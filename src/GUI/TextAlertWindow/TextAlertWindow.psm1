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
    Set-WindowStyling -Window $Window -HideCloseButton

    $OkButton.Content = $Localization.Ok
    $OkButton.Add_Click({ $Window.Close() })
    $MessageBlock.Text = $Message

    $Window.Add_KeyDown({
        if ($PSItem.Key -eq 'Enter') { $Window.Close() }
      })

    if ($ParentWindow) { $Window.Owner = $ParentWindow }
    $Window.ShowDialog() | Out-Null
  }
}
