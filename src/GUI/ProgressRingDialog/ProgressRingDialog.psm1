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

function Show-ProgressRingDialog {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param (
    [Parameter(Mandatory)]
    [scriptblock]$Operation,

    [object[]]$ArgumentList = @(),

    [string]$Message
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/ProgressRingDialog.xaml" -HideCaptionButtons -AsModal

    $ViewModel = [ViewModel]::new($Message)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $task = [BackgroundTask]@{
      Operation    = $Operation
      ArgumentList = $ArgumentList
      OnFinished   = { $Window.DialogResult = $true }
    }

    $Window.Add_ContentRendered({
        $task.Start()
      })

    if ($Window.ShowDialog()) {
      @{
        Cancelled = $false
        Output    = $task.WaitForResult()
      }
    }
    else {
      $task.ForceStopAsync()
      @{ Cancelled = $true }
    }
  }
}

class ViewModel {
  $CancelCommand = [RelayCommand]::new({
      $Window.Close()
    })

  [string] $Message

  ViewModel($message) {
    $this.Message = $message
  }
}
