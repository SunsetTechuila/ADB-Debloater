#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

."$PSScriptRoot/Paths.ps1"

#region Platform-Tools

function Set-PlatformTools {
  [CmdletBinding()]
  param()
  begin {
    $AdbFromResources = "$Resources/platform-tools/adb.exe"
  }
  process {
    $Parameters = @{
      Name = 'adb'
      CommandType = 'Application'
      TotalCount = 1
      ErrorAction = 'SilentlyContinue'
    }
    $adbFromPATH = (Get-Command @Parameters).Source
    if ($adbFromPATH) {
      $Env:adb = $adbFromPATH
      return
    }

    $Env:adb = $AdbFromResources

    $Parameters = @{
      Path     = $AdbFromResources
      PathType = 'Leaf'
      ErrorAction = 'SilentlyContinue'
    }
    if (-not (Test-Path @Parameters)) {
      Get-PlatformTools
    }
  }
}

function Get-PlatformTools {
  [CmdletBinding()]
  param()
  begin {
    $platformToolsArchive = "$Resources/platform-tools.zip"
    $platformToolsDownloadUri = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
  }
  process {
    $Parameters = @{
      Uri             = $platformToolsDownloadUri
      OutFile         = $platformToolsArchive
      UseBasicParsing = $true
    }
    Invoke-WebRequest @Parameters

    $Parameters = @{
      Path            = $platformToolsArchive
      DestinationPath = $Resources
      Force           = $true
    }
    Expand-Archive @Parameters

    Remove-Item -Path $platformToolsArchive -Force
  }
}

#endregion

#region ADB

function Start-Adb {
  [CmdletBinding()]
  param()
  process {
    .$Env:adb start-server
  }
}

function Stop-Adb {
  [CmdletBinding()]
  param()
  process {
    .$Env:adb kill-server
  }
}

function Connect-DeviceOverWiFi {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string]$IpAddress
  )
  process {
    .$Env:adb connect $IpAddress
  }
}

function Pair-DeviceOverWiFi {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string]$IpAddress,

    [Parameter(Mandatory)]
    [string]$PairingCode
  )
  process {
    $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processStartInfo.FileName = $Env:adb
    $processStartInfo.Arguments = "pair $IpAddress"
    $processStartInfo.RedirectStandardInput = $true


    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processStartInfo
    $process.Start()

    $process.StandardInput.WriteLine($PairingCode)
    $process.StandardInput.Close()

    $process.WaitForExit()
  }
}

function Get-Devices {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param()
  process {
    foreach ($line in .$Env:adb devices -l | Select-Object -Skip 1) {
      if ($line.Length -eq 0) { continue }
      $fields = -split $line

      $status = ($fields -match '^(bootloader|device|recovery|sideload|offline|unauthorized)$')[0]
      if ($status -eq 'device') { $status = 'connected' }
      $model = ($fields -match '^model:\w+$')[0]
      $model = if ($model) { $model.Replace('model:', '').Replace('_', ' ') } else { 'unknown' }

      @{
        Id     = $fields[0]
        Status = if ($status) { $status } else { 'unknown' }
        Model  = $model
      }
    }
  }
}

#region Packages

function Get-InstalledPackages {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    (.$Env:adb -s $DeviceId shell pm list packages) -replace '^package:'
  }
}

function Get-EnabledPackages {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    (.$Env:adb -s $DeviceId shell pm list packages -e) -replace '^package:'
  }
}

function Get-DisabledPackages {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    (.$Env:adb -s $DeviceId shell pm list packages -d) -replace '^package:'
  }
}

function Get-UninstalledPackages {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    $allPackages = (.$Env:adb -s $DeviceId shell pm list packages -u) -replace '^package:'
    $installedPackages = Get-InstalledPackages -DeviceId $DeviceId
    [Linq.Enumerable]::Except([string[]]$allPackages, [string[]]$installedPackages)
  }
}

function Uninstall-Packages {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string[]]$Packages,

    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    foreach ($package in $Packages) {
      try {
        try {
          # Uninstall system app update, if installed
          .$Env:adb -s $DeviceId shell pm uninstall $package
        }
        catch { }
        # `pm uninstall --user 0` uninstalls the system package for the primary user; when the app is uninstalled, `pm disable-user` is used to prevent the Play Store or other OEM app stores from forced reinstalling the app or enabling it after an OTA software update
        # `am force-stop' is used to ensure that all app processes are terminated
        .$Env:adb -s $DeviceId shell "pm uninstall --user 0 $package && pm disable-user $package && am force-stop $package"
        Write-Host -Object "Uninstalled $package"
      }
      catch {
        Write-Host -Object "Failed to uninstall $($package): $($PSItem.Exception.Message)"
      }
    }
  }
}

function Disable-Packages {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string[]]$Packages,

    [string]$DeviceId
  )
  process {
    foreach ($package in $Packages) {
      try {
        try {
          # Uninstall system app update, if installed
          .$Env:adb -s $DeviceId shell pm uninstall $package
        }
        catch { }
        # `pm disable-user` disables the system package for the primary user, preventing it from running in the background or receiving updates
        # `am force-stop' is used to ensure that all app processes are terminated
        # `pm clear` clears all application data
        .$Env:adb -s $DeviceId shell "pm disable-user $package && am force-stop $package && pm clear $package" 
        Write-Host -Object "Disabled $package"
      }
      catch {
        Write-Host -Object "Failed to disable $($package): $($PSItem.Exception.Message)"
      }
    }
  }
}

function Enable-Packages {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string[]]$Packages,

    [string]$DeviceId
  )
  process {
    foreach ($package in $Packages) {
      try {
        .$Env:adb -s $DeviceId shell pm enable $package
        Write-Host -Object "Enabled $package"
      }
      catch {
        Write-Host -Object "Failed to enable $($package): $($PSItem.Exception.Message)"
      }
    }
  }
}

function Reinstall-Packages {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string[]]$Packages,

    [string]$DeviceId
  )
  process {
    foreach ($package in $Packages) {
      try {
        .$Env:adb -s $DeviceId shell "cmd package install-existing $package && pm enable $package"
        Write-Host -Object "Reinstalled $package"
      }
      catch {
        Write-Host -Object "Failed to reinstall $($package): $($PSItem.Exception.Message)"
      }
    }
  }
}

#endregion

#endregion

#region Apps

function Get-AppsToProcess {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param (
    [Parameter(Mandatory)]
    [string[]]$Packages,

    [Parameter(Mandatory)]
    [array]$BloatwareList
  )
  begin {
    $targetLanguage = $PSUICulture.Split('-')[0]
  }
  process {
    foreach ($bloatwareApp in $BloatwareList) {
      $matchingPackages = foreach ($package in $bloatwareApp.Packages) {
        if ($Packages.Contains($package)) {
          $package
        }
      }
      if (-not $matchingPackages) { continue }

      $name = $bloatwareApp.Name.$targetLanguage
      if (-not $name) {
        $name = $bloatwareApp.Name.en
      }
      $description = $bloatwareApp.Description.$targetLanguage
      if (-not $description) {
        $description = $bloatwareApp.Description.en
      }

      @{
        Name        = $name
        Description = $description
        Packages    = $matchingPackages
      }
    }
  }
}

#endregion
