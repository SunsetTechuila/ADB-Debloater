function Show-ProgressRingDialog {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param (
    [Parameter(Mandatory)]
    [scriptblock]$Operation,

    [object[]]$ArgumentList = @(),

    [string]$Message
  )
  process {
    $Localization = Get-Localization
    $Window = Initialize-Window -Path "$PSScriptRoot/ProgressRingDialog.xaml" -HideCaptionButtons -AsModal

    $ViewModel = [ProgressRingDialogViewModel]::new($Message)

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $task = [BackgroundTask]@{
      Operation    = $Operation
      ArgumentList = $ArgumentList
      OnFinished   = { $Window.DialogResult = $true }
    }

    $Window.Add_ContentRendered({
        $task.Start()
      })

    if ($Window.ShowDialog()) {
      @{
        Cancelled = $false
        Output    = $task.WaitForResult()
      }
    }
    else {
      $task.ForceStopAsync()
      @{ Cancelled = $true }
    }
  }
}

class ProgressRingDialogViewModel {
  $CancelCommand = [RelayCommand]::new({
      $Window.Close()
    })

  [string] $Message

  ProgressRingDialogViewModel($message) {
    $this.Message = $message
  }
}
