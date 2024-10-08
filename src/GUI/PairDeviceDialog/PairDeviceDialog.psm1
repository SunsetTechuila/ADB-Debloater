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

    function Set-TextBoxPlaceholderVisibility {
      [CmdletBinding()]
      param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBox] $TextBox,

        [Parameter(Mandatory)]
        [string] $Placeholder
      )
      process {
        $inputText = $TextBox.Text

        if ($TextBox.IsFocused) {
          if ($inputText -eq $Placeholder) {
            $TextBox.Foreground = $Window.FindResource('TextBrush')
            $TextBox.Text = ''
          }
        }
        elseif ($inputText.Length -eq 0) {
          $TextBox.Foreground = $Window.FindResource('InactiveTextBrush')
          $TextBox.Text = $Placeholder
        }
      }
    }

    function Set-IpAdressBoxPlaceholderVisibility {
      [CmdletBinding()]
      param()
      begin {
        $Parameters = @{
          TextBox     = $IpAdressBox
          Placeholder = $Localization.EnterIpAddress
        }
      }
      process {
        Set-TextBoxPlaceholderVisibility @Parameters
      }
    }

    function Set-PairingCodeBoxPlaceholderVisibility {
      [CmdletBinding()]
      param()
      begin {
        $Parameters = @{
          TextBox     = $PairingCodeBox
          Placeholder = $Localization.EnterPairingCode
        }
      }
      process {
        Set-TextBoxPlaceholderVisibility @Parameters
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

    $IpAdressBox.Add_TextChanged({ Set-OkButtonState })
    $IpAdressBox.Add_GotFocus({ Set-IpAdressBoxPlaceholderVisibility })
    $IpAdressBox.Add_LostFocus({ Set-IpAdressBoxPlaceholderVisibility })

    $PairingCodeBox.Add_TextChanged({ Set-OkButtonState })
    $PairingCodeBox.Add_GotFocus({ Set-PairingCodeBoxPlaceholderVisibility })
    $PairingCodeBox.Add_LostFocus({ Set-PairingCodeBoxPlaceholderVisibility })

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

    $shouldSetMicaBackdrop = Test-DwmBackdropApiAvailability
    $shouldSetImmersiveDarkMode = Test-DwmImmersiveDarkModeApiAvailability

    Set-ContentBorderThickness -Border $ContentBorder

    if ($shouldSetMicaBackdrop) {
      $Window.Add_Loaded({ Set-MicaBackdrop -Window $Window })

      $Parameters = @{
        TargetThickness = $ContentBorder.BorderThickness
        WindowState     = $Window.WindowState
      }
      $ContentBorder.BorderThickness = Get-ContentBorderAdjustedThickness @Parameters
    }
    else {
      Set-ContentBorderThickness -Border $ContentBorder
      if ($shouldSetImmersiveDarkMode) {
        $Window.Add_Loaded({ Set-ImmersiveDarkMode -Window $Window })
      }
    }

    $Window.Add_SourceInitialized({ Hide-CloseButton -Window $Window })
    $Window.Add_Loaded({
        Set-IpAdressBoxPlaceholderVisibility
        Set-PairingCodeBoxPlaceholderVisibility
        $Window.Activate()
      })

    Add-ColorStyles -Window $Window

    if ($ParentWindow) { $Window.Owner = $ParentWindow }
    $Window.ShowDialog() | Out-Null

    if ((-not $ipAddress) -or (-not $pairingCode)) { return }
    @{
      IpAddress   = $ipAddress
      PairingCode = $pairingCode
    }
  }
}
