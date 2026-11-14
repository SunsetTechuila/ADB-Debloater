#Requires -Version 5.1

using module ../Helpers.psm1

$ErrorActionPreference = 'Stop'

."$PSScriptRoot/../../Paths.ps1"
."$PSScriptRoot/../Paths.ps1"

$modules = @(
  'Helpers',
  'ConnectDeviceDialog',
  'PairDeviceDialog',
  'ProgressRingDialog',
  'MessageDialog'
)
Import-Module -Name (Get-Variable -Name $modules -ValueOnly) -Force -DisableNameChecking

$Parameters = @{
  BindingVariable = 'Localization'
  BaseDirectory   = $Localizations
  FileName        = 'Strings'
}
Import-LocalizedData @Parameters

function Show-DevicesDialog {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param(
    [Parameter(Mandatory)]
    [scriptblock]$WatchDevices,

    [Parameter(Mandatory)]
    [scriptblock]$ConnectDevice,

    [Parameter(Mandatory)]
    [scriptblock]$PairDevice,

    [string]$SelectedDeviceId
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/DevicesDialog.xaml"

    $ViewModel = [ViewModel]::new($SelectedDeviceId)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $Window.DevicesListView.add_SelectionChanged({
        $ViewModel.OnSelectionChanged()
      })

    $watchDevicesTask = [BackgroundTask]@{
      Operation  = $WatchDevices
      OnProgress = { param($devices) $ViewModel.UpdateDevices($devices) }
    }

    $watchDevicesTask.Start()
    $confirmed = $Window.ShowDialog()
    $watchDevicesTask.ForceStopAsync()

    if ($confirmed) {
      @{
        DeviceId   = $ViewModel.SelectedDevice.Id
        ActionName = $ViewModel.SelectedActionName
      }
    }
  }
}

class ViewModel : ObservableObject {
  $PairCommand = [RelayCommand]::new({
      $data = Show-PairDeviceDialog
      if (-not $data) { return }

      $Parameters = @{
        Message      = $Localization.Pairing
        Operation    = $PairDevice
        ArgumentList = $data.IpAddress, $data.PairingCode
      }
      try {
        Show-ProgressRingDialog @Parameters > $null
      }
      catch {
        $Parameters = @{
          Title   = $Localization.FailedToPair
          Message = $PSItem.Exception.Message
          Icon    = 'Error'
        }
        Show-MessageDialog @Parameters > $null
      }
    })

  $ConnectCommand = [RelayCommand]::new({
      $ipAddress = Show-ConnectDeviceDialog
      if (-not $ipAddress) { return }

      $Parameters = @{
        Message      = $Localization.Connecting
        Operation    = $ConnectDevice
        ArgumentList = $ipAddress
      }
      try {
        Show-ProgressRingDialog @Parameters > $null
      }
      catch {
        $Parameters = @{
          Title   = $Localization.FailedToConnect
          Message = $PSItem.Exception.Message
          Icon    = 'Error'
        }
        Show-MessageDialog @Parameters > $null
      }
    })

  $ChooseActionCommand = [RelayCommand]::new(
    {
      param($actionName)
      $ViewModel.SelectedActionName = $actionName
      $Window.DialogResult = $true
    },
    {
      $selectedDevice = $ViewModel.SelectedDevice
      $selectedDevice -and ($selectedDevice.Status -eq 'Connected')
    }
  )

  hidden $Devices = [Collections.ObjectModel.ObservableCollection[Device]]::new()
  [void] UpdateDevices([hashtable] $devices) {
    $this.SyncDevices($devices)
    $this.SortDevicesByStatus()
    $this.UpdateSelection()
  }

  hidden [void] SyncDevices([hashtable] $devices) {
    foreach ($existingDevice in @($this.Devices)) {
      $updatedDevice = $devices[$existingDevice.Id]
      if ($updatedDevice) {
        $existingDevice.SetModel($updatedDevice.Model)
        $didStatusChange = $existingDevice.SetStatus($updatedDevice.Status)
        if ($didStatusChange -and ($this.SelectedDevice -eq $existingDevice)) {
          $this.ChooseActionCommand.NotifyCanExecuteChanged()
        }
        $devices.Remove($existingDevice.Id)
      }
      else {
        $this.Devices.Remove($existingDevice)
      }
    }

    foreach ($device in $devices.GetEnumerator()) {
      $this.Devices.Add([Device]::new(
          $device.Key, $device.Value.Model, $device.Value.Status
        ))
    }
  }

  hidden [void] SortDevicesByStatus() {
    if ($this.Devices.Count -le 1) { return }

    $sortedDevices = @(
      $this.Devices | Sort-Object -Property { $PSItem.Status -ne 'Connected' }, Status, Id
    )
    for ($i = 0; $i -lt $sortedDevices.Count; $i++) {
      $oldIndex = $this.Devices.IndexOf($sortedDevices[$i])
      if ($oldIndex -ne $i) {
        $this.Devices.Move($oldIndex, $i)
      }
    }
  }

  hidden [void] UpdateSelection() {
    if ($this.SelectedDevice -or (-not $this.Devices.Count)) { return }

    if ($this.InitialSelectedDeviceId) {
      $targetDevice = $this.Devices | Where-Object -Property 'Id' -EQ $this.InitialSelectedDeviceId
      $this.InitialSelectedDeviceId = $null
      if ($targetDevice) {
        $this.SetSelectedDevice($targetDevice)
        return
      }
    }

    $firstDevice = $this.Devices[0]
    if ($firstDevice.Status -eq 'Connected') {
      $this.SetSelectedDevice($firstDevice)
    }
  }

  hidden [string] $InitialSelectedDeviceId

  hidden [Device] $SelectedDevice
  [void] SetSelectedDevice($value) {
    $this.SetProperty('SelectedDevice', $value)
  }

  hidden [string] $SelectedActionName

  ViewModel([string] $initialSelectedDeviceId) {
    $this.InitialSelectedDeviceId = $initialSelectedDeviceId
  }

  [void] OnSelectionChanged() {
    $this.ChooseActionCommand.NotifyCanExecuteChanged()
  }
}

class Device : ObservableObject {
  [string] $Id

  [string] $Model
  # Model changes from unknown to a specific value when status changes from offline/unauthorized
  [void] SetModel($value) {
    $this.SetProperty('Model', $value)
  }

  [string] $Status
  [bool] SetStatus($status) {
    $formattedStatus = $status.Substring(0, 1).ToUpper() + $status.Substring(1).ToLower()
    $statusChanged = $this.SetProperty('Status', $formattedStatus)
    if ($statusChanged) {
      $this.UpdateHint()
    }
    return $statusChanged
  }

  [string] $Hint
  hidden [void] UpdateHint() {
    $newHint = switch -Regex ($this.Status) {
      'Offline' {
        $script:Localization.DeviceReconnectInstruction
        break
      }
      'Bootloader|Recovery|Sideload' {
        $script:Localization.DeviceRebootInstruction
        break
      }
      'Unauthorized' {
        $script:Localization.DeviceAuthorizeInstruction
        break
      }
      default {
        $null
      }
    }
    $this.SetProperty('Hint', $newHint)
  }

  Device(
    [string] $id,
    [string] $model,
    [string] $status
  ) {
    $this.Id = $id
    $this.Model = $model
    $this.SetStatus($status)
  }
}
