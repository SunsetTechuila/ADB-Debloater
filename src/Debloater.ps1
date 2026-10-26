#Requires -Version 5.1

param(
  [switch]$Dev
)

#region Preparation

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName 'PresentationFramework'

."$PSScriptRoot/Paths.ps1"

@(
  'Functions',
  'AppsDialog',
  'DevicesDialog',
  'MessageDialog'
) | ForEach-Object -Process {
  $path = Get-Variable -Name $PSItem -ValueOnly
  # PowerShell 5 resolves the dialogs' relative `using module ../Helpers.psm1` against the current directory,
  # so the modules are parsed from a dialog folder rather than from wherever the script was launched
  Push-Location (Split-Path -Path $path)
  Remove-Module -Name $PSItem -Force -ErrorAction 'SilentlyContinue'
  try {
    Import-Module -Name $path -DisableNameChecking
  }
  finally {
    Pop-Location
  }
}

$Parameters = @{
  BindingVariable = 'Localization'
  BaseDirectory   = $Localizations
  FileName        = 'Strings'
}
Import-LocalizedData @Parameters

#endregion

#region Main

Set-PlatformTools
Start-Adb

do {
  $Parameters = @{
    GetDevices    = ${function:Get-Devices}
    ConnectDevice = ${function:Connect-DeviceOverWiFi}
    PairDevice    = ${function:Pair-DeviceOverWiFi}
  }
  $choice = Show-DevicesDialog @Parameters
  if (-not $choice) {
    break
  }
  $actionName = $choice.ActionName
  $deviceId = $choice.DeviceId

  switch -Exact ($actionName) {
    'uninstall' {
      $chosenAction = ${function:Uninstall-Packages}
      $packages = Get-InstalledPackages -DeviceId $deviceId
      break
    }
    'disable' {
      $chosenAction = ${function:Disable-Packages}
      $packages = Get-EnabledPackages -DeviceId $deviceId
      break
    }
    'enable' {
      $chosenAction = ${function:Enable-Packages}
      $packages = Get-DisabledPackages -DeviceId $deviceId
      break
    }
    'reinstall' {
      $chosenAction = ${function:Reinstall-Packages}
      $packages = Get-UninstalledPackages -DeviceId $deviceId
      break
    }
    default {
      throw "Unknown action: $($actionName)"
    }
  }

  if (-not $packages) {
    Show-MessageDialog -Message $Localization.NoPackagesFound
    continue
  }

  $Parameters = @{
    Packages      = $packages
    BloatwareList = Get-Content -Path $BloatwareList -Raw | ConvertFrom-Json
  }
  $appsToProcess = Get-AppsToProcess @Parameters

  if (-not $appsToProcess) {
    Show-MessageDialog -Message $Localization.NoPackagesFound
    continue
  }

  $Parameters = @{
    ActionName = $actionName
    Action     = $chosenAction
    Apps       = $appsToProcess
    DeviceId   = $deviceId
  }
  Show-AppsDialog @Parameters
} while ($true)

if (-not $Dev) {
  Stop-Adb
}

#endregion
