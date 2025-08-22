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
    $reader = (New-Object -TypeName 'Xml.XmlNodeReader' -ArgumentList $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
      Set-Variable -Name ($PSItem.Name) -Value $Window.FindName($PSItem.Name)
    }
    Set-WindowStyling -Window $Window -NoTopBar -SetWindowMaxHeight

    $appItems = @(
      foreach ($app in $Apps) {
        [AppItem]::new($app.Name, $app.Packages, $app.Description)
      }
    )
    $ViewModel = [ViewModel]::new($appItems)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
      ActionLabel  = $Localization.$ActionName
    }

    $AppsListView.add_SelectionChanged({ $ViewModel.OnSelectionChanged() })

    $OnSearchTextChanged = {
      param($eventSender)
      $ViewModel.FilterApps($eventSender.Text)
    }
    $SearchBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.Search }
    $SearchBox.Add_TextChanged($OnSearchTextChanged)

    $Window.Add_ContentRendered({
        # prevents the window from resizing on search
        $Window.SizeToContent = 'Manual'
        #removes scrollbar
        $Window.Height = $Window.ActualHeight + 1
      })

    $Window.ShowDialog() | Out-Null
  }
}

class ViewModel : ObservableObject {
  $ActionCommand = [RelayCommand]::new(
    {
      $selectedPackages = [Collections.Generic.HashSet[string]]::new()

      foreach ($appItem in $ViewModel.FilteredAppItems.SourceCollection) {
        if ($appItem.IsSelected) {
          foreach ($package in $appItem.Packages) {
            $selectedPackages.Add($package) | Out-Null
          }
        }
      }

      $Window.Close()
      $Action.Invoke($selectedPackages, $DeviceId)
    },
    {
      foreach ($appItem in $ViewModel.FilteredAppItems.SourceCollection) {
        if ($appItem.IsSelected) {
          return $true
        }
      }
      $false
    }
  )

  $ToggleFilteredAppItemsSelectionCommand = [RelayCommand]::new(
    {
      $ViewModel.IsTogglingSelection = $true

      $shouldSelect = -not $ViewModel.AreAllFilteredAppItemsSelected
      if ($shouldSelect) {
        $ViewModel.FilteredAppItems.ForEach({ $PSItem.SetIsSelected($true) })
      }
      else {
        $ViewModel.FilteredAppItems.ForEach({ $PSItem.SetIsSelected($false) })
      }

      $ViewModel.IsTogglingSelection = $false
      $ViewModel.OnSelectionChanged()
    },
    {
      $ViewModel.FilteredAppItems.Count -gt 0
    }
  )

  hidden [ComponentModel.ICollectionView] $FilteredAppItems

  hidden $AreAllFilteredAppItemsSelected = $false
  hidden [void] SetAreAllFilteredAppItemsSelected([bool] $value) {
    $this.SetProperty('AreAllFilteredAppItemsSelected', $value)
  }

  hidden [string] $SearchText

  hidden $IsTogglingSelection = $false

  ViewModel([AppItem[]] $appItems) {
    $appItemsCollection = [Collections.ObjectModel.ObservableCollection[AppItem]]::new($appItems)
    $this.FilteredAppItems = [Windows.Data.CollectionViewSource]::GetDefaultView($appItemsCollection)

    $this.FilteredAppItems.Filter = $this.FilterAppAppItem

    $this.FilteredAppItems.add_CollectionChanged({
        $ViewModel.ToggleFilteredAppItemsSelectionCommand.NotifyCanExecuteChanged()
        $ViewModel.UpdateSelectAllState()
      })

    $this.UpdateSelectAllState()
  }

  [void] FilterApps([string] $text) {
    $this.SearchText = $text
    $this.FilteredAppItems.Refresh()
  }

  [void] OnSelectionChanged() {
    if ($this.IsTogglingSelection) { return }
    $this.ActionCommand.NotifyCanExecuteChanged()
    $this.UpdateSelectAllState()
  }

  hidden [bool] FilterAppAppItem($appItem) {
    if ([string]::IsNullOrEmpty($this.SearchText)) {
      return $true
    }
    else {
      $searchTextLowered = $this.SearchText.ToLower()
      return (
        ($appItem.Name.ToLower().Contains($searchTextLowered)) -or
        ($appItem.Packages.Contains($searchTextLowered))
      )
    }
  }

  hidden [void] UpdateSelectAllState() {
    if ($this.FilteredAppItems.Count.Equals(0)) {
      $this.SetAreAllFilteredAppItemsSelected($false)
      return
    }

    $allFilteredAppItemsSelected = $true
    foreach ($appItem in $this.FilteredAppItems) {
      if (-not $appItem.IsSelected) {
        $allFilteredAppItemsSelected = $false
        break
      }
    }

    $this.SetAreAllFilteredAppItemsSelected($allFilteredAppItemsSelected)
  }
}

class AppItem : ObservableObject {
  [string] $Name

  [string[]] $Packages

  $IsSelected = $false
  [void] SetIsSelected([bool] $value) {
    $this.SetProperty('IsSelected', $value)
  }

  [string] $HelpMessage
  
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
}
