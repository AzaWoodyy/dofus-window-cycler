# Dofus Window Switcher

AutoHotkey v2 tray app for cycling through open Dofus windows in a chosen order.

Unofficial tool, not affiliated with Ankama.

The app only changes Windows focus. It does not click, send gameplay keys, repeat actions, or automate Dofus gameplay.

## Requirements

- Windows
- [AutoHotkey v2](https://www.autohotkey.com/)

## Usage

1. Run `DofusWindowCycler.ahk` with AutoHotkey v2.
2. Open the tray icon and choose `Open`.
3. Click `Refresh` if your Dofus windows are not listed.
4. Use the checkbox beside each window to include or exclude it from cycling.
5. Reorder windows with `Move Up`, `Move Down`, `Send First`, and `Send Last`.
6. Use `Listen...` to set the cycle shortcut.

Newly detected windows are checked by default. Unchecked windows remain visible in the list so they can be re-enabled later.

The main window is a compact native Windows UI. Use `Cycling enabled` to pause or resume from the UI without opening the tray menu.

Supported shortcut capture includes keyboard keys, `MButton`, `XButton1`, and `XButton2`.

`XButton1` and `XButton2` are owned by the switcher while it is running, so browser Back/Forward behavior may not pass through.

## Debugging

Debug is off by default for faster cycling, and the diagnostics panel stays hidden until debug is enabled.

Enable `Debug Enabled` from the tray or UI when investigating an issue. Logs appear in the UI and are also written to:

```text
%APPDATA%\DofusWindowCycler\debug.log
```

Use `Clear Debug` before reproducing a bug, then `Copy Debug` to copy the visible log.

## Startup

To start the switcher with Windows, create a Startup shortcut pointing to AutoHotkey v2 with this script as its argument.

Example target:

```text
C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe
```

Example argument:

```text
C:\path\to\DofusWindowCycler.ahk
```
