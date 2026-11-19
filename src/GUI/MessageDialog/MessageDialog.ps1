function Show-MessageDialog {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)]
    [string]$Message,

    [string]$Title,

    [ValidateSet('Warning', 'Error')]
    [string]$Icon,

    [ValidateSet('Ok', 'OkCancel')]
    [string]$Buttons = 'Ok'
  )
  process {
    $Localization = Get-Localization
    $Window = Initialize-Window -Path "$PSScriptRoot/MessageDialog.xaml" -HideCaptionButtons -AsModal

    $ViewModel = [MessageDialogViewModel]::new($Message, $Title, $Icon, $Buttons)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $Window.ShowDialog()
  }
}

class MessageDialogViewModel {
  $OkCommand = [RelayCommand]::new({
      $Window.DialogResult = $true
    })

  $CancelCommand = [RelayCommand]::new({
      $Window.Close()
    })

  [string] $Message

  [string] $Title

  [string] $Icon

  [string] $Buttons

  MessageDialogViewModel(
    [string] $message,
    [string] $title,
    [string] $icon,
    [string] $buttons
  ) {
    $this.Message = $message
    $this.Title = $title
    $this.Icon = $icon
    $this.Buttons = $buttons
  }
}
