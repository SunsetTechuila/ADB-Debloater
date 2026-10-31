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

function Show-ProgressDialog {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [scriptblock]$Operation,

    [int]$MaxProgress = 100
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/ProgressDialog.xaml" -HideCaptionButtons

    $ViewModel = [ViewModel]::new($MaxProgress)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $output = [Collections.Generic.List[object]]::new()

    $Window.Add_ContentRendered({
        & $Operation | ForEach-Object -Process {
          $output.Add($PSItem)
        }
        if ($Window.IsVisible) {
          # Frame 1 commits/presents the final progress bar update to DWM
          # Frame 2 closes after it is on screen
          $script:renderedFrames = 0
          $script:onRendered = [EventHandler]{
            $script:renderedFrames++
            if ($script:renderedFrames -ge 2) {
              [Windows.Media.CompositionTarget]::remove_Rendering($script:onRendered)
              $Window.Close()
            }
          }
          [Windows.Media.CompositionTarget]::add_Rendering($script:onRendered)
        }
      })

    $Window.ShowDialog() | Out-Null
    $output
  }
}

function Update-Progress {
  [CmdletBinding()]
  param(
    [string]$Message,

    [Nullable[int]]$Progress
  )
  process {
    if ($Message) {
      $ViewModel.SetMessage($Message)
    }
    if ($null -ne $Progress) {
      $ViewModel.SetProgress($Progress)
    }
    $Window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
    if (-not $Window.IsVisible) {
      break
    }
  }
}

class ViewModel : ObservableObject {
  $CancelCommand = [RelayCommand]::new({
      $Window.Close()
    })

  hidden [string] $Message
  [void] SetMessage($value) {
    $this.SetProperty('Message', $value)
  }

  hidden [int] $Progress
  [void] SetProgress($value) {
    $this.SetProperty('Progress', $value)
  }

  hidden [int] $MaxProgress

  ViewModel($maxProgress) {
    $this.MaxProgress = $maxProgress
  }
}
