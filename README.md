# SmartBarHide
A utility to configure menu bar hiding behavior per-display for macOS.

## Why?
Modern MacBooks have notches. External displays do not. Default behavior of hiding the menu bar when an app is fullscreen makes sense on regular, rectangular displays, but not on notched displays as you get this big, ugly black bar of wasted space where you can just as easily still put your menu bar for quick glances at menu bar icons without having to hover your mouse over the top. There is a way to always show the menu bar but that does that on all displays which means you give up on space unnecessarily on monitors . There is no documented, public way of configuring this behavior per-display.

## Compatibility Warning
This program uses an undocumented private macOS API's to achieve this: SLSSetMenuBarVisibilityOverrideOnDisplay from SkyLight. It was verified to be working on:
- macOS 26.6.2 (25G83) on Apple Silicon
- macOS 27.0 (26A428)

Please let me know if you encounter any issues on other versions!

## Building
```
make app
```

## Usage
**Make sure "Automatically hide and show the menu bar" in macOS System Settings > Menu Bar is set to the default value, "In Full Screen Only".**

You may have to allow the app to run from System Settings > Privacy and Security, depending on your security settings.

Launch the app once and it runs in the background, launch it again to reveal a settings menu with toggles for all detected displays.

By default, the built-in display will always show the menu bar while any additional display you add will have the menu bar hidden. Your preferences are saved even if you unplug and replug the monitor. An option to run at login exists in the settings window.

### Command Line
Several command line flags exist for interacting with a running instance of SmartBarHide through a socket.
```sh
SmartBarHide.app/Contents/MacOS/SmartBarHide --status
SmartBarHide.app/Contents/MacOS/SmartBarHide --settings
SmartBarHide.app/Contents/MacOS/SmartBarHide --enable
SmartBarHide.app/Contents/MacOS/SmartBarHide --disable
SmartBarHide.app/Contents/MacOS/SmartBarHide --quit
```

## Contributing
Issues and PR's are welcome! This code is licensed under the MIT license, refer to LICENSE for details.

## Changelog
### 0.1.1 (2026-09-15)
Add more checks for menu bar state restore to (hopefully) mitigate a bug

### 0.1.0 (2026-09-14)
Initial release
