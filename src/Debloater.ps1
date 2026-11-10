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
  'ProgressRingDialog',
  'MessageDialog',
  'ProcessPackagesDialog'
) | ForEach-Object -Process {
  $path = Get-Variable -Name $PSItem -ValueOnly
  # PowerShell 5 resolves the dialogs' relative `using module ../Helpers.psm1` against the current directory,
  # so the modules are parsed from a dialog folder rather than from wherever the script was launched
  Push-Location (Split-Path -Path $path)
  try {
    Import-Module -Name $path -Force -DisableNameChecking
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

#region ADB

Set-Adb
$wasAdbInstalled = Test-Adb
if (-not $wasAdbInstalled) {
  $Parameters = @{
    Message   = "$($Localization.SettingAdbUp)..."
    Operation = ${function:Get-Adb}
  }
  try {
    $result = Show-ProgressRingDialog @Parameters
    if ($result.Cancelled) { exit }
  }
  catch {
    $Parameters = @{
      Title   = $Localization.FailedToSetAdbUp
      Message = $PSItem.Exception.Message
      Icon    = 'Error'
    }
    Show-MessageDialog @Parameters > $null
    exit
  }
}

$hasStartedAdbServer = $false
if (-not $wasAdbInstalled -or -not (Test-AdbServer)) {
  $Parameters = @{
    Message   = "$($Localization.StartingAdbServer)..."
    Operation = ${function:Start-AdbServer}
  }
  try {
    $result = Show-ProgressRingDialog @Parameters
    if ($result.Cancelled) { exit }
    $hasStartedAdbServer = $true
  }
  catch {
    $Parameters = @{
      Title   = $Localization.FailedToStartAdbServer
      Message = $PSItem.Exception.Message
      Icon    = 'Error'
    }
    Show-MessageDialog @Parameters > $null
    exit
  }
}

#endregion

#region Main Loop

do {
  $Parameters = @{
    WatchDevices  = ${function:Watch-Devices}
    ConnectDevice = ${function:Connect-DeviceOverWiFi}
    PairDevice    = ${function:Pair-DeviceOverWiFi}
  }
  $choice = Show-DevicesDialog @Parameters
  if (-not $choice) { break }

  $deviceId = $choice.DeviceId
  $actionName = $choice.ActionName

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
  }

  if (-not $packages) {
    Show-MessageDialog -Message $Localization.NoPackagesFound -Icon 'Warning' > $null
    continue
  }

  $Parameters = @{
    Packages      = $packages
    BloatwareList = Get-Content -Path $BloatwareList -Raw | ConvertFrom-Json
  }
  $appsToProcess = Get-AppsToProcess @Parameters

  if (-not $appsToProcess) {
    Show-MessageDialog -Message $Localization.NoPackagesFound -Icon 'Warning' > $null
    continue
  }

  $Parameters = @{
    ActionName = $actionName
    Apps       = $appsToProcess
  }
  $selectedApps = Show-AppsDialog @Parameters
  if (-not $selectedApps) { continue }

  $Parameters = @{
    ActionName = $actionName
    Action     = $chosenAction
    Apps       = $selectedApps
    DeviceId   = $deviceId
  }
  $failedPackages = Show-ProcessPackagesDialog @Parameters

  if ($failedPackages) {
    $failedActionMessage = switch -Exact ($actionName) {
      'uninstall' { $Localization.FailedToUninstall; break }
      'disable' { $Localization.FailedToDisable; break }
      'enable' { $Localization.FailedToEnable; break }
      'reinstall' { $Localization.FailedToReinstall; break }
    }
    $failedPackagesList = foreach ($failedPackage in $failedPackages) {
      "$($failedPackage.Package) ($($failedPackage.AppName))"
    }
    $Parameters = @{
      Title   = $failedActionMessage
      Message = $failedPackagesList -join "`n"
      Icon    = 'Error'
    }
    Show-MessageDialog @Parameters > $null
  }
} while ($true)

if (-not $Dev -and $hasStartedAdbServer) {
  Stop-AdbServer
}

#endregion
