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

function Show-MessageDialog {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)]
    [string]$Message,

    [string]$Title,

    [ValidateSet('Warning', 'Error')]
    [string]$Icon,

    [ValidateSet('Ok', 'OkCancel')]
    [string]$Buttons = 'Ok'
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/MessageDialog.xaml" -HideCaptionButtons -AsModal

    $ViewModel = [ViewModel]::new($Message, $Title, $Icon, $Buttons)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $Window.ShowDialog()
  }
}

class ViewModel {
  $OkCommand = [RelayCommand]::new({
      $Window.DialogResult = $true
    })

  $CancelCommand = [RelayCommand]::new({
      $Window.Close()
    })

  [string] $Message

  [string] $Title

  [string] $Icon

  [string] $Buttons

  ViewModel(
    [string] $message,
    [string] $title,
    [string] $icon,
    [string] $buttons
  ) {
    $this.Message = $message
    $this.Title = $title
    $this.Icon = $icon
    $this.Buttons = $buttons
  }
}
