#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

."$PSScriptRoot/Paths.ps1"

#region Window

function Set-WindowMaxHeight {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [System.Windows.Window] $Window
  )
  process {
    $Window.Add_StateChanged({
        param ($Window)
        if ($Window.WindowState -eq 'Maximized') {
          # makes the window content take the whole window space
          $Window.MaxHeight = (Get-MaximizedScreenHeight) + 20
        }
        else {
          # keeps the window within the screen borders when SizeToContent set to (WidthAnd)Height
          $Window.MaxHeight = Get-MaximizedScreenHeight
        }
      })
    $Window.MaxHeight = Get-MaximizedScreenHeight
  }
}

function Get-ContentBorderAdjustedThickness {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [System.Windows.Thickness] $TargetThickness,

    [Parameter(Mandatory)]
    [System.Windows.WindowState]$WindowState
  )
  process {
    if ($WindowState -eq 'Maximized') {
      # window border thickness decreases when window is maximized
      "
        $($TargetThickness.Left + 8),
        $($TargetThickness.Top + 8),
        $($TargetThickness.Right + 8),
        $($TargetThickness.Bottom + 8)
      "
    }
    else {
      # window border thickness decreases when WindowChrome.GlassFrameThickness is set to -1
      "
        $($TargetThickness.Left + 4),
        $($TargetThickness.Top + 1),
        $($TargetThickness.Right + 4),
        $($TargetThickness.Bottom + 4)
      "
    }
  }
}

function Set-ContentBorderThickness {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [System.Windows.Controls.Border] $Border,

    [switch] $NoTopBar
  )
  begin {
    $defaultBorderThickness = 12
    $windowDraggableBorderHeight = 24
  }
  process {
    $Border.BorderThickness = "
      $defaultBorderThickness,
      $(if ($NoTopBar) { $windowDraggableBorderHeight } else { $defaultBorderThickness }),
      $defaultBorderThickness,
      $defaultBorderThickness
    "
  }
}

function Add-ColorStyles {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [System.Windows.Window] $Window
  )
  process {
    $systemTheme = Get-SystemTheme
    $accentVariant = if ($systemTheme -eq 'dark') { 'light' } else { 'dark' }
    $accentColor = Get-SystemAccentColor -Variant $accentVariant
    $colorStylesPath = if ($systemTheme -eq 'dark') { $DarkStyles } else { $LightStyles }

    [xml]$colorStyles = Get-Content -Path $colorStylesPath
    $colorStyles.ResourceDictionary.SolidColorBrush[0].Color = $accentColor
    $reader = (New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $colorStyles)
    $Window.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Load($reader))
  }
}

function Add-FluentStyles {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [xml]$Xaml
  )
  process {
    $xmlNS = $Xaml.DocumentElement.NamespaceURI

    $windowResources = $Xaml.CreateElement('Window.Resources', $xmlNS)
    $resourceDictionary = $Xaml.CreateElement('ResourceDictionary', $xmlNS)
    $mergedDictionaries = $Xaml.CreateElement('ResourceDictionary.MergedDictionaries', $xmlNS)
    $fluentResourceDictionary = $Xaml.CreateElement('ResourceDictionary', $xmlNS)

    $sourceAttribute = $Xaml.CreateAttribute('Source')
    $sourceAttribute.Value = $FluentStyles

    $windowResources.AppendChild($resourceDictionary) | Out-Null
    $resourceDictionary.AppendChild($mergedDictionaries) | Out-Null
    $fluentResourceDictionary.Attributes.Append($sourceAttribute) | Out-Null
    $mergedDictionaries.AppendChild($fluentResourceDictionary) | Out-Null

    $Xaml.DocumentElement.PrependChild($windowResources) | Out-Null

    $Xaml
  }
}

#endregion

#region Window Attributes

function Set-MicaBackdrop {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [System.Windows.Window] $Window,

    [switch] $NoChrome
  )
  begin {
    $systemBackdropType = 38
    $micaBackdrop = 2
    $useImmersiveDarkMode = 20
  }
  process {
    $Window.Background = 'Transparent'

    $WindowChrome = [System.Windows.Shell.WindowChrome]::new()
    $WindowChrome.GlassFrameThickness = '-1'
    # fixes close button right margin
    $WindowChrome.NonClientFrameEdges = 'Bottom, Left, Right'
    [System.Windows.Shell.WindowChrome]::SetWindowChrome($Window, $WindowChrome)

    $useDarkMode = if ((Get-SystemTheme) -eq 'dark') { 1 } else { 0 }
    Set-DwmWindowAttribute -Window $Window -Attribute $systemBackdropType -Value $micaBackdrop
    Set-DwmWindowAttribute -Window $Window -Attribute $useImmersiveDarkMode -Value $useDarkMode
  }
}

