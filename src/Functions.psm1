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
    $adbFromPATH = (Get-Command -Name 'adb' -ErrorAction 'SilentlyContinue').Source
    if ($adbFromPATH) {
      $Env:adb = $adbFromPATH
      return
    }

    $Env:adb = $AdbFromResources

    $Parameters = @{
      Path     = $AdbFromResources
      PathType = 'Leaf'
    }
    if (-not (Test-Path @Parameters -ErrorAction 'SilentlyContinue')) {
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
  param()
  process {
    .$Env:adb devices -l | Select-Object -Skip 1 | ForEach-Object -Process {
      if ($PSItem.Length -eq 0) { return }
      $fields = $PSItem.Split([char]::Tab)

      $status = ($fields -match '^(bootloader|device|recovery|sideload|offline|unauthorized){1}$')[0]
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
  [OutputType([array])]
  param(
    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    .$Env:adb -s $DeviceId shell pm list packages | ForEach-Object -Process {
      $PSItem.Replace('package:', '')
    }
  }
}

function Get-EnabledPackages {
  [CmdletBinding()]
  [OutputType([array])]
  param(
    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    .$Env:adb -s $DeviceId shell pm list packages -e | ForEach-Object -Process {
      $PSItem.Replace('package:', '')
    }
  }
}

function Get-DisabledPackages {
  [CmdletBinding()]
  [OutputType([array])]
  param(
    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    .$Env:adb -s $DeviceId shell pm list packages -d | ForEach-Object -Process {
      $PSItem.Replace('package:', '')
    }
  }
}

function Uninstall-Packages {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [array]$Packages,

    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    foreach ($package in $Packages) {
      .$Env:adb -s $DeviceId shell pm uninstall --user 0 $package
      Write-Verbose -Message "Uninstalled $package"
    }
  }
}

function Disable-Packages {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [array]$Packages,

    [string]$DeviceId
  )
  process {
    foreach ($package in $Packages) {
      .$Env:adb -s $DeviceId shell pm disable-user --user 0 $package
      Write-Verbose -Message "Disabled $package"
    }
  }
}

function Enable-Packages {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [array]$Packages,

    [string]$DeviceId
  )
  process {
    foreach ($package in $Packages) {
      .$Env:adb -s $DeviceId shell pm enable --user 0 $package
      Write-Verbose -Message "Enabled $package"
    }
  }
}

#endregion

#endregion

#region Apps

function Get-AppsToProcess {
  [CmdletBinding()]
  [OutputType([array])]
  param (
    [Parameter(Mandatory)]
    [array]$Packages,

    [Parameter(Mandatory)]
    [array]$BloatwareList
  )
  begin {
    $targetLanguage = $PSUICulture.Split('-')[0]
  }
  process {
    $appsToProcess = @()
    $i = 0

    foreach ($bloatwareApp in $BloatwareList) {
      $found = $false

      foreach ($package in $Packages) {
        if ($package -in $bloatwareApp.Packages) {
          $found = $true

          if (-not $appsToProcess[$i]) {
            $appsToProcess += @{}
            $appsToProcess[$i].Packages = @()
          }

          $appsToProcess[$i].Name = $bloatwareApp.Name.$targetLanguage
          if (-not $appsToProcess[$i].Name) {
            $appsToProcess[$i].Name = $bloatwareApp.Name.en
          }
          $appsToProcess[$i].Description = $bloatwareApp.Description.$targetLanguage
          if (-not $appsToProcess[$i].Description) {
            $appsToProcess[$i].Description = $bloatwareApp.Description.en
          }

          $appsToProcess[$i].Packages += $package
        }
      }

      if ($found) { $i++ }
    }

    $appsToProcess
  }
}

#endregion
