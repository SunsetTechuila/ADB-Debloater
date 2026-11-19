function Show-PairDeviceDialog {
  [CmdletBinding()]
  [OutputType([hashtable])]
  param()
  process {
    $Localization = Get-Localization
    $Window = Initialize-Window -Path "$PSScriptRoot/PairDeviceDialog.xaml" -HideCaptionButtons -AsModal

    $ViewModel = [PairDeviceDialogViewModel]::new()

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $Window.IpAddressBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.EnterIpAddress }
    $Window.IpAddressBox.Add_TextChanged({ $ViewModel.SetIpAddress($Window.IpAddressBox.Text) })

    $Window.PairingCodeBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.EnterPairingCode }
    $Window.PairingCodeBox.Add_TextChanged({ $ViewModel.SetPairingCode($Window.PairingCodeBox.Text) })

    if ($Window.ShowDialog()) {
      @{
        IpAddress   = $ViewModel.IpAddress
        PairingCode = $ViewModel.PairingCode
      }
    }
  }
}

class PairDeviceDialogViewModel : ObservableObject {
  $OkCommand = [RelayCommand]::new(
    { $Window.DialogResult = $true},
    { $ViewModel.AreInputsValid() }
  )

  $CancelCommand = [RelayCommand]::new({
      $Window.Close()
    })

  hidden [string] $IpAddress = ''
  [void] SetIpAddress($value) {
    if ($this.SetProperty('IpAddress', $value.Trim())) {
      $this.OkCommand.NotifyCanExecuteChanged()
    }
  }

  hidden [string] $PairingCode = ''
  [void] SetPairingCode($value) {
    if ($this.SetProperty('PairingCode', $value.Trim())) {
      $this.OkCommand.NotifyCanExecuteChanged()
    }
  }

  hidden $PairingCodeRegex = '^\d{6}$'
  hidden [bool] AreInputsValid() {
    return (
      ($this.PairingCode -match $this.PairingCodeRegex) -and
      (Test-IpAddress -IpAddress $this.IpAddress)
    )
  }
}
