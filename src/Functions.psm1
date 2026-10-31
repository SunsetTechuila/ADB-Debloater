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
      Name        = 'adb'
      CommandType = 'Application'
      TotalCount  = 1
      ErrorAction = 'Ignore'
    }
    $adbFromPATH = (Get-Command @Parameters).Source
    if ($adbFromPATH) {
      $Env:adb = $adbFromPATH
      return
    }

    $Env:adb = $AdbFromResources

    $Parameters = @{
      Path        = $AdbFromResources
      PathType    = 'Leaf'
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
    Add-Type -AssemblyName 'System.IO.Compression', 'System.IO.Compression.FileSystem'
    $platformToolsDirectory = "$Resources/platform-tools"
    $platformToolsDownloadUri = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
    $requiredFiles = @('adb.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll')
  }
  process {
    $completed = $false
    try {
      $response = [Net.WebRequest]::CreateHttp($platformToolsDownloadUri).GetResponse()
      $responseStream = $response.GetResponseStream()
      $archiveStream = [IO.MemoryStream]::new([int]$response.ContentLength)
      $responseStream.CopyTo($archiveStream)

      [IO.Directory]::CreateDirectory($platformToolsDirectory) > $null
      $archive = [IO.Compression.ZipArchive]::new($archiveStream)
      foreach ($file in $requiredFiles) {
        $entry = $archive.GetEntry("platform-tools/$file")
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, "$platformToolsDirectory/$file", $true)
      }

      $completed = $true
    }
    finally {
      if ($archive) { $archive.Dispose() }
      if ($archiveStream) { $archiveStream.Dispose() }
      if ($response) { $response.Dispose() }
      if (-not $completed) {
        Remove-Item -Path $platformToolsDirectory -Recurse -Force -ErrorAction 'SilentlyContinue'
      }
    }
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
    .$Env:adb pair $IpAddress $PairingCode
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
    $command = '{ pm list packages -u; pm list packages; } | sort | uniq -u'
    (.$Env:adb -s $DeviceId shell $command) -replace '^package:'
  }
}

function Uninstall-Packages {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param (
    [Parameter(Mandatory)]
    [string[]]$Packages,

    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    $command = @(
      # Uninstall system app update, if installed
      'pm uninstall $package > /dev/null 2>&1;'
      # `pm uninstall --user 0` uninstalls the system package for the primary user;
      # when the app is uninstalled, `pm disable-user` is used to prevent the Play Store or other OEM app stores from forced reinstalling the app or enabling it after an OTA software update
      # `am force-stop' is used to ensure that all app processes are terminated
      'pm uninstall --user 0 $package && pm disable-user $package && am force-stop $package'
    ) -join ' '

    Invoke-PackagesCommand -Packages $Packages -DeviceId $DeviceId -Command $command
  }
}

function Disable-Packages {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param (
    [Parameter(Mandatory)]
    [string[]]$Packages,

    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    $command = @(
      # Uninstall system app update, if installed
      'pm uninstall $package > /dev/null 2>&1;'
      # `pm disable-user` disables the system package for the primary user, preventing it from running in the background or receiving updates
      # `am force-stop' is used to ensure that all app processes are terminated
      # `pm clear` clears all application data
      'pm disable-user $package && am force-stop $package && pm clear $package'
    ) -join ' '

    Invoke-PackagesCommand -Packages $Packages -DeviceId $DeviceId -Command $command
  }
}

function Enable-Packages {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param (
    [Parameter(Mandatory)]
    [string[]]$Packages,

    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    Invoke-PackagesCommand -Packages $Packages -DeviceId $DeviceId -Command 'pm enable $package'
  }
}

function Reinstall-Packages {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param (
    [Parameter(Mandatory)]
    [string[]]$Packages,

    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    $command = 'cmd package install-existing $package && pm enable $package'
    Invoke-PackagesCommand -Packages $Packages -DeviceId $DeviceId -Command $command
  }
}

function Invoke-PackagesCommand {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param (
    [Parameter(Mandatory)]
    [string[]]$Packages,

    [Parameter(Mandatory)]
    [string]$DeviceId,

    [Parameter(Mandatory)]
    [string]$Command,

    [Threading.CancellationToken]$CancellationToken
  )
  process {
    $process = [Diagnostics.Process]@{
      StartInfo = @{
        FileName               = $Env:adb
        Arguments              = "-s $DeviceId shell"
        UseShellExecute        = $false
        CreateNoWindow         = $true
        RedirectStandardInput  = $true
        RedirectStandardOutput = $true
      }
    }

    try {
      $process.Start() > $null
      $registration = $CancellationToken.Register(
        [Action[object]][scriptblock]::Create({
            param($process)
            if (-not $process.HasExited) { $process.Kill() }
          }),
        $process
      )
      $process.StandardInput.NewLine = "`n"

      foreach ($package in $Packages) {
        $shellCommand = @(
          "package=$package;"
          "if output=`$({ $Command; } < /dev/null 2>&1) && case `"`$output`" in *Failure*|*Failed*|*Exception*|*Error*) false ;; esac; then"
          'echo "OK";'
          'else'
          'echo "ERR";'
          'fi'
        ) -join ' '

        $output = if (-not $process.HasExited) {
          $process.StandardInput.WriteLine($shellCommand)
          $process.StandardOutput.ReadLine()
        }

        if ($CancellationToken.IsCancellationRequested) { break }

        @{
          Package = $package
          Success = $output -eq 'OK'
        }
      }
    }
    finally {
      if ($registration) {
        $registration.Dispose()
      }
      if (-not $process.HasExited) {
        $process.Kill()
      }
      $process.Dispose()
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
