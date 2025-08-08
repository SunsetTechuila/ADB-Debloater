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
    [xml]$xaml = Get-Content -Path "$PSScriptRoot/AppsDialog.xaml"
    $xaml = Add-FluentStyles -Xaml $xaml
    $reader = (New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
      Set-Variable -Name ($PSItem.Name) -Value $Window.FindName($PSItem.Name)
    }
    Set-WindowStyling -Window $Window -NoTopBar -SetWindowMaxHeight

    $OnActionButtonClick = {
      [CmdletBinding()]
      param()
      process {
        $Window.Close()
        $packages = $AppsViewModel.GetSelectedPackages()
        $Action.Invoke($packages, $DeviceId)
      }
    }

    $OnSearchTextChanged = {
      [CmdletBinding()]
      param($eventSender)
      process {
        $AppsViewModel.FilterAppsByName($eventSender.Text)
        $AppsViewModel.UpdateSelectionFlags()
      }
    }

    $AppItems = @(
      foreach ($app in $Apps) {
        [AppItem]::new($app.Name, $app.Packages, $app.Description)
      }
    )
    $AppsViewModel = [AppsViewModel]::new($AppItems)
    $Window.DataContext = [PSCustomObject]@{
      AppsViewModel = $AppsViewModel
      Localization  = $Localization
      ActionLabel   = $Localization.$ActionName
    }

    $AppsContainer.AddHandler(
      [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent,
      [System.Windows.RoutedEventHandler] {
        $AppsViewModel.UpdateSelectionFlags()
      })
    $AppsContainer.AddHandler(
      [System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,
      [System.Windows.RoutedEventHandler] {
        $AppsViewModel.UpdateSelectionFlags()
      })

    $SearchBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.Search }
    $SearchBox.Add_TextChanged($OnSearchTextChanged)
    $SelectAllCheckBox.Add_Click({ $AppsViewModel.ToggleVisibleAppItemsSelection() })
    $ActionButton.Add_Click($OnActionButtonClick)

    $Window.Add_ContentRendered({
        # prevents the window from resizing on search
        $Window.SizeToContent = 'Manual'
        #removes scrollbar
        $Window.Height = $Window.ActualHeight + 1
      })

    $Window.ShowDialog() | Out-Null
  }
}

class AppsViewModel : INotifyPropertyChanged {
  [AppItem[]] $AppItems
  [bool] $HasAnyVisibleAppItem = $false
  [bool] $HasAnyAppItemSelected = $false
  [bool] $AreAllVisibleAppItemsSelected = $false

  AppsViewModel([AppItem[]] $appItems) {
    $this.AppItems = $appItems
  }

  hidden [void] UpdateSelectionFlags() {
    $anySelected = $false
    $allVisibleSelected = $true
    $hasAnyVisible = $false

    foreach ($appItem in $this.AppItems) {
      if ($appItem.IsSelected) { $anySelected = $true }
      if ($appItem.IsVisible) {
        $hasAnyVisible = $true
        if (-not $appItem.IsSelected) { $allVisibleSelected = $false }
      }
    }

    $this.HasAnyVisibleAppItem = $hasAnyVisible
    $this.HasAnyAppItemSelected = $anySelected
    $this.AreAllVisibleAppItemsSelected = ($hasAnyVisible -and $allVisibleSelected)

    $this.OnPropertyChanged('HasAnyVisibleAppItem')
    $this.OnPropertyChanged('HasAnyAppItemSelected')
    $this.OnPropertyChanged('AreAllVisibleAppItemsSelected')
  }

  [void] FilterAppsByName([string] $searchText) {
    if ($searchText.Equals('Search')) { return }
    $searchTextLowered = $searchText.ToLower()
    foreach ($appItem in $this.AppItems) {
      $appItem.SetIsVisible($appItem.Name.ToLower().Contains($searchTextLowered) -or $appItem.Packages.Contains($searchTextLowered))
    }
  }

  [void] ToggleVisibleAppItemsSelection() {
    $shouldSelect = -not $this.AreAllVisibleAppItemsSelected
    foreach ($appItem in $this.AppItems) {
      if ($appItem.IsVisible) { $appItem.SetIsSelected($shouldSelect) }
    }
  }

  [string[]] GetSelectedPackages() {
    [System.Collections.ArrayList]$selectedPackages = @()
    foreach ($app in $this.AppItems) {
      if ($app.IsSelected) {
        foreach ($package in $app.Packages) { $selectedPackages.Add($package) }
      }
    }
    return $selectedPackages
  }
}

class AppItem : INotifyPropertyChanged {
  [string] $Name
  [string[]] $Packages
  [bool] $IsSelected = $false
  [bool] $IsVisible = $true
  hidden [string] $HelpMessage
  hidden [string] $PackagesString

  AppItem(
    [string] $name,
    [string[]] $packages,
    [string] $helpMessage
  ) {
    $this.Name = $name
    $this.Packages = $packages
    $this.HelpMessage = $helpMessage
    $this.PackagesString = ($packages -join "`n")
  }

  [void] SetIsSelected([bool] $value) {
    if ($this.IsSelected -ne $value) {
      $this.IsSelected = $value
      $this.OnPropertyChanged('IsSelected')
    }
  }

  [void] SetIsVisible([bool] $value) {
    if ($this.IsVisible -ne $value) {
      $this.IsVisible = $value
      $this.OnPropertyChanged('IsVisible')
    }
  }
}
