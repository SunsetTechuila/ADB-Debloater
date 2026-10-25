#Requires -Version 5.1
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
    [System.Windows.Window] $ParentWindow
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/PairDeviceDialog.xaml" -HideCloseButton

    function Set-OkButtonState {
      [CmdletBinding()]
      param()
      begin {
        $ipV4Regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?):(?:[1-9]\d{0,4}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'
        $ipV6Regex = '^(?:(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}|(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}|(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(?:(?::[0-9a-fA-F]{1,4}){1,6})|:(?:(?::[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(?::[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(?:ffff(?::0{1,4}){0,1}:){0,1}(?:(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])|(?:[0-9a-fA-F]{1,4}:){1,4}:(?:(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9]))(?:]:(?:[1-9]\d{0,4}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5]))$'
        $pairingCodeRegex = '^\d{6}$'
      }
      process {
        $ipAddressInput = $Window.IpAdressBox.Text
        $pairingCodeInput = $Window.PairingCodeBox.Text
        $Window.OkButton.IsEnabled = (($ipAddressInput -match $ipV4Regex) -or ($ipAddressInput -match $ipV6Regex)) -and ($pairingCodeInput -match $pairingCodeRegex)
      }
    }

    function OnOkButtonClick {
      [CmdletBinding()]
      param()
      process {
        $script:ipAddress = $Window.IpAdressBox.Text
        $script:pairingCode = $Window.PairingCodeBox.Text
        $Window.Close()
      }
    }

    $Window.IpAdressBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.EnterIpAddress }
    $Window.IpAdressBox.Add_TextChanged({ Set-OkButtonState })

    $Window.PairingCodeBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.EnterPairingCode }
    $Window.PairingCodeBox.Add_TextChanged({ Set-OkButtonState })

    $Window.OkButton.Content = $Localization.Ok
    $Window.OkButton.Add_Click({ OnOkButtonClick })
    $Window.CancelButton.Content = $Localization.Cancel
    $Window.CancelButton.Add_Click({ $Window.Close() })

    $Window.Add_KeyDown({
        switch -Exact ($PSItem.Key) {
          'Enter' {
            if ($Window.OkButton.IsEnabled) { OnOkButtonClick }
            break
          }
          'Escape' {
            $Window.Close()
            break
          }
        }
      })

    if ($ParentWindow) { $Window.Owner = $ParentWindow }
    $Window.ShowDialog() | Out-Null

    if ((-not $ipAddress) -or (-not $pairingCode)) { return }
    @{
      IpAddress   = $ipAddress
      PairingCode = $pairingCode
    }
  }
}
