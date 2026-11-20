#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$Resources = "$PSScriptRoot/Resources"

#region ADB Setup

function Set-Adb {
  [CmdletBinding()]
  param()
  begin {
    $adbFromResources = "$Resources/ADB/adb.exe"
  }
  process {
    $Parameters = @{
      Name        = 'adb'
      CommandType = 'Application'
      TotalCount  = 1
      ErrorAction = 'Ignore'
    }
    $adbFromPath = (Get-Command @Parameters).Source

    $Env:adb = if ($adbFromPath) { $adbFromPath } else { $adbFromResources }
  }
}

function Test-Adb {
  [CmdletBinding()]
  [OutputType([bool])]
  param()
  process {
    [IO.File]::Exists($Env:adb)
  }
}

function Get-Adb {
  [CmdletBinding()]
  param()
  begin {
    Add-Type -AssemblyName 'System.IO.Compression', 'System.IO.Compression.FileSystem'
    $adbDirectory = "$Resources/ADB"
    $platformToolsDownloadUri = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
    $requiredFiles = @('AdbWinApi.dll', 'AdbWinUsbApi.dll', 'adb.exe')
  }
  process {
    $completed = $false
    try {
      $response = [Net.WebRequest]::CreateHttp($platformToolsDownloadUri).GetResponse()
      $responseStream = $response.GetResponseStream()
      $archiveStream = [IO.MemoryStream]::new([int]$response.ContentLength)
      $responseStream.CopyTo($archiveStream)

      [IO.Directory]::CreateDirectory($adbDirectory) > $null
      $archive = [IO.Compression.ZipArchive]::new($archiveStream)
      foreach ($file in $requiredFiles) {
        $entry = $archive.GetEntry("platform-tools/$file")
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, "$adbDirectory/$file", $true)
      }

      $completed = $true
    }
    finally {
      if ($archive) { $archive.Dispose() }
      if ($archiveStream) { $archiveStream.Dispose() }
      if ($response) { $response.Dispose() }
      if (-not $completed) {
        Remove-Item -Path $adbDirectory -Recurse -Force -ErrorAction 'Ignore'
      }
    }
  }
}

#endregion

#region ADB

function Start-AdbServer {
  [CmdletBinding()]
  param()
  process {
    # `adb start-server` writes status messages to stderr
    $ErrorActionPreference = 'Continue'
    $output = & $Env:adb start-server 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
  }
}

function Stop-AdbServer {
  [CmdletBinding()]
  param()
  process {
    & $Env:adb kill-server
  }
}

function Test-AdbServer {
  [CmdletBinding()]
  [OutputType([bool])]
  param()
  process {
    [bool][Diagnostics.Process]::GetProcessesByName('adb')
  }
}

function Connect-DeviceOverWiFi {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string]$IpAddress
  )
  process {
    $output = & $Env:adb connect $IpAddress
    # `adb connect` writes error messages to stdout and exits with code 0 when connection fails
    if ($output -notmatch '^(already )?connected to') { throw $output }
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
    # Manually throw to avoid the message being wrapped
    # with "The running command stopped because the..." in PowerShell 5
    $ErrorActionPreference = 'Continue'
    $output = & $Env:adb pair $IpAddress $PairingCode 2>&1
    if ($LASTEXITCODE -ne 0) { throw $output }
  }
}

