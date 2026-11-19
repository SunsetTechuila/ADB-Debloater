#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$script:Localization = $null

function Get-Localization {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param()
  process {
    if (-not $script:Localization) {
      $Parameters = @{
        BindingVariable = 'localizedData'
        BaseDirectory   = "$PSScriptRoot/Resources/Localizations"
        FileName        = 'Strings'
      }
      Import-LocalizedData @Parameters -ErrorAction 'Ignore'
      if (-not $localizedData) {
        Import-LocalizedData @Parameters -UICulture 'en'
      }
      $script:Localization = $localizedData
    }

    $script:Localization
  }
}

Export-ModuleMember -Function 'Get-Localization'
