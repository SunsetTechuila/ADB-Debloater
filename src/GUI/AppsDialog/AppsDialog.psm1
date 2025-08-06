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

function Show-AppsDialog {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [ValidateSet('uninstall', 'disable', 'enable', 'reinstall')]
    [string]$ActionName,

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

    [xml]$xaml = Get-Content -Path "$PSScriptRoot/AppsDialog.xaml"
    $xaml = Add-FluentStyles -Xaml $xaml
    $reader = (New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
      Set-Variable -Name ($PSItem.Name) -Value $Window.FindName($PSItem.Name)
    }
    Set-WindowStyling -Window $Window -NoTopBar -SetWindowMaxHeight

    function Get-CheckBoxes {
      [CmdletBinding()]
      [OutputType([System.Windows.Controls.CheckBox[]])]
      param(
        [switch]$OnlyVisible
      )
      process {
        foreach ($AppRow in $AppsContainer.Children) {
          $AppRow.Children | Where-Object -FilterScript {
            $isCheckBox = $PSItem -is [System.Windows.Controls.CheckBox]
            $isVisible = $PSItem.Parent.Visibility -eq 'Visible'

            if ($OnlyVisible) { $isCheckBox -and $isVisible }
            else { $isCheckBox }
          }
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

        foreach ($AppRow in $AppsContainer.Children) {
          $CheckBox = $AppRow.Children | Where-Object -FilterScript { $PSItem -is [System.Windows.Controls.CheckBox] }
          if ($CheckBox) {
            if (($CheckBox.Content.ToLower().Contains($searchText)) -or ($searchText.Length -eq 0)) {
              $AppRow.Visibility = 'Visible'
            }
            else {
              $AppRow.Visibility = 'Collapsed'
            }
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
    $ActionButton.Content = $Localization.$ActionName

    for ($i = 0; $i -lt $Apps.Count; $i++) {
      $app = $Apps[$i]
      $nextApp = $Apps[$i + 1]

      $AppRow = New-Object -TypeName 'System.Windows.Controls.StackPanel'
      $AppRow.Orientation = 'Horizontal'
      $AppRow.VerticalAlignment = 'Center'
      if ($nextApp) { $AppRow.Margin = '0,0,0,12' }

      $CheckBox = New-Object -TypeName 'System.Windows.Controls.CheckBox'
      $CheckBox.Content = $app.Name
      $CheckBox.Tag = $app.Packages
      $CheckBox.ToolTip = $app.Packages -join "`n"
      $CheckBox.IsChecked = $false

      $CheckBox.Add_Click({ OnCheckBoxClick })
      
      $AppRow.Children.Add($CheckBox) | Out-Null
      $AppsContainer.Children.Add($AppRow) | Out-Null

      if ($app.Description) {
        $HelpIcon = New-Object -TypeName 'System.Windows.Controls.ContentControl'
        $HelpIcon.Style = $Window.FindResource('HelpIcon')
        $HelpIcon.Margin = '8,0,0,0'
        $HelpIcon.ToolTip = $app.Description

        $AppRow.Children.Add($HelpIcon) | Out-Null
      }
    }

    $SearchBox.Add_TextChanged({ OnSearchTextChange })
    $SearchBox.Add_GotFocus({ Set-SearchBoxPlaceholderVisibility })
    $SearchBox.Add_LostFocus({ Set-SearchBoxPlaceholderVisibility })
    $SelectAllCheckBox.Add_Click({ OnSelectAllClick })
    $ActionButton.Add_Click({ OnActionButtonClick })

    $Window.Add_Loaded({
        Set-SearchBoxPlaceholderVisibility
      })
    $Window.Add_ContentRendered({
        # prevents the window from resizing on search
        $Window.SizeToContent = 'Manual'
        #removes scrollbar
        $Window.Height = $Window.ActualHeight + 1
      })

    $Window.ShowDialog() | Out-Null
  }
}
