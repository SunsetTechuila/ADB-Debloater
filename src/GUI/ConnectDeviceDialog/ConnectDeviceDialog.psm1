#Requires -Version 5.1

using module ../Helpers.psm1

$ErrorActionPreference = 'Stop'

."$PSScriptRoot/../../Paths.ps1"
."$PSScriptRoot/../Paths.ps1"

Import-Module -Name $Helpers -Force -DisableNameChecking

$Parameters = @{
  BindingVariable = 'Localization'
  BaseDirectory   = $Localizations
  FileName        = 'Strings'
}
Import-LocalizedData @Parameters

function Show-ConnectDeviceDialog {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Windows.Window] $ParentWindow
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/ConnectDeviceDialog.xaml" -HideCaptionButtons

    $ViewModel = [ViewModel]::new()

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $Window.IpAdressBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.EnterIpAddress }
    $Window.IpAdressBox.Add_TextChanged({ $ViewModel.SetIpAddress($Window.IpAdressBox.Text) })

    if ($ParentWindow) { $Window.Owner = $ParentWindow }

    if ($Window.ShowDialog()) {
      $ViewModel.IpAddress
    }
  }
}

class ViewModel : ObservableObject {
  $OkCommand = [RelayCommand]::new(
    {
      $Window.DialogResult = $true
    },
    {
      $ViewModel.IsIpAddressValid()
    }
  )

  $CancelCommand = [RelayCommand]::new({
      $Window.Close()
    })

  hidden [string] $IpAddress = ''
  [void] SetIpAddress($value) {
    if ($this.SetProperty('IpAddress', $value)) {
      $this.OkCommand.NotifyCanExecuteChanged()
    }
  }

  hidden $IpV4Regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?):(?:[1-9]\d{0,4}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'
  hidden $IpV6Regex = '^(?:(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}|(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}|(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(?:(?::[0-9a-fA-F]{1,4}){1,6})|:(?:(?::[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(?::[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(?:ffff(?::0{1,4}){0,1}:){0,1}(?:(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])|(?:[0-9a-fA-F]{1,4}:){1,4}:(?:(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9]))(?:]:(?:[1-9]\d{0,4}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5]))$'
  hidden [bool] IsIpAddressValid() {
    return ($this.IpAddress -match $this.IpV4Regex) -or ($this.IpAddress -match $this.IpV6Regex)
  }
}
