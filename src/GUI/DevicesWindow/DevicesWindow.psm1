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

function Show-DevicesWindow {
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
    $choice = @{}

    [xml]$xaml = Get-Content -Path "$PSScriptRoot/DevicesWindow.xaml"
    $xaml = Add-FluentStyles -Xaml $xaml
    $reader = (New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
      Set-Variable -Name ($PSItem.Name) -Value $Window.FindName($PSItem.Name)
    }
    Set-WindowStyling -Window $Window -NoTopBar -SetWindowMaxHeight

    $ViewModel = [ViewModel]::new($GetDevices)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $DevicesListView.add_SelectionChanged({
        $ViewModel.SetSelectedDevice($DevicesListView.SelectedItem)
        $ViewModel.OnSelectionChanged()
      })

    $Window.ShowDialog() | Out-Null

    $choice
  }
}

class ViewModel : ObservableObject {
  $RefreshCommand = [RelayCommand]::new({
      $ViewModel.RefreshDevices()
    })

  $PairCommand = [RelayCommand]::new({
      $data = Show-PairDeviceDialog -ParentWindow $Window
      if (-not $data.Count) { return }
      $PairDevice.Invoke($data.IpAddress, $data.PairingCode)
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
      $choice.DeviceId = $ViewModel.SelectedDevice.Id
      $choice.ActionName = $actionName
      $Window.Close()
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
