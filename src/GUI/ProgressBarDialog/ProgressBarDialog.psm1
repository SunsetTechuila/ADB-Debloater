#Requires -Version 5.1

using module ../Helpers.psm1

$ErrorActionPreference = 'Stop'

."$PSScriptRoot/../../Paths.ps1"
."$PSScriptRoot/../Paths.ps1"

Import-Module -Name $Helpers -Force -DisableNameChecking

$Parameters = @{
  BindingVariable = 'Localization'
  BaseDirectory   = $Localizations
  FileName        = 'Strings'
}
Import-LocalizedData @Parameters

function Show-ProgressBarDialog {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [scriptblock]$Operation,

    [object[]]$ArgumentList = @(),

    [Parameter(Mandatory)]
    [scriptblock]$OnProgress,

    [string]$InitialMessage,

    [int]$MaxProgress = 100
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/ProgressBarDialog.xaml" -HideCaptionButtons

    $ViewModel = [ViewModel]::new($InitialMessage, $MaxProgress)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $task = [BackgroundTask]@{
      Operation    = $Operation
      ArgumentList = $ArgumentList
      OnProgress   = $OnProgress
      OnFinished   = { $Window.DialogResult = $true }
    }

    $Window.Add_ContentRendered({
        $task.Start()
      })

    if ($Window.ShowDialog()) {
      $task.WaitForResult() > $null
    }
    else {
      $task.ForceStopAsync()
    }
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

    # Render the updated UI and processes queued user input
    $Window.Dispatcher.Invoke([Action] {}, [Windows.Threading.DispatcherPriority]::Background)
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

  ViewModel($message, $maxProgress) {
    $this.Message = $message
    $this.MaxProgress = $maxProgress
  }
}
