#Requires -Version 5.1

using module ../Helpers.psm1

$ErrorActionPreference = 'Stop'

."$PSScriptRoot/../../Paths.ps1"
."$PSScriptRoot/../Paths.ps1"

@(
  'Helpers',
  'ConnectDeviceDialog'
  'PairDeviceDialog'
) | ForEach-Object -Process {
  Remove-Module -Name $PSItem -Force -ErrorAction 'SilentlyContinue'
  Import-Module -Name (Get-Variable -Name $PSItem -ValueOnly) -DisableNameChecking
}

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
    [scriptblock]$GetDevices,

    [Parameter(Mandatory)]
    [scriptblock]$ConnectDevice,

    [Parameter(Mandatory)]
    [scriptblock]$PairDevice
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/DevicesDialog.xaml" -NoTopBar -SetWindowMaxHeight

    $ViewModel = [ViewModel]::new($GetDevices)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $Window.DevicesListView.add_SelectionChanged({
        $ViewModel.OnSelectionChanged()
      })

    if ($Window.ShowDialog()) {
      @{
        DeviceId   = $ViewModel.SelectedDevice.Id
        ActionName = $ViewModel.SelectedActionName
      }
    }
  }
}

class ViewModel : ObservableObject {
  $RefreshCommand = [RelayCommand]::new({
      $ViewModel.RefreshDevices()
    })

  $PairCommand = [RelayCommand]::new({
      $data = Show-PairDeviceDialog -ParentWindow $Window
      if ($data) { $PairDevice.Invoke($data.IpAddress, $data.PairingCode) }
    })

  $ConnectCommand = [RelayCommand]::new({
      $ipAddress = Show-ConnectDeviceDialog -ParentWindow $Window
      if (-not $ipAddress) { return }
      $ConnectDevice.Invoke($ipAddress)
      $ViewModel.RefreshDevices()
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

  hidden [Device[]] $Devices
  hidden [void] SetDevices($value) {
    $this.SetProperty('Devices', $value)
  }

  hidden [Device] $SelectedDevice
  [void] SetSelectedDevice($value) {
    $this.SetProperty('SelectedDevice', $value)
  }

  hidden [string] $SelectedActionName

  hidden [scriptblock] $GetDevices

  ViewModel($getDevices) {
    $this.GetDevices = $getDevices
    $this.RefreshDevices()
  }

  [void] RefreshDevices() {
    $this.SetDevices($(
        foreach ($device in $this.GetDevices.Invoke()) {
          [Device]::new($device.Id, $device.Model, $device.Status)
        }
      ))
    $this.SetSelectedDevice(
      $(if ($this.Devices.Count) { $this.Devices[0] })
    )
  }

  [void] OnSelectionChanged() {
    $this.ChooseActionCommand.NotifyCanExecuteChanged()
  }
}

class Device {
  [string] $Id

  [string] $Model

  [string] $Status

  [string] $Hint

  Device(
    [string] $id,
    [string] $model,
    [string] $status
  ) {
    $this.Id = $id
    $this.Model = $model
    $this.Status = $status.Substring(0, 1).ToUpper() + $status.Substring(1).ToLower()
    $this.Hint = switch -Regex ($status) {
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
  }
}
