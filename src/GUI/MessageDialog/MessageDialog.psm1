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

function Show-MessageDialog {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Message,

    [System.Windows.Window] $ParentWindow
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    $Window = Initialize-Window -Path "$PSScriptRoot/MessageDialog.xaml" -SetWindowMaxHeight -HideCaptionButtons

    $Window.OkButton.Content = $Localization.Ok
    $Window.OkButton.Add_Click({ $Window.Close() })
    $Window.MessageBlock.Text = $Message

    $Window.Add_KeyDown({
        if (($PSItem.Key -eq 'Enter') -or ($PSItem.Key -eq 'Escape')) {
          $Window.Close()
        }
      })

    if ($ParentWindow) {
      $Window.Owner = $ParentWindow
      $Window.WindowStartupLocation = 'CenterOwner'
    }
    $Window.ShowDialog() | Out-Null
  }
}
