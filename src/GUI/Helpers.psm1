#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

."$PSScriptRoot/Paths.ps1"

#region Window

function Initialize-Window {
  [CmdletBinding()]
  [OutputType([Windows.Window])]
  param (
    [Parameter(Mandatory)]
    [string]$Path,

    [switch]$SetWindowMaxHeight,

    [switch]$HideCaptionButtons
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    [xml]$xaml = Get-Content -Path $Path -Raw
    $xaml = Add-FluentStyles -Xaml $xaml
    $reader = New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $xaml
    $Window = [Windows.Markup.XamlReader]::Load($reader)

    $namedNodes = $xaml.SelectNodes('//*[@Name]')
    foreach ($namedNode in $namedNodes) {
      $control = $Window.FindName($namedNode.Name)
      if ($null -eq $control) { continue }
      Add-Member -InputObject $Window -NotePropertyName $namedNode.Name -NotePropertyValue $control
    }

    Set-WindowChrome -Window $Window
    Set-ColorStyles -Window $Window

    $Window.Add_SourceInitialized({ param($Window) Sync-WindowTheme -Window $Window })

    # Bring the window to the foreground
    $Window.Add_Loaded({ param($Window) $Window.Activate() })

    $Window.Add_Closed({ param($Window) $Window.DataContext = $null })

    if (Test-DwmImmersiveDarkModeApiAvailability) {
      $Window.Add_SourceInitialized({ param($Window) Set-ImmersiveDarkMode -Window $Window })
    }
    if (Test-DwmBackdropApiAvailability) {
      $Window.Add_SourceInitialized({ param($Window) Set-MicaBackdrop -Window $Window })
    }

    if ($HideCaptionButtons) {
      $Window.Add_SourceInitialized({ param($Window) Hide-CaptionButtons -Window $Window })
    }

    if ($SetWindowMaxHeight) {
      Set-WindowMaxHeight -Window $Window
    }

    $Window
  }
}

function Set-WindowMaxHeight {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [Windows.Window] $Window
  )
  process {
    $Window.Add_StateChanged({
        param ($Window)
        if ($Window.WindowState -eq 'Maximized') {
          # makes the window content take the whole window space
          $Window.MaxHeight = (Get-ActiveScreenWorkingAreaHeight -Window $Window) + 20
        }
        else {
          # keeps the window within the screen borders when SizeToContent set to (WidthAnd)Height
          $Window.MaxHeight = Get-ActiveScreenWorkingAreaHeight -Window $Window
        }
      })
    $Window.MaxHeight = Get-ActiveScreenWorkingAreaHeight -Window $Window
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

    $windowResources = $Xaml.DocumentElement.SelectSingleNode("*[local-name()='Window.Resources']", $Xaml.CreateNavigator().NamespaceManager)
    if (-not $windowResources) {
      $windowResources = $Xaml.CreateElement('Window.Resources', $xmlNS)
      $resourceDictionary = $Xaml.CreateElement('ResourceDictionary', $xmlNS)
      $windowResources.AppendChild($resourceDictionary) | Out-Null
      $Xaml.DocumentElement.PrependChild($windowResources) | Out-Null
    }
    else {
      $resourceDictionary = $windowResources.SelectSingleNode("*[local-name()='ResourceDictionary']")
    }

    $mergedDictionaries = $Xaml.CreateElement('ResourceDictionary.MergedDictionaries', $xmlNS)
    $resourceDictionary.PrependChild($mergedDictionaries) | Out-Null

    $fluentResourceDictionary = $Xaml.CreateElement('ResourceDictionary', $xmlNS)
    $sourceAttribute = $Xaml.CreateAttribute('Source')
    $sourceAttribute.Value = $FluentStyles
    $fluentResourceDictionary.Attributes.Append($sourceAttribute) | Out-Null
    $mergedDictionaries.AppendChild($fluentResourceDictionary) | Out-Null

    $Xaml
  }
}

