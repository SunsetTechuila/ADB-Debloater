#region Window

function Initialize-Window {
  [CmdletBinding()]
  [OutputType([Windows.Window])]
  param (
    [Parameter(Mandatory)]
    [string]$Path,

    [switch]$HideCaptionButtons,

    [switch]$AsModal
  )
  process {
    if (-not [Windows.Application]::Current) {
      $application = [Windows.Application]::new()
      $application.ShutdownMode = 'OnExplicitShutdown'
      Add-FluentStyles
      Set-ColorStyles
    }

    $reader = [Xml.XmlReader]::Create($Path)
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    $reader.Close()

    foreach ($entry in [Windows.NameScope]::GetNameScope($Window)) {
      $Window.PSObject.Properties.Add([PSNoteProperty]::new($entry.Key, $entry.Value))
    }

    Set-WindowChrome -Window $Window

    $Window.Add_SourceInitialized({ param($Window) Sync-WindowTheme -Window $Window })

    # Bring the window to the foreground
    $Window.Add_Loaded({ param($Window) $Window.Activate() })

    # WPF does not detach bindings on close.
    # Clearing DataContext unsubscribes bindings so they can be garbage-collected and avoids teardown errors on exit.
    $Window.Add_Closed({ param($Window) $Window.DataContext = $null })

    if (Test-DwmBackdropApiAvailability) {
      $Window.Add_SourceInitialized({ param($Window) Set-MicaBackdrop -Window $Window })
    }

    if ($HideCaptionButtons) {
      $Window.Add_SourceInitialized({ param($Window) Hide-CaptionButtons -Window $Window })
    }

    $Window.WindowStartupLocation = 'CenterScreen'
    if ($AsModal) {
      $owner = [Windows.Application]::Current.Windows |
        Where-Object { $PSItem.IsVisible } |
          Select-Object -Last 1
      if ($owner) {
        $Window.Owner = $owner
        $Window.WindowStartupLocation = 'CenterOwner'
        $Window.ShowInTaskbar = $false
        $Window.Topmost = $true
      }
    }

    if (
      $Window.SizeToContent -ne 'Manual' -and
      ($Window.MaxWidth -eq [double]::PositiveInfinity -or
      $Window.MaxHeight -eq [double]::PositiveInfinity)
    ) {
      Set-WindowMaxSize -Window $Window
    }

    $Window
  }
}

function Set-WindowMaxSize {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [Windows.Window] $Window
  )
  begin {
    Add-Type -AssemblyName 'System.Windows.Forms'
  }
  process {
    # Run after the HWND is placed on the target monitor (giving the real screen and DPI), but before the first layout pass
    # so SizeToContent measures with the clamped bounds, preventing virtualized controls from de-virtualizing
    # and ensuring the window is centered using its clamped dimensions.
    [Windows.PresentationSource]::AddSourceChangedHandler($Window, {
        param($Window, $eventArguments)

        $isTeardownEvent = -not $eventArguments.NewSource
        if ($isTeardownEvent) { return }

        $windowHandle = [Windows.Interop.WindowInteropHelper]::new($Window).Handle
        $activeScreen = [Windows.Forms.Screen]::FromHandle($windowHandle)
        $dpi = [Windows.Media.VisualTreeHelper]::GetDpi($Window)

        if ($Window.MaxWidth -eq [double]::PositiveInfinity) {
          $Window.MaxWidth = $activeScreen.WorkingArea.Width / $dpi.DpiScaleX
        }
        if ($Window.MaxHeight -eq [double]::PositiveInfinity) {
          $Window.MaxHeight = $activeScreen.WorkingArea.Height / $dpi.DpiScaleY
        }
      })

    $Window.Add_ContentRendered({
        param($Window)
        # Prevent clearing MaxWidth/MaxHeight from causing the window to expand past the screen.
        $Window.SizeToContent = 'Manual'
        # Prevent the window from being clipped when maximized (+16px overhang) or when moved to a larger monitor.
        $Window.MaxWidth = [double]::PositiveInfinity
        $Window.MaxHeight = [double]::PositiveInfinity
      })
  }
}