function Set-ImmersiveDarkMode {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [System.Windows.Window] $Window
  )
  begin {
    $useImmersiveDarkMode = 20
  }
  process {
    $useDarkMode = if ((Get-SystemTheme) -eq 'dark') { 1 } else { 0 }
    Set-DwmWindowAttribute -Window $Window -Attribute $useImmersiveDarkMode -Value $useDarkMode
  }
}

#endregion Window Attributes

#region System

function Get-SystemTheme {
  [CmdletBinding()]
  [OutputType([string])]
  param ()
  begin {
    $Parameters = @{
      Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
      Name = 'SystemUsesLightTheme'
    }
  }
  process {
    switch (Get-ItemPropertyValue @Parameters) {
      0 { return 'dark' }
      1 { return 'light' }
    }
  }
}

function Get-SystemAccentColor {
  [CmdletBinding()]
  [OutputType([string])]
  param (
    [Parameter(Mandatory)]
    [ValidateSet('light', 'dark')]
    [string]$Variant
  )
  begin {
    $Parameters = @{
      Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
      Name = 'AccentPalette'
    }
  }
  process {
    $accentPalette = Get-ItemPropertyValue @Parameters

    $accentColor = if ($Variant -eq 'light') {
      $accentPalette[4..6]
    }
    else {
      $accentPalette[16..18]
    }

    '#' + ( -join ($accentColor | ForEach-Object {
          $channel = '{0:X}' -f $PSItem
          if ($channel.Length -eq 1) { $channel = "0$channel" }
          $channel
        }))
  }
}

function Get-MaximizedScreenHeight {
  [CmdletBinding()]
  [OutputType([int])]
  param ()
  begin {
    Add-Type -AssemblyName 'System.Windows.Forms'
  }
  process {
    [System.Windows.Forms.Screen]::FromHandle((Get-Process -Id $PID).MainWindowHandle).WorkingArea.Height
  }
}

#endregion System

#region DWM

function Set-DwmWindowAttribute {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [System.Windows.Window] $Window,

    [Parameter(Mandatory)]
    [int] $Attribute,

    [Parameter(Mandatory)]
    [int] $Value
  )
  begin {
    $referensedAssemblies = @('PresentationFramework', 'System.Xaml', 'WindowsBase')
    if ($PSVersionTable.PSVersion.Major -eq 5) { $referensedAssemblies += 'PresentationCore' }
    Add-Type -ReferencedAssemblies $referensedAssemblies -TypeDefinition @'
using System;
using System.Windows;
using System.Windows.Interop;
using System.Runtime.InteropServices;

public class DWM {
  [DllImport("dwmapi.dll", SetLastError = true)]
  private static extern int DwmSetWindowAttribute(
    IntPtr hwnd,
    uint dwAttribute,
    ref int pvAttribute,
    uint cbAttribute
  );

  public static void SetWindowAttribute(Window window, uint attribute, int value) {
    IntPtr windowPtr = new WindowInteropHelper(window).Handle;
    DwmSetWindowAttribute(windowPtr, attribute, ref value, sizeof(int));
  }
}
'@
  }
  process {
    [DWM]::SetWindowAttribute($Window, $Attribute, $Value)
  }
}

function Test-DwmBackdropApiAvailability {
  [CmdletBinding()]
  [OutputType([bool])]
  param()
  process {
    [System.Environment]::OSVersion.Version.Build -ge 22523
  }
}

function Test-DwmImmersiveDarkModeApiAvailability {
  [CmdletBinding()]
  [OutputType([bool])]
  param()
  process {
    [System.Environment]::OSVersion.Version.Build -ge 19041
  }
}

#endregion

function Hide-CloseButton {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [System.Windows.Window]$Window
  )
  begin {
    $referensedAssemblies = @('PresentationFramework', 'System.Xaml', 'WindowsBase')
    if ($PSVersionTable.PSVersion.Major -eq 5) { $referensedAssemblies += 'PresentationCore' }
    Add-Type -ReferencedAssemblies $referensedAssemblies -TypeDefinition @'
using System;
using System.Windows;
using System.Windows.Interop;
using System.Runtime.InteropServices;

public class WinApi {
  private const int GWL_STYLE = -16;
  private const int WS_SYSMENU = 0x80000;

  [DllImport("user32.dll", SetLastError = true)]
  private static extern int GetWindowLong(
    IntPtr hWnd,
    int nIndex
  );

  [DllImport("user32.dll")]
  private static extern int SetWindowLong(
    IntPtr hWnd,
    int nIndex,
    int dwNewLong
  );

  public static void RemoveCloseButton(Window window) {
    IntPtr windowPtr = new WindowInteropHelper(window).Handle;
    SetWindowLong(windowPtr, GWL_STYLE, GetWindowLong(windowPtr, GWL_STYLE) & ~WS_SYSMENU);
  }
}
'@
  }
  process {
    [WinApi]::RemoveCloseButton($Window)
    $Window.UpdateLayout()
  }
}