function Set-ColorStyles {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [Windows.Window] $Window
  )
  process {
    $systemTheme = Get-SystemTheme
    $accentVariant = if ($systemTheme -eq 'dark') { 'light' } else { 'dark' }
    $accentColor = Get-SystemAccentColor -Variant $accentVariant
    $colorStylesPath = if ($systemTheme -eq 'dark') { $DarkStyles } else { $LightStyles }

    [xml]$colorStyles = Get-Content -Path $colorStylesPath -Raw
    $colorStyles.ResourceDictionary.SolidColorBrush[0].Color = $accentColor
    $reader = New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $colorStyles
    $colorResourceDictionary = [Windows.Markup.XamlReader]::Load($reader)

    $mergedDictionaries = $Window.Resources.MergedDictionaries
    if ($Window.ColorResourceDictionary) {
      $mergedDictionaries.Remove($Window.ColorResourceDictionary) | Out-Null
    }
    $mergedDictionaries.Add($colorResourceDictionary)
    Add-Member -InputObject $Window -NotePropertyName 'ColorResourceDictionary' -NotePropertyValue $colorResourceDictionary -Force
  }
}

function Sync-WindowTheme {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [Windows.Window] $Window
  )
  process {
    $hwndSource = [Windows.Interop.HwndSource]::FromVisual($Window)
    $hwndSource.AddHook({
        param($hwnd, $message, $wParam, $lParam, $handled)
        $settingChangeMessage = 0x001A
        if (
          ($message -eq $settingChangeMessage) -and
          ([Runtime.InteropServices.Marshal]::PtrToStringAuto($lParam) -eq 'ImmersiveColorSet')
        ) {
          $window = [Windows.Interop.HwndSource]::FromHwnd($hwnd).RootVisual
          Set-ColorStyles -Window $window
          if (Test-DwmImmersiveDarkModeApiAvailability) {
            Set-ImmersiveDarkMode -Window $window
          }
        }
        [IntPtr]::Zero
      })
  }
}

function Set-WindowChrome {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [Windows.Window] $Window
  )
  begin {
    $commandBindings = @(
      [Windows.Input.CommandBinding]::new(
        [Windows.SystemCommands]::MinimizeWindowCommand,
        { param($Window) [Windows.SystemCommands]::MinimizeWindow($Window) }
      ),
      [Windows.Input.CommandBinding]::new(
        [Windows.SystemCommands]::MaximizeWindowCommand,
        { param($Window) [Windows.SystemCommands]::MaximizeWindow($Window) }
      ),
      [Windows.Input.CommandBinding]::new(
        [Windows.SystemCommands]::RestoreWindowCommand,
        { param($Window) [Windows.SystemCommands]::RestoreWindow($Window) }
      ),
      [Windows.Input.CommandBinding]::new(
        [Windows.SystemCommands]::CloseWindowCommand,
        { param($Window) [Windows.SystemCommands]::CloseWindow($Window) }
      )
    )
  }
  process {
    $Window.CommandBindings.AddRange($commandBindings)

    $WindowChrome = [Windows.Shell.WindowChrome]::GetWindowChrome($Window)
    if (-not $WindowChrome) {
      $WindowChrome = [Windows.Shell.WindowChrome]::new()
    }

    $WindowChrome.GlassFrameThickness = '-1'
    $WindowChrome.UseAeroCaptionButtons = $false
    if ($Window.ResizeMode -eq 'NoResize') { $WindowChrome.ResizeBorderThickness = 0 }

    $Window.Add_Loaded(
      {
        if ($Window.TopBarElement) {
          $WindowChrome.CaptionHeight = $Window.TopBarElement.ActualHeight + $Window.Padding.Top
        }
        Hide-NativeCaptionButtons -Window $Window
        [Windows.Shell.WindowChrome]::SetWindowChrome($Window, $WindowChrome)
      }.GetNewClosure()
    )
  }
}