function Add-FluentStyles {
  [CmdletBinding()]
  param ()
  process {
    $reader = [Xml.XmlReader]::Create("$PSScriptRoot/Styles/Fluent.xaml")
    $fluentResourceDictionary = [Windows.Markup.XamlReader]::Load($reader)
    $reader.Close()
    [Windows.Application]::Current.Resources.MergedDictionaries.Add($fluentResourceDictionary)
    Register-ContextMenuAnimation
  }
}

function Register-ContextMenuAnimation {
  [CmdletBinding()]
  param ()
  begin {
    $animateFromBottom = [Windows.Controls.Primitives.Popup].GetProperty(
      'AnimateFromBottom',
      [Reflection.BindingFlags]'NonPublic,Instance'
    )
  }
  process {
    [Windows.EventManager]::RegisterClassHandler(
      [Windows.Controls.ContextMenu],
      [Windows.Controls.ContextMenu]::OpenedEvent,
      [Windows.RoutedEventHandler] {
        param($ContextMenu)
        $menuRoot = $ContextMenu.Template.FindName('MenuRoot', $ContextMenu)
        $isAnimatingFromBottom = $animateFromBottom.GetValue($ContextMenu.Parent)
        $menuRoot.VerticalAlignment = if ($isAnimatingFromBottom) { 'Bottom' } else { 'Top' }

        if (
          [Windows.SystemParameters]::ClientAreaAnimation -and
          [Windows.SystemParameters]::MenuAnimation
        ) {
          $revealSizer = $ContextMenu.Template.FindName('RevealSizer', $ContextMenu)
          $ContextMenu.FindResource('RevealStoryboard').Begin($revealSizer)
        }
      }.GetNewClosure()
    )
  }
}

