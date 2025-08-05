#Requires -Version 5.1
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

    function Set-Devices {
      [CmdletBinding()]
      param()
      process {
        $DevicesListView.ItemsSource = @($GetDevices.Invoke() | ForEach-Object -Process {
            $hint = switch -Regex ($PSItem.Status) {
              'Offline' {
                $Localization.DeviceReconnectInstruction
                break
              }
              'Bootloader|Recovery|Sideload' {
                $Localization.DeviceRebootInstruction
                break
              }
              'Unauthorized' {
                $Localization.DeviceAuthorizeInstruction
                break
              }
              Default {
                $null
              }
            }
            $status = $PSItem.Status.Substring(0, 1).ToUpper() + $PSItem.Status.Substring(1).ToLower()

            [PSCustomObject]@{
              Id     = $PSItem.Id
              Model  = $PSItem.Model
              Status = $status
              Hint   = $hint
            }
          })

        $DevicesListView.SelectedIndex = 0
      }
    }

    function OnSelectionChange {
      [CmdletBinding()]
      param()
      begin {
        $selectedItem = $PSItem.Source.SelectedItem
      }
      process {
        $isDeviceConnected = $selectedItem.Status -eq 'Connected'

        @($UninstallButton, $DisableButton, $EnableButton, $ReinstallButton) | ForEach-Object -Process {
          $PSItem.IsEnabled = $isDeviceConnected
        }
      }
    }

    function Set-Choice {
      [CmdletBinding()]
      param()
      begin {
        $actionName = $PSItem.Source.Tag
      }
      process {
        $choice.DeviceId = $DevicesListView.SelectedItem.Id
        $choice.ActionName = $actionName
        $Window.Close()
      }
    }

    function OnConnectButtonClick {
      [CmdletBinding()]
      param()
      process {
        $ipAddress = Show-ConnectDeviceDialog -ParentWindow $Window
        if (-not $ipAddress) { return }
        $ConnectDevice.Invoke($ipAddress)
        Set-Devices
      }
    }

    function OnPairButtonClick {
      [CmdletBinding()]
      param()
      process {
        $data = Show-PairDeviceDialog -ParentWindow $Window
        if (-not $data.Count) { return }
        $PairDevice.Invoke($data.IpAddress, $data.PairingCode)
      }
    }

    $DevicesTextBlock.Text = $Localization.Devices
    $ConnectButton.ToolTip = $Localization.ConnectDeviceOverWiFi
    $ConnectButton.Add_Click({ OnConnectButtonClick })
    $PairButton.ToolTip = $Localization.PairDeviceOverWiFi
    $PairButton.Add_Click({ OnPairButtonClick })
    $RefreshButton.ToolTip = $Localization.RefreshDevicesList
    $RefreshButton.Add_Click({ Set-Devices })

    $UninstallButton.Content = $Localization.UninstallApps
    $UninstallButton.Tag = 'uninstall'
    $UninstallButton.Add_Click({ Set-Choice })

    $DisableButton.Content = $Localization.DisableApps
    $DisableButton.Tag = 'disable'
    $DisableButton.Add_Click({ Set-Choice })

    $EnableButton.Content = $Localization.EnableApps
    $EnableButton.Tag = 'enable'
    $EnableButton.Add_Click({ Set-Choice })

    $ReinstallButton.Content = $Localization.ReinstallApps
    $ReinstallButton.Tag = 'reinstall'
    $ReinstallButton.Add_Click({ Set-Choice })

    $DeviceModelColumn.Header = $Localization.DeviceModel
    $DeviceStatusColumn.Header = $Localization.DeviceStatus
    $DeviceIdColumn.Header = $Localization.DeviceId
    $DevicesListView.Add_SelectionChanged({ OnSelectionChange })
    Set-Devices

    $Window.Add_KeyDown({
        if ($PSItem.Key -eq 'F5') { Set-Devices }
      })

    $Window.ShowDialog() | Out-Null

    $choice
  }
}