function Set-MicaBackdrop {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [Windows.Window] $Window
  )
  begin {
    $systemBackdropType = 38
    $micaBackdrop = 2
  }
  process {
    Set-DwmWindowAttribute -Window $Window -Attribute $systemBackdropType -Value $micaBackdrop
    $Window.Background = 'Transparent'
  }
}

function Set-ImmersiveDarkMode {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [Windows.Window] $Window
  )
  begin {
    $useImmersiveDarkMode = 20
    $useDarkMode = if ((Get-SystemTheme) -eq 'dark') { 1 } else { 0 }
  }
  process {
    Set-DwmWindowAttribute -Window $Window -Attribute $useImmersiveDarkMode -Value $useDarkMode
  }
}

function Hide-CaptionButtons {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [Windows.Window]$Window
  )
  process {
    $captionButtons = $Window.Template.FindName('CaptionButtons', $Window)
    $captionButtons.Visibility = 'Collapsed'
  }
}

function Hide-NativeCaptionButtons {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [Windows.Window]$Window
  )
  begin {
    if (-not ('WinApi' -as [type])) {
      $referensedAssemblies = @('PresentationFramework', 'WindowsBase')
      if ($PSVersionTable.PSVersion.Major -eq 5) { $referensedAssemblies += 'PresentationCore', 'System.Xaml' }
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

  public static void HideNativeCaptionButtons(Window window) {
    IntPtr windowPtr = new WindowInteropHelper(window).Handle;
    SetWindowLong(windowPtr, GWL_STYLE, GetWindowLong(windowPtr, GWL_STYLE) & ~WS_SYSMENU);
  }
}
'@
    }
  }
  process {
    [WinApi]::HideNativeCaptionButtons($Window)
  }
}

#endregion

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
    '#{0:X2}{1:X2}{2:X2}' -f $(
      if ($Variant -eq 'light') {
        $accentPalette[4], $accentPalette[5], $accentPalette[6]
      }
      else {
        $accentPalette[16], $accentPalette[17], $accentPalette[18]
      }
    )
  }
}

function Get-ActiveScreenWorkingAreaHeight {
  [CmdletBinding()]
  [OutputType([int])]
  param (
    [Parameter(Mandatory)]
    [Windows.Window] $Window
  )
  begin {
    Add-Type -AssemblyName 'System.Windows.Forms'
  }
  process {
    $windowHandle = ([Windows.Interop.WindowInteropHelper]::new($Window)).Handle
    [Windows.Forms.Screen]::FromHandle($windowHandle).WorkingArea.Height
  }
}

#endregion System

#region DWM

function Set-DwmWindowAttribute {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [Windows.Window] $Window,

    [Parameter(Mandatory)]
    [int] $Attribute,

    [Parameter(Mandatory)]
    [int] $Value
  )
  begin {
    if (-not ('DWM' -as [type])) {
      $referensedAssemblies = @('PresentationFramework', 'WindowsBase')
      if ($PSVersionTable.PSVersion.Major -eq 5) { $referensedAssemblies += 'PresentationCore', 'System.Xaml' }
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
    [Environment]::OSVersion.Version.Build -ge 22523
  }
}

function Test-DwmImmersiveDarkModeApiAvailability {
  [CmdletBinding()]
  [OutputType([bool])]
  param()
  process {
    [Environment]::OSVersion.Version.Build -ge 19041
  }
}

#endregion

#region MVVM

class ObservableObject : ComponentModel.INotifyPropertyChanged, ComponentModel.INotifyPropertyChanging {
  hidden [ComponentModel.PropertyChangedEventHandler] $PropertyChanged

  hidden [ComponentModel.PropertyChangingEventHandler] $PropertyChanging

  [void] add_PropertyChanged([ComponentModel.PropertyChangedEventHandler] $handler) {
    $this.PropertyChanged = [Delegate]::Combine($this.PropertyChanged, $handler)
  }