function Set-ColorStyles {
  [CmdletBinding()]
  param ()
  process {
    $appTargetTheme = Get-AppTargetTheme
    $accentVariant = if ($appTargetTheme -eq 'dark') { 'light' } else { 'dark' }
    $accentColor = Get-SystemAccentColor -Variant $accentVariant
    $colorStylesPath = if ($appTargetTheme -eq 'dark') {
      "$PSScriptRoot/Styles/Dark.xaml"
    }
    else {
      "$PSScriptRoot/Styles/Light.xaml"
    }

    $reader = [Xml.XmlReader]::Create($colorStylesPath)
    $colorResourceDictionary = [Windows.Markup.XamlReader]::Load($reader)
    $reader.Close()
    $colorResourceDictionary.AccentBrush.Color = $accentColor

    $application = [Windows.Application]::Current
    $mergedDictionaries = $application.Resources.MergedDictionaries
    if ($application.Properties.ColorResourceDictionary) {
      $mergedDictionaries.Remove($application.Properties.ColorResourceDictionary) > $null
    }
    $mergedDictionaries.Add($colorResourceDictionary)
    $application.Properties.ColorResourceDictionary = $colorResourceDictionary
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
          Set-ColorStyles
          if (Test-DwmImmersiveDarkModeApiAvailability) {
            $window = [Windows.Interop.HwndSource]::FromHwnd($hwnd).RootVisual
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

    $windowChrome = [Windows.Shell.WindowChrome]::new()
    [Windows.Shell.WindowChrome]::SetWindowChrome($Window, $windowChrome)

    $windowChrome.GlassFrameThickness = '-1'
    $windowChrome.UseAeroCaptionButtons = $false
    if ($Window.ResizeMode -eq 'NoResize') { $windowChrome.ResizeBorderThickness = 0 }

    $Window.Add_SourceInitialized({
        param($Window)
        Hide-NativeCaptionButtons -Window $Window
        # WPF initially sizes the content smaller to leave room for the native title bar and resize borders.
        # Re-measure after WindowChrome removes them so no empty space is left on the right and bottom.
        $Window.InvalidateMeasure()
      })

    $Window.Add_Loaded({
        if ($Window.TopBarElement) {
          $windowChrome.CaptionHeight = $Window.TopBarElement.ActualHeight + $Window.Padding.Top
        }
      }.GetNewClosure())
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
    $gwlStyle = -16
    $wsSysMenu = 0x80000
    $winApi = Get-WinApi
  }
  process {
    $windowHandle = [Windows.Interop.WindowInteropHelper]::new($Window).Handle
    $style = $winApi::GetWindowLong($windowHandle, $gwlStyle)
    $winApi::SetWindowLong($windowHandle, $gwlStyle, ($style -band (-bnot $wsSysMenu))) > $null
  }
}

#endregion

#region System

function Get-AppTargetTheme {
  [CmdletBinding()]
  [OutputType([string])]
  param ()
  process {
    $appsUseLightTheme = [Microsoft.Win32.Registry]::GetValue(
      'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
      'AppsUseLightTheme',
      $null
    )
    switch ($appsUseLightTheme) {
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
  process {
    $accentPalette = [Microsoft.Win32.Registry]::GetValue(
      'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent',
      'AccentPalette',
      $null
    )
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

#endregion System

#region DWM

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
    Set-ImmersiveDarkMode -Window $Window
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
    $useDarkMode = if ((Get-AppTargetTheme) -eq 'dark') { 1 } else { 0 }
  }
  process {
    Set-DwmWindowAttribute -Window $Window -Attribute $useImmersiveDarkMode -Value $useDarkMode
  }
}

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
    $winApi = Get-WinApi
    $intSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf([type][int])
  }
  process {
    $windowHandle = [Windows.Interop.WindowInteropHelper]::new($Window).Handle
    $winApi::DwmSetWindowAttribute($windowHandle, [uint32]$Attribute, [ref]$Value, $intSize) > $null
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

#region WinAPI

$script:WinApi = $null

function Get-WinApi {
  [CmdletBinding()]
  [OutputType([type])]
  param()
  process {
    if ($script:WinApi) { return $script:WinApi }

    $typeBuilder = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
      'WinApi', 'Run'
    ).DefineDynamicModule('WinApi').DefineType('WinApi', 'Public, Abstract, Sealed')

    $methods = @(
      @{
        Name       = 'GetWindowLong'
        Dll        = 'user32.dll'
        ReturnType = [int]
        Parameters = [IntPtr], [int]
      }
      @{
        Name       = 'SetWindowLong'
        Dll        = 'user32.dll'
        ReturnType = [int]
        Parameters = [IntPtr], [int], [int]
      }
      @{
        Name       = 'DwmSetWindowAttribute'
        Dll        = 'dwmapi.dll'
        ReturnType = [int]
        Parameters = [IntPtr], [uint32], [int].MakeByRefType(), [uint32]
      }
    )

    foreach ($method in $methods) {
      $typeBuilder.DefinePInvokeMethod(
        $method.Name,
        $method.Dll,
        'Public, Static, PinvokeImpl',
        'Standard',
        $method.ReturnType,
        [type[]]$method.Parameters,
        'Winapi',
        'Unicode'
      ).SetImplementationFlags('PreserveSig')
    }

    $script:WinApi = $typeBuilder.CreateType()
    $script:WinApi
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

#region Background Task

class BackgroundTask {
  hidden [Threading.CancellationTokenSource] $CancellationTokenSource

  hidden [PowerShell] $Runner

  hidden [IAsyncResult] $Invocation

  hidden [hashtable] $UiSync

  BackgroundTask([hashtable] $parameters) {
    $operation = $parameters.Operation
    $argumentList = $parameters.ArgumentList
    if (-not $argumentList) { $argumentList = @() }
    $onProgress = $parameters.OnProgress
    $onFinished = $parameters.OnFinished

    $this.CancellationTokenSource = [Threading.CancellationTokenSource]::new()
    $this.UiSync = @{ PendingOperation = $null }

    $initialSessionState = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    if ($operation.Module) {
      $initialSessionState.ImportPSModule($operation.Module.Path)
    }

    $dispatcher = [Windows.Threading.Dispatcher]::CurrentDispatcher
    $onProgressAction = [Action[object]]$onProgress
    $onFinishedAction = [Action[object]]$onFinished

    $this.Runner = [PowerShell]::Create($initialSessionState).AddScript({
        param(
          $moduleName,
          $operation,
          $argumentList,
          $cancellationToken,
          $dispatcher,
          $onProgressAction,
          $onFinishedAction,
          $uiSync
        )
        $ErrorActionPreference = 'Stop'
        $PSDefaultParameterValues['*:CancellationToken'] = $cancellationToken

        function Invoke-UiOperation {
          param(
            [Parameter(Mandatory)]
            [Action[object]]$Callback,

            [object]$Argument
          )
          $dispatcherOperation = $null

          [Threading.Monitor]::Enter($uiSync)
          try {
            if ($cancellationToken.IsCancellationRequested) {
              return $false
            }
            $dispatcherOperation = $dispatcher.BeginInvoke('Normal', $Callback, $Argument)
            $uiSync.PendingOperation = $dispatcherOperation
          }
          finally {
            [Threading.Monitor]::Exit($uiSync)
          }

          try {
            $dispatcherOperation.Task.Wait($cancellationToken)
          }
          catch [OperationCanceledException] {
            $dispatcherOperation.Abort() > $null
            return $false
          }
          finally {
            [Threading.Monitor]::Enter($uiSync)
            $uiSync.PendingOperation = $null
            [Threading.Monitor]::Exit($uiSync)
          }

          $true
        }

        # Rebind to this background runspace so it can run independently
        $scriptBlock = if ($moduleName) {
          $module = Get-Module -Name $moduleName
          & $module { $PSDefaultParameterValues['*:CancellationToken'] = $cancellationToken }
          # Bind to its module's scope so it can access module-scoped variables and functions
          $module.NewBoundScriptBlock($operation)
        }
        else {
          [scriptblock]::Create($operation)
        }

        try {
          if ($onProgressAction) {
            & $scriptBlock @argumentList | ForEach-Object -Process {
              if (-not (Invoke-UiOperation -Callback $onProgressAction -Argument $PSItem)) {
                exit
              }
            }
          }
          else {
            & $scriptBlock @argumentList
          }
        }
        finally {
          if ($onFinishedAction) {
            Invoke-UiOperation -Callback $onFinishedAction > $null
          }
        }
      }).AddParameters(@(
        $operation.Module.Name,
        $operation,
        $argumentList,
        $this.CancellationTokenSource.Token,
        $dispatcher,
        $onProgressAction,
        $onFinishedAction,
        $this.UiSync
      ))
  }

  [void] Start() {
    $this.Invocation = $this.Runner.BeginInvoke()
  }

  [object] WaitForResult() {
    try {
      $result = $this.Runner.EndInvoke($this.Invocation)
      # Unwrapping an empty collection with `$()` returns `[AutomationNull]::Value`,
      # which throws in PowerShell 5.1 class methods
      if ($result.Count) { return $($result) }
      return $null
    }
    catch {
      # Unwrap the inner exception from `Exception calling "EndInvoke..."`
      throw $PSItem.Exception.InnerException
    }
    finally {
      $this.Runner.Runspace.CloseAsync()
    }
  }

  [void] ForceStopAsync() {
    $this.CancellationTokenSource.Cancel()
    
    [Threading.Monitor]::Enter($this.UiSync)
    if ($this.UiSync.PendingOperation) {
      $this.UiSync.PendingOperation.Abort() > $null
      $this.UiSync.PendingOperation = $null
    }
    [Threading.Monitor]::Exit($this.UiSync)
    
    $this.Runner.Runspace.CloseAsync()
  }
}

#endregion

#region Validation

function Test-IpAddress {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [string]$IpAddress
  )
  begin {
    $ipV4Regex = '^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]):(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$'
    $ipV6Regex = '^\[(?:(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,7}:|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}|(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}|(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:(?::[0-9a-fA-F]{1,4}){1,6}|:(?:(?::[0-9a-fA-F]{1,4}){1,7}|:)|(?:(?:[0-9a-fA-F]{1,4}:){6}|(?:[0-9a-fA-F]{1,4}:){5}:|(?:[0-9a-fA-F]{1,4}:){4}(?::[0-9a-fA-F]{1,4})?:|(?:[0-9a-fA-F]{1,4}:){3}(?::[0-9a-fA-F]{1,4}){0,2}:|(?:[0-9a-fA-F]{1,4}:){2}(?::[0-9a-fA-F]{1,4}){0,3}:|[0-9a-fA-F]{1,4}:(?::[0-9a-fA-F]{1,4}){0,4}:|:(?::[0-9a-fA-F]{1,4}){0,5}:)(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))(?:%[0-9a-zA-Z._-]+)?\]:(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$'
  }
  process {
    ($IpAddress -match $ipV4Regex) -or ($IpAddress -match $ipV6Regex)
  }
}

#endregion
