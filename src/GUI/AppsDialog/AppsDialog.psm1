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
    [hashtable[]]$Apps,

    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/AppsDialog.xaml" -SetWindowMaxHeight

    $appItems = New-AppItems -Apps $Apps
    $ViewModel = [ViewModel]::new($appItems)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
      ActionLabel  = $Localization.$ActionName
    }

    $Window.AppsListView.add_SelectionChanged({
        # When scrolling or filtering, VirtualizingStackPanel generates or recycles ListViewItem containers
        # while ItemContainerGenerator.Status is 'GeneratingContainers'.
        # Syncing a recycled container's IsSelected binding to the newly bound AppItem raises SelectionChanged
        # even though no AppItem selection state actually changed.
        if ($Window.AppsListView.ItemContainerGenerator.Status -ne 'ContainersGenerated') {
          return
        }
        $ViewModel.OnSelectionChanged()
      })

    $OnSearchTextChanged = {
      param($eventSender)
      $ViewModel.FilterApps($eventSender.Text)
    }
    $Window.SearchBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.Search }
    $Window.SearchBox.Add_TextChanged($OnSearchTextChanged)

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

      foreach ($appItem in $ViewModel.AppItems) {
        if ($appItem.IsSelected) {
          $selectedPackages.UnionWith($appItem.Packages)
        }
      }

      $Window.Close()
      $Action.Invoke($selectedPackages, $DeviceId)
    },
    {
      foreach ($appItem in $ViewModel.AppItems) {
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

      $targetState = -not $ViewModel.SelectAllState
      if (-not $targetState) {
        # Off-screen items have no realized ListViewItem container, so SetProperty('IsSelected', $false) only
        # updates the AppItem model and cannot notify ListView via the container's TwoWay binding.
        # Clearing SelectedItems prevents ListView from re-selecting those items when scrolled back into view.
        $Window.AppsListView.SelectedItems.Clear()
      }
      [ObservableObject]::SetProperty($ViewModel.FilteredAppItems, 'IsSelected', $targetState)

      $ViewModel.IsTogglingSelection = $false
      $ViewModel.OnSelectionChanged()
    },
    {
      $ViewModel.FilteredAppItems.Count -gt 0
    }
  )

  hidden [AppItem[]] $AppItems

  hidden [AppItem[]] $FilteredAppItems
  hidden [void] SetFilteredAppItems($value) {
    if ($this.SetProperty('FilteredAppItems', $value)) {
      $this.ToggleFilteredAppItemsSelectionCommand.NotifyCanExecuteChanged()
      $this.UpdateSelectAllState()
    }
  }

  hidden [Nullable[bool]] $SelectAllState = $false
  hidden [void] SetSelectAllState($value) {
    $this.SetProperty('SelectAllState', $value)
  }

  hidden $IsTogglingSelection = $false

  ViewModel([AppItem[]] $appItems) {
    $this.AppItems = $appItems
    $this.FilteredAppItems = $appItems
  }

  [void] FilterApps([string] $searchText) {
    if ([string]::IsNullOrEmpty($searchText)) {
      $this.SetFilteredAppItems($this.AppItems)
      return
    }

    $escapedSearchText = [regex]::Escape($searchText)
    $this.SetFilteredAppItems(
      @(
        foreach ($appItem in $this.AppItems) {
          if (
            ($appItem.Name -match $escapedSearchText) -or
            ($appItem.Packages -contains $searchText)
          ) {
            $appItem
          }
        }
      )
    )
  }

  [void] OnSelectionChanged() {
    if ($this.IsTogglingSelection) { return }
    $this.ActionCommand.NotifyCanExecuteChanged()
    $this.UpdateSelectAllState()
  }

  hidden [void] UpdateSelectAllState() {
    $hasSelected = $false
    $hasUnselected = $false

    foreach ($appItem in $this.FilteredAppItems) {
      if ($appItem.IsSelected) {
        $hasSelected = $true
      }
      else {
        $hasUnselected = $true
      }

      if ($hasSelected -and $hasUnselected) {
        $this.SetSelectAllState($null)
        return
      }
    }

    $this.SetSelectAllState($hasSelected)
  }
}

class AppItem : ObservableObject {
  [string] $Name

  [string[]] $Packages

  [bool] $IsSelected

  [string] $HelpMessage

  hidden [string] $PackagesString
}

# Defining a constructor or static factory method on AppItem causes PowerShell to emit a scriptblock
# wrapper into AppItem's default constructor, adding noticeable overhead when creating a large collection.
function New-AppItems {
  [CmdletBinding()]
  [OutputType([AppItem[]])]
  param (
    [Parameter(Mandatory)]
    [hashtable[]]$Apps
  )
  process {
    foreach ($app in $Apps) {
      $appItem = [AppItem]::new()
      $appItem.Name = $app.Name
      $appItem.Packages = $app.Packages
      $appItem.HelpMessage = $app.Description
      $appItem.PackagesString = $app.Packages -join "`n"
      $appItem
    }
  }
}
