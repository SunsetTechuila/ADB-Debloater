#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

."$PSScriptRoot/../../Paths.ps1"
."$PSScriptRoot/../Paths.ps1"

Import-Module -Name $ProgressDialog -Force -DisableNameChecking

$Parameters = @{
  BindingVariable = 'Localization'
  BaseDirectory   = $Localizations
  FileName        = 'Strings'
}
Import-LocalizedData @Parameters

function Show-ProcessPackagesDialog {
  [CmdletBinding()]
  [OutputType([hashtable])]
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
  process {
    $operationName = switch -Exact ($ActionName) {
      'uninstall' { $Localization.Uninstalling; break }
      'disable'   { $Localization.Disabling; break }
      'enable'    { $Localization.Enabling; break }
      'reinstall' { $Localization.Reinstalling; break }
    }

    function Get-ProgressMessage {
      param([hashtable]$PackageItem)
      "$($operationName): $($PackageItem.AppName)"
    }

    [hashtable[]]$packageItems = foreach ($app in $Apps) {
      foreach ($package in $app.Packages) {
        @{
          Package = $package
          AppName = $app.Name
        }
      }
    }

    $Parameters = @{
      MaxProgress = $packageItems.Count
      Operation   = {
        Update-Progress -Message (Get-ProgressMessage -PackageItem $packageItems[0])

        $packages = $packageItems.Package
        $completedCount = 0

        & $Action -Packages $packages -DeviceId $DeviceId | ForEach-Object -Process {
          if (-not $PSItem.Success) {
            $packageItems[$completedCount]
          }

          $completedCount++

          if ($completedCount -lt $packageItems.Count) {
            $message = Get-ProgressMessage -PackageItem $packageItems[$completedCount]
            Update-Progress -Message $message -Progress $completedCount
          }
          else {
            Update-Progress -Progress $completedCount
          }
        }
      }
    }
    Show-ProgressDialog @Parameters
  }
}