  [void] remove_PropertyChanged([ComponentModel.PropertyChangedEventHandler] $handler) {
    $this.PropertyChanged = [Delegate]::Remove($this.PropertyChanged, $handler)
  }

  [void] add_PropertyChanging([ComponentModel.PropertyChangingEventHandler] $handler) {
    $this.PropertyChanging = [Delegate]::Combine($this.PropertyChanging, $handler)
  }

  [void] remove_PropertyChanging([ComponentModel.PropertyChangingEventHandler] $handler) {
    $this.PropertyChanging = [Delegate]::Remove($this.PropertyChanging, $handler)
  }

  [void] OnPropertyChanged([ComponentModel.PropertyChangedEventArgs] $eventArguments) {
    if ($this.PropertyChanged) {
      $this.PropertyChanged.Invoke($this, $eventArguments)
    }
  }

  [void] OnPropertyChanging([ComponentModel.PropertyChangingEventArgs] $eventArguments) {
    if ($this.PropertyChanging) {
      $this.PropertyChanging.Invoke($this, $eventArguments)
    }
  }

  [bool] SetProperty([string] $propertyName, $newValue) {
    if ([object]::Equals($this.$propertyName, $newValue)) {
      return $false
    }

    $this.OnPropertyChanging($propertyName)
    $this.$propertyName = $newValue
    $this.OnPropertyChanged($propertyName)

    return $true
  }

  [bool] SetProperty($newValue, [scriptblock] $comparer, [string] $propertyName) {
    $currentValue = $this.$propertyName

    if ($comparer.Invoke($currentValue, $newValue)) {
      return $false
    }

    $this.OnPropertyChanging($propertyName)
    $this.$propertyName = $newValue
    $this.OnPropertyChanged($propertyName)

    return $true
  }

  # Calling SetProperty in a loop over a large collection is slow in PowerShell due to per-call method overhead.
  # Use this overload when updating items bound to a virtualized control,
  # where off-screen items have no realized container subscribed to PropertyChanged/PropertyChanging.
  static [void] SetProperty([Collections.IEnumerable] $items, [string] $propertyName, $newValue) {
    foreach ($item in $items) {
      if ($item.PropertyChanged -or $item.PropertyChanging) {
        $item.SetProperty($propertyName, $newValue)
      }
      else {
        $item.$propertyName = $newValue
      }
    }
  }
}

class RelayCommand : Windows.Input.ICommand {
  [EventHandler] $CanExecuteChanged

  hidden [scriptblock] $_execute

  hidden [scriptblock] $_canExecute

  [void] add_CanExecuteChanged([EventHandler] $handler) {
    $this.CanExecuteChanged = [Delegate]::Combine($this.CanExecuteChanged, $handler)
  }

  [void] remove_CanExecuteChanged([EventHandler] $handler) {
    $this.CanExecuteChanged = [Delegate]::Remove($this.CanExecuteChanged, $handler)
  }

  RelayCommand([scriptblock] $execute) {
    $this._execute = $execute
  }

  RelayCommand([scriptblock] $execute, [scriptblock] $canExecute) {
    $this._execute = $execute
    $this._canExecute = $canExecute
  }

  [void] NotifyCanExecuteChanged() {
    if ($this.CanExecuteChanged) {
      $this.CanExecuteChanged.Invoke($this, [EventArgs]::Empty)
    }
  }

  [bool] CanExecute([object] $parameter) {
    if ($this._canExecute) {
      return $this._canExecute.Invoke($parameter)
    }
    return $true
  }

  [void] Execute([object] $parameter) {
    $this._execute.Invoke($parameter)
  }

  [void] ExecuteIfCan([object] $parameter) {
    if ($this.CanExecute($parameter)) {
      $this.Execute($parameter)
    }
  }
}

#endregion
