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

    #region Shift Multi-selection

    $selectionStartItem = [ref]$null

    $AppsListView.add_PreviewMouseLeftButtonDown({
        param($eventSender, $eventArguments)

        $clickedElement = [Windows.Controls.ItemsControl]::ContainerFromElement(
          $AppsListView,
          $eventArguments.OriginalSource
        )
        if (-not ($clickedElement -is [Windows.Controls.ListViewItem])) { return }
        $clickedItem = $clickedElement.DataContext

        $isShiftPressed = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift) -ne 0
        if (-not $isShiftPressed) {
          $selectionStartItem.Value = $clickedItem
          return
        }

        if (-not $AppsListView.Items.Contains($selectionStartItem.Value)) {
          $selectionStartItem.Value = $AppsListView.Items.GetItemAt(0)
        }

        $ViewModel.SelectItemsFromTo($selectionStartItem.Value, $clickedItem)
        $clickedElement.Focus()
        $eventArguments.Handled = $true
      })

    $AppsListView.add_PreviewKeyDown({
        param($eventSender, $eventArguments)

        $isUpOrDownPressed = $eventArguments.Key -in [Windows.Input.Key]::Up, [Windows.Input.Key]::Down
        $isShiftPressed = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift) -ne 0
        if ((-not $isUpOrDownPressed) -or (-not $isShiftPressed)) { return }

        $focusedElement = [Windows.Controls.ItemsControl]::ContainerFromElement(
          $AppsListView,
          [Windows.Input.Keyboard]::FocusedElement
        )
        if (-not ($focusedElement -is [Windows.Controls.ListViewItem])) { return }
        $focusedItem = $focusedElement.DataContext

        if (-not $focusedItem.IsSelected) {
          $selectionStartItem.Value = $focusedItem
        }

        $nextItemIndex = $AppsListView.ItemContainerGenerator.IndexFromContainer($focusedElement) + $(
          if ($eventArguments.Key -eq [Windows.Input.Key]::Up) { -1 } else { 1 }
        )
        if (($nextItemIndex -lt 0) -or ($nextItemIndex -ge $AppsListView.Items.Count)) {
          $eventArguments.Handled = $true
          return
        }
        $nextItem = $AppsListView.Items.GetItemAt($nextItemIndex)

        $ViewModel.SelectItemsFromTo($selectionStartItem.Value, $nextItem)
        $AppsListView.ScrollIntoView($nextItem)
        $AppsListView.ItemContainerGenerator.ContainerFromItem($nextItem).Focus()
        $eventArguments.Handled = $true
      })

    #endregion

    $searchDebounceTimer = [Windows.Threading.DispatcherTimer]::new()
    $searchDebounceTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $searchDebounceTimer.add_Tick({
        $searchDebounceTimer.Stop()
        $ViewModel.FilterApps($SearchBox.Text)
      })

    $OnSearchTextChanged = {
      param($eventSender)
      $searchDebounceTimer.Stop()
      $searchDebounceTimer.Start()
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

      $targetState = -not $ViewModel.SelectAllState
      $ViewModel.FilteredAppItems.ForEach({ $PSItem.SetIsSelected($targetState) })

      $ViewModel.IsTogglingSelection = $false
      $ViewModel.OnSelectionChanged()
    },
    {
      $ViewModel.FilteredAppItems.Count -gt 0
    }
  )

  hidden [ComponentModel.ICollectionView] $FilteredAppItems

  hidden [Nullable[bool]] $SelectAllState = $false
  hidden [void] SetSelectAllState([Nullable[bool]] $value) {
    $this.SetProperty('SelectAllState', $value)
  }

  hidden [string] $SearchText

  hidden $IsTogglingSelection = $false

  [void] SelectItemsFromTo([AppItem] $startItem, [AppItem] $endItem) {
    $startItemIndex = $this.FilteredAppItems.IndexOf($startItem)
    $endItemIndex = $this.FilteredAppItems.IndexOf($endItem)
    $selectionStartIndex = [Math]::Min($startItemIndex, $endItemIndex)
    $selectionEndIndex = [Math]::Max($startItemIndex, $endItemIndex)

    $this.IsTogglingSelection = $true

    $this.FilteredAppItems.ForEach({
        $itemIndex = $this.FilteredAppItems.IndexOf($PSItem)
        $shouldSelect = ($itemIndex -ge $selectionStartIndex) -and ($itemIndex -le $selectionEndIndex)
        $PSItem.SetIsSelected($shouldSelect)
      })

    $this.IsTogglingSelection = $false
    $this.OnSelectionChanged()
  }

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
      $this.SetSelectAllState($false)
      return
    }

    $selectedItemsCount = 0
    $totalItemsCount = 0
    foreach ($appItem in $this.FilteredAppItems) {
      $totalItemsCount += 1
      if ($appItem.IsSelected) { $selectedItemsCount += 1 }
    }

    if ($selectedItemsCount.Equals(0)) {
      $this.SetSelectAllState($false)
    }
    elseif ($selectedItemsCount.Equals($totalItemsCount)) {
      $this.SetSelectAllState($true)
    }
    else {
      $this.SetSelectAllState($null)
    }
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
