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
    $Localization = Get-Localization
    $operationName = switch -Exact ($ActionName) {
      'uninstall' { $Localization.Uninstalling; break }
      'disable' { $Localization.Disabling; break }
      'enable' { $Localization.Enabling; break }
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

    $failedPackages = [Collections.Generic.List[hashtable]]::new()
    $script:completedCount = 0

    $Parameters = @{
      Operation      = $Action
      ArgumentList   = $packageItems.Package, $DeviceId
      InitialMessage = Get-ProgressMessage -PackageItem $packageItems[0]
      MaxProgress    = $packageItems.Count
      OnProgress = {
        param($result)
        if (-not $result.Success) {
          $failedPackages.Add($packageItems[$completedCount])
        }

        $script:completedCount++

        if ($completedCount -lt $packageItems.Count) {
          $message = Get-ProgressMessage -PackageItem $packageItems[$completedCount]
          Update-Progress -Message $message -Progress $completedCount
        }
        else {
          Update-Progress -Progress $completedCount
        }
      }
    }
    Show-ProgressBarDialog @Parameters

    $failedPackages
  }
}
