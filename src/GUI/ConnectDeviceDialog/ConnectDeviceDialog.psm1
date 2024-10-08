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

function Show-ConnectDeviceDialog {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [System.Windows.Window] $ParentWindow
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    [xml]$xaml = Get-Content -Path "$PSScriptRoot/ConnectDeviceDialog.xaml"
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
      }
      process {
        $inputText = $IpAdressBox.Text
        $OkButton.IsEnabled = ($inputText -match $ipV4Regex) -or ($inputText -match $ipV6Regex)
      }
    }

    function Set-IpAdressBoxPlaceholderVisibility {
      [CmdletBinding()]
      param()
      process {
        $inputText = $IpAdressBox.Text

        if ($IpAdressBox.IsFocused) {
          if ($inputText -eq $Localization.EnterIpAddress) {
            $IpAdressBox.Foreground = $Window.FindResource('TextBrush')
            $IpAdressBox.Text = ''
          }
        }
        elseif ($inputText.Length -eq 0) {
          $IpAdressBox.Foreground = $Window.FindResource('InactiveTextBrush')
          $IpAdressBox.Text = $Localization.EnterIpAddress
        }
      }
    }

    function OnOkButtonClick {
      [CmdletBinding()]
      param()
      process {
        $script:ipAddress = $IpAdressBox.Text
        $Window.Close()
      }
    }

    $IpAdressBox.Add_TextChanged({ Set-OkButtonState })
    $IpAdressBox.Add_GotFocus({ Set-IpAdressBoxPlaceholderVisibility })
    $IpAdressBox.Add_LostFocus({ Set-IpAdressBoxPlaceholderVisibility })

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
        $Window.Activate()
      })

    Add-ColorStyles -Window $Window

    if ($ParentWindow) { $Window.Owner = $ParentWindow }
    $Window.ShowDialog() | Out-Null

    $ipAddress
  }
}
