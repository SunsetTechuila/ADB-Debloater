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
    [xml]$xaml = Get-Content -Path "$PSScriptRoot/PairDeviceDialog.xaml"
    $xaml = Add-FluentStyles -Xaml $xaml
    $reader = (New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
      Set-Variable -Name ($PSItem.Name) -Value $Window.FindName($PSItem.Name)
    }
    Set-WindowStyling -Window $Window -HideCloseButton

    function Set-OkButtonState {
      [CmdletBinding()]
      param()
      begin {
        $ipV4Regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?):(?:[1-9]\d{0,4}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'
        $ipV6Regex = '^(?:(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}|(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}|(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(?:(?::[0-9a-fA-F]{1,4}){1,6})|:(?:(?::[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(?::[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(?:ffff(?::0{1,4}){0,1}:){0,1}(?:(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])|(?:[0-9a-fA-F]{1,4}:){1,4}:(?:(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(?:25[0-5]|(?:2[0-4]|1{0,1}[0-9]){0,1}[0-9]))(?:]:(?:[1-9]\d{0,4}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5]))$'
        $pairingCodeRegex = '^\d{6}$'
      }
      process {
        $ipAddressInput = $IpAdressBox.Text
        $pairingCodeInput = $PairingCodeBox.Text
        $OkButton.IsEnabled = (($ipAddressInput -match $ipV4Regex) -or ($ipAddressInput -match $ipV6Regex)) -and ($pairingCodeInput -match $pairingCodeRegex)
      }
    }

    function OnOkButtonClick {
      [CmdletBinding()]
      param()
      process {
        $script:ipAddress = $IpAdressBox.Text
        $script:pairingCode = $PairingCodeBox.Text
        $Window.Close()
      }
    }

    $IpAdressBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.EnterIpAddress }
    $IpAdressBox.Add_TextChanged({ Set-OkButtonState })

    $PairingCodeBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.EnterPairingCode }
    $PairingCodeBox.Add_TextChanged({ Set-OkButtonState })

    $OkButton.Content = $Localization.Ok
    $OkButton.Add_Click({ OnOkButtonClick })
    $CancelButton.Content = $Localization.Cancel
    $CancelButton.Add_Click({ $Window.Close() })

    $Window.Add_KeyDown({
        switch -Exact ($PSItem.Key) {
          'Enter' {
            if ($OkButton.IsEnabled) { OnOkButtonClick }
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
