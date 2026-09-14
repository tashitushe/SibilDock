# SibilDock

A floating, draggable glass-style widget dock for macOS. It sits above every
Space and full-screen app, shows a small set of live system widgets in a
liquid-glass tile style, and stays out of the way — no Dock icon, no menu bar
icon.

## Widgets

- **Battery & Wi-Fi** — battery ring (blue while charging, orange when low) with a Wi-Fi status badge
- **Weather** — current temperature and conditions for your location
- **Now Playing** — play/pause with a progress ring, reading from Music or Spotify
- **Clock** — time and weekday
- **Network Speed** — live download/upload throughput
- **Memory** — RAM usage ring

## Features

- Floating and draggable — no fixed position, just drag it anywhere
- Vertical or horizontal layout, switchable from Settings
- Drag-to-reorder the widgets from Settings
- Remembers its position and layout between launches
- Launches at login by default
- Right-click the dock for **Settings** and **About**

## Install

Download the latest build from [Releases](../../releases), unzip, and drag
`SibilDock.app` to `/Applications`.

Since the app is ad-hoc signed (not notarized by Apple), the first launch
needs one extra step: right-click `SibilDock.app` → **Open** → **Open**, or
allow it under **System Settings → Privacy & Security** if macOS blocks it.

## Build from source

Requires macOS 13+ and Xcode's command line tools.

```bash
git clone https://github.com/tashitushe/SibilDock.git
cd SibilDock
./build_app.sh release
open SibilDock.app
```

## Permissions

- **Location** — only used to fetch the local weather forecast
- **Automation (Apple Events)** — used to read now-playing info from Music/Spotify
