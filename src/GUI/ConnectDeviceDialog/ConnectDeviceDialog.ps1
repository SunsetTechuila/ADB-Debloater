function Show-ConnectDeviceDialog {
  [CmdletBinding()]
  [OutputType([string])]
  param()
  process {
    $Localization = Get-Localization
    $Window = Initialize-Window -Path "$PSScriptRoot/ConnectDeviceDialog.xaml" -HideCaptionButtons -AsModal

    $ViewModel = [ConnectDeviceDialogViewModel]::new()

    $Window.DataContext = [PSCustomObject]@{
      ViewModel    = $ViewModel
      Localization = $Localization
    }

    $Window.IpAddressBox.Tag = [PSCustomObject]@{ PlaceholderText = $Localization.EnterIpAddress }
    $Window.IpAddressBox.Add_TextChanged({ $ViewModel.SetIpAddress($Window.IpAddressBox.Text) })

    if ($Window.ShowDialog()) {
      $ViewModel.IpAddress
    }
  }
}

class ConnectDeviceDialogViewModel : ObservableObject {
  $OkCommand = [RelayCommand]::new(
    { $Window.DialogResult = $true },
    { $ViewModel.IsIpAddressValid() }
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

  hidden [bool] IsIpAddressValid() {
    return (Test-IpAddress -IpAddress $this.IpAddress)
  }
}
