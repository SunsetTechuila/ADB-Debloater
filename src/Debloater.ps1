#Requires -Version 5.1

param(
  [switch]$Dev
)

#region Preparation

$ErrorActionPreference = 'Stop'

."$PSScriptRoot/Paths.ps1"

@(
  'Functions',
  'AppsDialog',
  'DevicesWindow',
  'MessageDialog'
) | ForEach-Object -Process {
  Remove-Module -Name $PSItem -Force -ErrorAction 'SilentlyContinue'
  Import-Module -Name (Get-Variable -Name $PSItem -ValueOnly) -DisableNameChecking
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
  $choice = Show-DevicesWindow @Parameters
  if ($choice.Count -eq 0) { 
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
