#Requires -Version 5.1

using module ../Helpers.psm1

$ErrorActionPreference = 'Stop'

."$PSScriptRoot/../../Paths.ps1"
."$PSScriptRoot/../Paths.ps1"

Remove-Module -Name 'Helpers' -Force -ErrorAction 'SilentlyContinue'
Import-Module -Name $Helpers -DisableNameChecking

$Parameters = @{
  BindingVariable = 'Localization'
  BaseDirectory   = $Localizations
  FileName        = 'Strings'
}
Import-LocalizedData @Parameters

function Show-PairDeviceDialog {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param(
    [Windows.Window] $ParentWindow
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/PairDeviceDialog.xaml" -HideCaptionButtons

    $ViewModel = [ViewModel]::new()

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $Window.IpAdressBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.EnterIpAddress }
    $Window.IpAdressBox.Add_TextChanged({ $ViewModel.SetIpAddress($Window.IpAdressBox.Text) })

    $Window.PairingCodeBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.EnterPairingCode }
    $Window.PairingCodeBox.Add_TextChanged({ $ViewModel.SetPairingCode($Window.PairingCodeBox.Text) })

    if ($ParentWindow) { $Window.Owner = $ParentWindow }

    if ($Window.ShowDialog()) {
      @{
        IpAddress   = $ViewModel.IpAddress
        PairingCode = $ViewModel.PairingCode
      }
    }
  }
}

class ViewModel : ObservableObject {
  $OkCommand = [RelayCommand]::new(
    {
      $Window.DialogResult = $true
    },
    {
      $ViewModel.AreInputsValid()
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

  hidden [string] $PairingCode = ''
  [void] SetPairingCode($value) {
    if ($this.SetProperty('PairingCode', $value)) {
      $this.OkCommand.NotifyCanExecuteChanged()
    }
  }

  hidden $IpV4Regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?):(?:[1-9]\d{0,4}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'
  hidden $IpV6Regex = '^(?:(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}|(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}|(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(?:(?::[0-9a-fA-F]{1,4}){1,6})|:(?:(?::[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(?::[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(?:ffff(?::0{1,4}){0,1}:){0,1}(?:(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])|(?:[0-9a-fA-F]{1,4}:){1,4}:(?:(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9]))(?:]:(?:[1-9]\d{0,4}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5]))$'
  hidden $PairingCodeRegex = '^\d{6}$'
  hidden [bool] AreInputsValid() {
    return (
      ($this.PairingCode -match $this.PairingCodeRegex) -and
      (($this.IpAddress -match $this.IpV4Regex) -or ($this.IpAddress -match $this.IpV6Regex))
    )
  }
}
