#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName 'PresentationFramework'

Import-Module -Name "$PSScriptRoot/../Localization.psm1"

foreach ($scriptPath in @(
    'Helpers.ps1'
    'MessageDialog/MessageDialog.ps1'
    'ProgressRingDialog/ProgressRingDialog.ps1'
    'ProgressBarDialog/ProgressBarDialog.ps1'
    'ProcessPackagesDialog/ProcessPackagesDialog.ps1'
    'ConnectDeviceDialog/ConnectDeviceDialog.ps1'
    'PairDeviceDialog/PairDeviceDialog.ps1'
    'DevicesDialog/DevicesDialog.ps1'
    'AppsDialog/AppsDialog.ps1'
  )) {
  ."$PSScriptRoot/$scriptPath"
}

Export-ModuleMember -Function @(
  'Show-AppsDialog'
  'Show-ConnectDeviceDialog'
  'Show-DevicesDialog'
  'Show-MessageDialog'
  'Show-PairDeviceDialog'
  'Show-ProcessPackagesDialog'
  'Show-ProgressBarDialog'
  'Show-ProgressRingDialog'
  'Update-Progress'
)
