#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

."$PSScriptRoot/../../Paths.ps1"
."$PSScriptRoot/../Paths.ps1"

Remove-Module -Name 'Helpers' -Force -ErrorAction 'SilentlyContinue'
Import-Module -Name $Helpers -DisableNameChecking

$Parameters = @{
  BindingVariable = 'Localization'
  BaseDirectory   = $Localizations
  FileName        = 'Strings'
}
Import-LocalizedData @Parameters

function Show-TextAlertWindow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Message,

    [System.Windows.Window] $ParentWindow
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
  }
  process {
    [xml]$xaml = Get-Content -Path "$PSScriptRoot/TextAlertWindow.xaml"
    $xaml = Add-FluentStyles -Xaml $xaml
    $reader = (New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $xaml)
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
      Set-Variable -Name ($PSItem.Name) -Value $Window.FindName($PSItem.Name)
    }

    $OkButton.Content = $Localization.Ok
    $OkButton.Add_Click({ $Window.Close() })
    $MessageBlock.Text = $Message

    $Window.Add_KeyDown({
        if ($PSItem.Key -eq 'Enter') { $Window.Close() }
      })

    $shouldSetMicaBackdrop = Test-DwmBackdropApiAvailability
    $shouldSetImmersiveDarkMode = Test-DwmImmersiveDarkModeApiAvailability

    Set-ContentBorderThickness -Border $ContentBorder

    if ($shouldSetMicaBackdrop) {
      $Window.Add_Loaded({ Set-MicaBackdrop -Window $Window })

      $Parameters = @{
        TargetThickness = $ContentBorder.BorderThickness
        WindowState     = $Window.WindowState
      }
      $ContentBorder.BorderThickness = Get-ContentBorderAdjustedThickness @Parameters
    }
    else {
      Set-ContentBorderThickness -Border $ContentBorder
      if ($shouldSetImmersiveDarkMode) {
        $Window.Add_Loaded({ Set-ImmersiveDarkMode -Window $Window })
      }
    }

    $Window.Add_SourceInitialized({ Hide-CloseButton -Window $Window })
    $Window.Add_Loaded({ $Window.Activate() })

    Add-ColorStyles -Window $Window

    if ($ParentWindow) { $Window.Owner = $ParentWindow }
    $Window.ShowDialog() | Out-Null
  }
}