function Watch-Devices {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param(
    [Threading.CancellationToken]$CancellationToken
  )
  process {
    $process = [Diagnostics.Process]@{
      StartInfo = @{
        FileName               = $Env:adb
        Arguments              = 'track-devices -l'
        UseShellExecute        = $false
        CreateNoWindow         = $true
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

      $lengthBuffer = [char[]]::new(4)
      while (-not $process.HasExited) {
        $headerLength = $process.StandardOutput.ReadBlock($lengthBuffer, 0, 4)
        if ($headerLength -lt 4) { break }

        $payloadRemainingLength = [Convert]::ToInt32((-join $lengthBuffer), 16)
        $devices = @{}
        # Do not use ReadBlock here because the ADB server's payload length is based on `\n` characters,
        # but on Windows adb.exe writes to stdout in text mode, expanding each `\n` to `\r\n`.
        while ($payloadRemainingLength -gt 0) {
          $line = $process.StandardOutput.ReadLine()
          $lineLengthWithUnixNewline = $line.Length + 1
          $payloadRemainingLength -= $lineLengthWithUnixNewline

          $fields = -split $line
          $id = $fields[0]
          $status = $fields[1]
          if ($status -eq 'device') { $status = 'connected' }
          $model = ($fields -match '^model:\w+$')[0]
          $model = if ($model) { $model.Replace('model:', '').Replace('_', ' ') } else { 'unknown' }

          $devices[$id] = @{
            Status = $status
            Model  = $model
          }
        }

        $devices
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

#region Packages

function Get-InstalledPackages {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)]
    [string]$DeviceId
  )
  process {
    (& $Env:adb -s $DeviceId shell cmd package list packages --user 0) -replace '^package:'
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
    (& $Env:adb -s $DeviceId shell cmd package list packages -e --user 0) -replace '^package:'
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
    (& $Env:adb -s $DeviceId shell cmd package list packages -d --user 0) -replace '^package:'
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
    $command = @(
      '('
      'cmd package list packages -u --user 0 &'
      'installed=$(cmd package list packages --user 0);'
      'wait;'
      'IFS=;'
      'echo $installed'
      ') | sort | uniq -u'
    ) -join ' '
    (& $Env:adb -s $DeviceId shell $command) -replace '^package:'
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
      'if $isSystem; then'
      # Uninstall system app update, if installed
      'cmd package uninstall $package > /dev/null 2>&1;'
      # Uninstall the system package for the primary user
      'cmd package uninstall --user 0 $package &&'
      # Prevent the Play Store or other OEM app stores from forced reinstalling the app or enabling it after an OTA software update
      # May fail on OEM-restricted packages or already disabled packages
      '{ cmd package disable-user --user 0 $package > /dev/null 2>&1 || true; };'
      'else'
      'cmd package uninstall $package;'
      'fi'
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
      'if $isSystem; then cmd package uninstall $package > /dev/null 2>&1; fi;'
      # Disable the package for the primary user, preventing it from running in the background or receiving updates
      'cmd package disable-user --user 0 $package &&'
      # Clear all application data
      'cmd package clear --user 0 $package'
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
    Invoke-PackagesCommand -Packages $Packages -DeviceId $DeviceId -Command 'cmd package enable --user 0 $package'
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
    $command = 'cmd package install-existing --user 0 $package && cmd package enable --user 0 $package'
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

      $usesIsSystem = $Command -cmatch '\$\{?isSystem\b'
      if ($usesIsSystem -and -not $process.HasExited) {
        $process.StandardInput.WriteLine(
          'systemPackages="$(cmd package list packages -s --user 0 < /dev/null 2>/dev/null | tr "\n" " ")"'
        )
      }

      foreach ($package in $Packages) {
        $shellCommand = @(
          "package=$package;"
          if ($usesIsSystem) {
            'if [[ "$systemPackages" == *"package:$package "* ]]; then'
            'isSystem=true;'
            'else'
            'isSystem=false;'
            'fi;'
          }
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

Export-ModuleMember -Function @(
  'Set-Adb'
  'Test-Adb'
  'Get-Adb'
  'Start-AdbServer'
  'Stop-AdbServer'
  'Test-AdbServer'
  'Connect-DeviceOverWiFi'
  'Pair-DeviceOverWiFi'
  'Watch-Devices'
  'Get-InstalledPackages'
  'Get-EnabledPackages'
  'Get-DisabledPackages'
  'Get-UninstalledPackages'
  'Uninstall-Packages'
  'Disable-Packages'
  'Enable-Packages'
  'Reinstall-Packages'
  'Get-AppsToProcess'
)
