# ADB Debloater

<!-- markdownlint-disable-next-line MD036 -->
**A PowerShell tool to debloat Android devices with ADB**

## Screenshots

| Dark theme, blue accent, blue wallpaper               | Light theme, green accent, green wallpaper             |
| ----------------------------------------------------- | ------------------------------------------------------ |
| ![screenshot1](/assets/screenshots/packages_dark.png) | ![screenshot2](/assets/screenshots/packages_light.png) |
| ![screenshot3](/assets/screenshots/devices_dark.png)  | ![screenshot4](/assets/screenshots/devices_light.png)  |

## Features

- Options to: uninstall, disable and enable apps
- Curated bloatware list from vendors like Google, Samsung, Xiaomi, and others
- WPF GUI in the WinUI 3 style
- Localized interface, app names and tooltips
- Automatic ADB downloading if it is not found in the PATH

## Usage

1. Launch PowerShell in any terminal
2. Download this repo:

   ```powershell
   iwr 'https://codeload.github.com/SunsetTechuila/ADB-Debloater/zip/refs/heads/master' -useb -out 'ADB-Debloater.zip'; expand-archive 'ADB-Debloater.zip'; cd 'ADB-Debloater'; mv */* ./
   ```

3. Enable debugging on your mobile device<sup>[`ℹ️`](https://developer.android.com/tools/adb#Enabling)</sup>
4. Connect your mobile device to your PC
5. Run the script:

   ```cmd
   ./start
   ```

Next time you can run the script by double clicking the "start" file in the "ADB-Debloater" folder.

## Requirements

- Windows 10 or higher
- PowerShell 5.1 or higher

![166300207-7e53ae91-08c3-455e-8d77-edc351dd4023](https://github.com/user-attachments/assets/15e002c2-d4bf-4a0a-9e16-bcc97dce66e0)
