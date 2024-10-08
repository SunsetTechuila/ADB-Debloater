#Requires -Version 5.1

#region Preparation

$ErrorActionPreference = 'Stop'

."$PSScriptRoot/Paths.ps1"

@(
  'Functions',
  'PackagesDialog',
  'DevicesWindow',
  'TextAlertWindow'
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

$Parameters = @{
  GetDevices    = ${function:Get-Devices}
  ConnectDevice = ${function:Connect-DeviceOverWiFi}
  PairDevice    = ${function:Pair-DeviceOverWiFi}
}
$choice = Show-DevicesWindow @Parameters
if ($choice.Count -eq 0) { return }
$actionType = $choice.ActionType
$deviceId = $choice.DeviceId

switch -Exact ($actionType) {
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
  Default {
    throw "Unknown action type: $($actionType)"
  }
}

if (-not $packages) {
  Show-TextAlertWindow -Message $Localization.NoPackagesFound
  Stop-Adb
  return
}

$Parameters = @{
  Packages      = $packages
  BloatwareList = Get-Content -Path $BloatwareList -Raw | ConvertFrom-Json
}
$appsToProcess = Get-AppsToProcess @Parameters

if (-not $appsToProcess) {
  Show-TextAlertWindow -Message $Localization.NoPackagesFound
  Stop-Adb
  return
}

$Parameters = @{
  ActionType = $actionType
  Action     = $chosenAction
  Apps       = $appsToProcess
  DeviceId   = $deviceId
}
Show-PackagesDialog @Parameters

Stop-Adb

#endregion
