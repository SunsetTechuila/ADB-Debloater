#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

."$PSScriptRoot/Paths.ps1"

#region Window

function Set-WindowStyling {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [Windows.Window]$Window,

    [switch]$NoTopBar,

    [switch]$SetWindowMaxHeight,

    [switch]$HideCloseButton
  )
  begin {
    $shouldSetMicaBackdrop = Test-DwmBackdropApiAvailability
    $shouldSetImmersiveDarkMode = Test-DwmImmersiveDarkModeApiAvailability
  }
  process {
    $ContentBorder = $Window.FindName('ContentBorder')

    if ($shouldSetMicaBackdrop) {
      Set-MicaBackdrop -Window $Window
      Set-ContentBorderThickness -Border $ContentBorder -NoTopBar:$NoTopBar

      $targetBorderThickness = $ContentBorder.BorderThickness
      $adjustBorderThicknessScript = {
        $Parameters = @{
          TargetThickness = $targetBorderThickness
          WindowState     = $Window.WindowState
        }
        $ContentBorder.BorderThickness = Get-ContentBorderAdjustedThickness @Parameters
      }.GetNewClosure()
      $Window.Add_StateChanged($adjustBorderThicknessScript)
      $adjustBorderThicknessScript.Invoke()
    }
    else {
      Set-ContentBorderThickness -Border $ContentBorder
      if ($shouldSetImmersiveDarkMode) {
        $Window.Add_Loaded({ param($Window) Set-ImmersiveDarkMode -Window $Window })
      }
    }

    $Window.Add_Loaded({ param($Window) $Window.Activate() })
    $Window.Add_Closed({ param($Window) $Window.DataContext = $null })

    if ($HideCloseButton) {
      $Window.Add_SourceInitialized({ param($Window) Hide-CloseButton -Window $Window })
    }

    if ($SetWindowMaxHeight) {
      Set-WindowMaxHeight -Window $Window
    }
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

function Get-ContentBorderAdjustedThickness {
  [CmdletBinding()]
  [OutputType([Windows.Thickness])]
  param (
    [Parameter(Mandatory)]
    [Windows.Thickness] $TargetThickness,

    [Parameter(Mandatory)]
    [Windows.WindowState]$WindowState
  )
  process {
    if ($WindowState -eq 'Maximized') {
      # window border thickness decreases when window is maximized
      [Windows.Thickness]::new(
        $TargetThickness.Left + 8,
        $TargetThickness.Top + 8,
        $TargetThickness.Right + 8,
        $TargetThickness.Bottom + 8
      )
    }
    else {
      # window border thickness decreases when WindowChrome.GlassFrameThickness is set to -1
      [Windows.Thickness]::new(
        $TargetThickness.Left + 4,
        $TargetThickness.Top + 1,
        $TargetThickness.Right + 4,
        $TargetThickness.Bottom + 4
      )
    }
  }
}

function Set-ContentBorderThickness {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [Windows.Controls.Border] $Border,

    [switch] $NoTopBar
  )
  begin {
    $defaultBorderThickness = 12
    $windowDraggableBorderHeight = 24
  }
  process {
    $Border.BorderThickness = [Windows.Thickness]::new(
      $defaultBorderThickness,
      $(if ($NoTopBar) { $windowDraggableBorderHeight } else { $defaultBorderThickness }),
      $defaultBorderThickness,
      $defaultBorderThickness
    )
  }
}

function Add-FluentStyles {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [xml]$Xaml
  )
  begin {
    $systemTheme = Get-SystemTheme
    $accentVariant = if ($systemTheme -eq 'dark') { 'light' } else { 'dark' }
    $accentColor = Get-SystemAccentColor -Variant $accentVariant
    $colorStylesPath = if ($systemTheme -eq 'dark') { $DarkStyles } else { $LightStyles }

    [xml]$colorStyles = Get-Content -Path $colorStylesPath -Raw
    $colorStyles.ResourceDictionary.SolidColorBrush[0].Color = $accentColor
  }
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

    $importedColorStyles = $Xaml.ImportNode($colorStyles.ResourceDictionary, $true)
    $mergedDictionaries.AppendChild($importedColorStyles) | Out-Null

    $Xaml
  }
}

function Initialize-Window {
  [CmdletBinding()]
  [OutputType([Windows.Window])]
  param (
    [Parameter(Mandatory)]
    [string]$Path,

    [switch]$NoTopBar,

    [switch]$SetWindowMaxHeight,

    [switch]$HideCloseButton
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    [xml]$xaml = Get-Content -Path $Path -Raw
    $xaml = Add-FluentStyles -Xaml $xaml
    $reader = New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $xaml
    $Window = [Windows.Markup.XamlReader]::Load($reader)

    $namedNodes = $xaml.SelectNodes("//*[@Name]")
    foreach ($namedNode in $namedNodes) {
      $control = $Window.FindName($namedNode.Name)
      if ($null -eq $control) { continue }
      Add-Member -InputObject $Window -NotePropertyName $namedNode.Name -NotePropertyValue $control
    }

    $Parameters = @{
      Window             = $Window
      NoTopBar           = $NoTopBar
      SetWindowMaxHeight = $SetWindowMaxHeight
      HideCloseButton    = $HideCloseButton
    }
    Set-WindowStyling @Parameters

    $Window
  }
}

#endregion

#region Window Attributes

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
    $Window.Background = 'Transparent'

    $Window.Add_SourceInitialized(
      {
        Set-DwmWindowAttribute -Window $Window -Attribute $systemBackdropType -Value $micaBackdrop
        Set-ImmersiveDarkMode -Window $Window
      }.GetNewClosure()
    )

    $WindowChrome = [Windows.Shell.WindowChrome]::GetWindowChrome($Window)
    if (-not $WindowChrome) {
      $WindowChrome = [Windows.Shell.WindowChrome]::new()
    }
    $WindowChrome.GlassFrameThickness = '-1'
    # fixes close button right margin
    $WindowChrome.NonClientFrameEdges = 'Bottom, Left, Right'

    $Window.Add_Loaded(
      {
        [Windows.Shell.WindowChrome]::SetWindowChrome($Window, $WindowChrome)
      }.GetNewClosure()
    )
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

function Hide-CloseButton {
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

  public static void RemoveCloseButton(Window window) {
    IntPtr windowPtr = new WindowInteropHelper(window).Handle;
    SetWindowLong(windowPtr, GWL_STYLE, GetWindowLong(windowPtr, GWL_STYLE) & ~WS_SYSMENU);
  }
}
'@
    }
  }
  process {
    [WinApi]::RemoveCloseButton($Window)
    $Window.UpdateLayout()
  }
}

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
