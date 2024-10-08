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

function Show-PackagesDialog {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [ValidateSet('uninstall', 'disable', 'enable')]
    [string]$ActionType,

    [Parameter(Mandatory)]
    [scriptblock]$Action,

    [Parameter(Mandatory)]
    [array]$Apps,

    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    [System.Collections.ArrayList]$packagesToProcess = @()

    [xml]$xaml = Get-Content -Path "$PSScriptRoot/PackagesDialog.xaml"
    $xaml = Add-FluentStyles -Xaml $xaml
    $reader = (New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
      Set-Variable -Name ($PSItem.Name) -Value $Window.FindName($PSItem.Name)
    }

    function Get-CheckBoxes {
      [CmdletBinding()]
      [OutputType([System.Windows.Controls.CheckBox[]])]
      param(
        [switch]$OnlyVisible
      )
      process {
        $CheckBoxesContainer.Children | Where-Object -FilterScript {
          $isCheckBox = $PSItem -is [System.Windows.Controls.CheckBox]
          $isVisible = $PSItem.Visibility -eq 'Visible'

          if ($OnlyVisible) { $isCheckBox -and $isVisible }
          else { $isCheckBox }
        }
      }
    }

    function Set-ActionButtonState {
      [CmdletBinding()]
      param()
      process {
        $ActionButton.IsEnabled = $packagesToProcess.Count -gt 0
      }
    }

    function Set-SelectAllCheckBoxState {
      [CmdletBinding()]
      param()
      process {
        $foundNotChecked = $false
        $hasVisibleCheckBoxes = $false

        foreach ($checkBox in Get-CheckBoxes -OnlyVisible) {
          $hasVisibleCheckBoxes = $true
          if (-not $checkBox.IsChecked) {
            $foundNotChecked = $true
            break
          }
        }

        $SelectAllCheckBox.IsChecked = (-not $foundNotChecked) -and ($hasVisibleCheckBoxes)
      }
    }

    function OnCheckBoxClick {
      [CmdletBinding()]
      param()
      begin {
        $CheckBox = $PSItem.Source
      }
      process {
        if ($CheckBox.IsChecked) {
          foreach ($package in $CheckBox.Tag) {
            if ($package -notin $packagesToProcess) {
              $packagesToProcess.Add($package)
            }
          }
        }
        else {
          foreach ($package in $CheckBox.Tag) {
            $packagesToProcess.Remove($package)
          }
        }

        Set-SelectAllCheckBoxState
        Set-ActionButtonState
      }
    }

    function OnSelectAllClick {
      [CmdletBinding()]
      param()
      begin {
        $SelectAllCheckBox = $PSItem.Source
      }
      process {
        foreach ($CheckBox in Get-CheckBoxes -OnlyVisible) {
          if ($SelectAllCheckBox.IsChecked) {
            $CheckBox.IsChecked = $true
            foreach ($package in $CheckBox.Tag) {
              if ($package -notin $packagesToProcess) {
                $packagesToProcess.Add($package)
              }
            }
          }
          else {
            $CheckBox.IsChecked = $false
            foreach ($package in $CheckBox.Tag) {
              $packagesToProcess.Remove($package)
            }
          }
        }

        # make it unchecked if there are no visible checkboxes
        Set-SelectAllCheckBoxState
        Set-ActionButtonState
      }
    }

    function OnActionButtonClick {
      [CmdletBinding()]
      param()
      process {
        $Window.Close()
        $Action.Invoke($packagesToProcess, $DeviceId)
      }
    }

    function OnSearchTextChange {
      [CmdletBinding()]
      param()
      begin {
        $searchText = $PSItem.Source.Text.ToLower()
      }
      process {
        if ($searchText -eq $Localization.Search) { return }

        foreach ($CheckBox in Get-CheckBoxes) {
          if (($CheckBox.Content.ToLower().Contains($searchText)) -or ($searchText.Length -eq 0)) {
            $CheckBox.Visibility = 'Visible'
          }
          else {
            $CheckBox.Visibility = 'Collapsed'
          }
        }

        Set-SelectAllCheckBoxState
      }
    }

    function Set-SearchBoxPlaceholderVisibility {
      [CmdletBinding()]
      param()
      process {
        $searchText = $SearchBox.Text

        if ($SearchBox.IsFocused) {
          if ($searchText -eq $Localization.Search) {
            $SearchBox.Foreground = $Window.FindResource('TextBrush')
            $SearchBox.Text = ''
          }
        }
        elseif ($searchText.Length -eq 0) {
          $SearchBox.Foreground = $Window.FindResource('InactiveTextBrush')
          $SearchBox.Text = $Localization.Search
        }
      }
    }

    $SelectAllCheckBox.Content = $Localization.SelectAll
    $ActionButton.Content = $Localization.$ActionType

    for ($i = 0; $i -lt $Apps.Count; $i++) {
      $app = $Apps[$i]
      $nextApp = $Apps[$i + 1]

      $CheckBox = New-Object -TypeName 'System.Windows.Controls.CheckBox'
      $CheckBox.Content = $app.Name
      $CheckBox.Tag = $app.Packages
      $CheckBox.ToolTip = $app.Description
      if ($nextApp) { $CheckBox.Margin = '0,0,0,12' }
      $CheckBox.IsChecked = $false

      $CheckBox.Add_Click({ OnCheckBoxClick })
      $CheckBoxesContainer.Children.Add($CheckBox) | Out-Null
    }

    $SearchBox.Add_TextChanged({ OnSearchTextChange })
    $SearchBox.Add_GotFocus({ Set-SearchBoxPlaceholderVisibility })
    $SearchBox.Add_LostFocus({ Set-SearchBoxPlaceholderVisibility })
    $SelectAllCheckBox.Add_Click({ OnSelectAllClick })
    $ActionButton.Add_Click({ OnActionButtonClick })

    $shouldSetMicaBackdrop = Test-DwmBackdropApiAvailability
    $shouldSetImmersiveDarkMode = Test-DwmImmersiveDarkModeApiAvailability

    if ($shouldSetMicaBackdrop) {
      $Window.Add_Loaded({ Set-MicaBackdrop -Window $Window })
      Set-ContentBorderThickness -Border $ContentBorder -NoTopBar

      $targetThickness = $ContentBorder.BorderThickness
      function Adjust-ContentBorderThickness {
        $Parameters = @{
          TargetThickness = $targetThickness
          WindowState     = $Window.WindowState
        }
        $ContentBorder.BorderThickness = Get-ContentBorderAdjustedThickness @Parameters
      }
      $Window.Add_StateChanged({ Adjust-ContentBorderThickness })
      Adjust-ContentBorderThickness
    }
    else {
      Set-ContentBorderThickness -Border $ContentBorder
      if ($shouldSetImmersiveDarkMode) {
        $Window.Add_Loaded({ Set-ImmersiveDarkMode -Window $Window })
      }
    }

    $Window.Add_Loaded({
        Set-SearchBoxPlaceholderVisibility
        $Window.Activate()
      })
    $Window.Add_ContentRendered({
        # prevents the window from resizing on search
        $Window.SizeToContent = 'Manual'
        #removes scrollbar
        $Window.Height = $Window.ActualHeight + 1
      })

    Add-ColorStyles -Window $Window
    Set-WindowMaxHeight -Window $Window

    $Window.ShowDialog() | Out-Null
  }
}
