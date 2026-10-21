<div align="center">

# ICO

**Dynamic Notch & Island Interface for macOS**

[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%7C%20Intel)-1f2328?style=flat-square)](https://github.com/infiniunbetatester/ico/releases)
[![Touch Bar](https://img.shields.io/badge/Hardware-Touch%20Bar%20Native-0969da?style=flat-square)](https://developer.apple.com/design/human-interface-guidelines/touch-bar)
[![License](https://img.shields.io/badge/License-MIT-2da44e?style=flat-square)](LICENSE)

<br/>

**English** • [Русский](README_RU.md)

<br/>

*ICO transforms the MacBook hardware notch and menu bar into an interactive, context-aware command center. Engineered natively for macOS with SwiftUI, AppKit, Apple Vision, and ScreenCaptureKit.*

<br/>

[Overview](#overview) • [Features](#key-features) • [Custom Widgets](#-custom-widgets-development) • [Telegram Bridge](#-telegram-clipboard-bridge) • [Installation](#installation) • [Shortcuts](#controls--shortcuts)

---

</div>

## Overview

> [!IMPORTANT]
> **Hardware Compatibility Notice:** ICO is designed and optimized specifically for Mac computers **without** a physical display notch (MacBook Pro/Air with Touch Bar or standard bezels, iMac, Mac mini, Mac Studio, Mac Pro, and external monitors). It brings a sleek virtual notch and Dynamic Island experience to these displays. **ICO is not intended for Mac models with a built-in hardware display notch** (e.g. MacBook Pro 14"/16" and MacBook Air with M2/M3 physical notches).

ICO brings the dynamic notch and island experience to Mac displays by placing an extensible utility hub anchored to the top of the screen:

```
       ┌───────────────────────────────┐
       │           ╭───────╮           │  <-- Dynamic Island / Hardware Notch
       │           ╰───────╯           │
       │                               │
       │    [Media] [Tools] [Shelf]    │  <-- Interactive Expandable Panels
       │  [Clipboard]  [Apps]  [Mixer] │
       └───────────────────────────────┘
```

---

## Key Features

### Media Remote & Audio Intelligence
* **Dynamic Mini Player:** Embedded artwork thumbnail, live track marquee with alpha-gradient edge masks, and adaptive frequency visualizer bars that sample the dominant palette of the album art.
* **Universal Media Remote:** Intercepts system media playback via native frameworks. Compatible with Apple Music, Spotify, Yandex Music, YouTube, Safari, Chrome, and Telegram.
* **Expanded Player Controls:** Interactive timeline scrubber, volume slider, shuffle/repeat toggles, and track rating directly from the island panel.

### Screen & Productivity Tools
* **Vision Text Recognition (OCR):** Crosshair region selector backed by `ScreenCaptureKit` and Apple `Vision`. Extracts text in English, Russian, and system languages, automatically formatting and copying to the clipboard.
* **QR Code Suite:**
  * **Screen Scanner:** Select any QR code on screen to decode payloads instantly with automated URL validation and one-click browser launch.
  * **Vector Generator:** Live QR generation from text or clipboard input using `CoreImage` with crisp vector scaling, clipboard copying, and PNG export.
* **Per-App Volume Mixer:** Granular audio gain adjustment for individual running processes without altering the global macOS master volume.
* **Precision Countdown Timer:** Compact circular countdown with progress badges, ambient sound alerts, and island expansion upon completion.

### Touch Bar Integration
* **Configurable Presentation Modes:**
  * **On Focus:** Active only when expanding or interacting with the dynamic island.
  * **Persistent Touch Bar (Always On):** Keeps the ICO Touch Bar visible continuously, even while multitasking in other applications, while **fully preserving the native macOS Control Strip on the right** (volume, brightness, and Siri remain accessible).
* **Instant Actions:** Tab switcher (Music, Files, Clipboard, Apps, Widgets), expand/collapse trigger, and pin toggle directly on the Touch Bar.

### Workspace & Data Management
* **Temporary File Shelf:** Drag-and-drop landing strip at the upper screen boundary for staging files, images, and folders between spaces and full-screen applications.
* **Smart Clipboard History:** Persistent clipboard stack with individual item deletion, full history clearing, search filtering, and 1-click **Telegram forwarding** to mobile devices.
* **Application Hub:** Instant overview of running GUI applications with window focus switching.
* **Window Settings (Always on Top):** Toggle whether the island floats above fullscreen windows or behaves as a standard window that doesn't block workspace workflows.

---

## 🧩 Custom Widgets Development (HTML / CSS / JS)

Users can build custom interactive widgets for the ICO notch in minutes. Widgets run inside an isolated `WKWebView` with hardware graphics acceleration and transparent backgrounds.

### 1. File Structure
All widgets live locally in your user directory:
```
~/.ico/widgets/<widget-id>/
├── widget.json   # Metadata (title, icon, height)
└── index.html    # Layout, styles, and JavaScript logic
```
*(You can click the **«📁 Folder»** button inside the Widgets panel to open this folder in Finder immediately).*

### 2. Manifest `widget.json`
```json
{
  "name": "My Widget",
  "icon": "sparkles",
  "description": "Custom HTML/JS notch widget",
  "height": 260
}
```
*Supports any system SF Symbols name (e.g., `sparkles`, `cloud.sun.fill`, `timer`, `note.text`, `chart.bar.fill`).*

### 3. Native JavaScript API (`window.ico`)
Every widget gets access to the native `window.ico` bridge. Timers and state **persist across collapse and expand cycles**:

| Method | Description | Example |
|---|---|---|
| `window.ico.toast(message, icon)` | Shows a native floating pill toast below the notch | `window.ico.toast('Done!', 'checkmark')` |
| `window.ico.copy(text)` | Copies text into the macOS system pasteboard | `window.ico.copy('https://example.com')` |
| `window.ico.close()` | Collapses the island back to compact mode | `window.ico.close()` |
| `window.ico.openURL(url)` | Opens an external URL in the default browser | `window.ico.openURL('https://binance.com')` |
| `window.ico.notify(title, body)` | Native macOS notification banner with sound (works in background!) | `window.ico.notify('Timer', '25 minutes is up!')` |
| `window.ico.sound(name)` | Plays a macOS system alert sound (`Glass`, `Ping`, `Hero`, `Tink`, `Morse`) | `window.ico.sound('Glass')` |
| `window.ico.storage.set(key, val)` | Persistent storage per widget ID (never erased on reboot) | `window.ico.storage.set('theme', 'dark')` |
| `window.ico.storage.get(key, default)` | Reads persisted key value | `const val = window.ico.storage.get('theme', 'dark')` |
| `window.ico.fetch(url, options)` | Native HTTP request proxy **without CORS restrictions** | `const res = await window.ico.fetch('https://api.binance.com/...')` |
| `window.ico.onCollapse(fn)` | Notch collapse lifecycle hook (pause heavy canvas/intervals to save CPU) | `window.ico.onCollapse(() => pause())` |
| `window.ico.onExpand(fn)` | Notch expand lifecycle hook | `window.ico.onExpand(() => resume())` |

### 4. Minimal Widget Example
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {
      background: transparent;
      color: #fff;
      font-family: -apple-system, sans-serif;
      padding: 16px;
      user-select: none;
    }
    .card {
      background: rgba(255, 255, 255, 0.08);
      border-radius: 12px;
      padding: 14px;
      text-align: center;
    }
    button {
      background: #fff;
      color: #000;
      border: none;
      padding: 6px 14px;
      border-radius: 8px;
      font-weight: 600;
      cursor: pointer;
    }
  </style>
</head>
<body>
  <div class="card">
    <h3>Hello from ICO! 🏝</h3>
    <button onclick="window.ico.toast('Clicked!', 'hand.wave.fill')">Click Me</button>
  </div>
</body>
</html>
```

---

## 💡 Popular Widget Ideas for the Notch

Here are some great widget concepts you can create or install in 1 click from the built-in **Widget Store**:

| Widget | Concept & Use Case | Tech / API |
|---|---|---|
| 🪙 **Crypto / Stock Ticker** | Live Bitcoin, Ethereum, Solana, and S&P 500 quotes with price change badges | Binance WebSocket / CoinGecko / Yahoo Finance |
| 🌤 **Minimalist Weather** | Current weather, precipitation radar, and hourly forecast | Open-Meteo / wttr.in (No API key needed) |
| 📝 **Quick Scratchpad** | Sticky memo pad for temporary text, phone numbers, and code snippets | `localStorage` + `window.ico.copy` |
| ⏳ **Pomodoro & Focus Timer** | 25/5 interval productivity clock with circular progress animation | HTML5 Canvas / CSS SVG stroke |
| 🐙 **GitHub Activity Watcher** | Real-time notifications for GitHub mentions, assigned PRs, and commit streaks | GitHub REST API |
| 🕒 **World Clock Matrix** | Parallel timezones for remote teams (New York, London, Tokyo, Berlin) | Native JS `Intl.DateTimeFormat` |
| ⚡ **System Glance Monitor** | Instant CPU load, RAM usage, Wi-Fi speed, and battery health percentage | Lightweight system scripts |
| 🤖 **AI Quick Prompt Bar** | 1-line query field to ask ChatGPT / Claude without leaving your current workspace | OpenAI / Anthropic API |

---

## ✈️ Telegram Clipboard Bridge (Mac → Phone)

ICO enables 1-click forwarding of any copied text, links, or screenshots directly to your phone via your personal Telegram Bot:

1. In the island header, click the **«⚙️ Settings»** gear button on the right.
2. In the **«Telegram Sync»** section, configure:
   * **Bot Token** (create a free bot in 30 seconds via [@BotFather](https://t.me/BotFather))
   * **Chat ID** (find your user ID via [@userinfobot](https://t.me/userinfobot))
3. Click **«Test Connection»** to verify setup.
4. Now in the **«Clipboard»** tab, every entry features a paper plane **«✈️»** button that instantly sends that snippet to your mobile Telegram!

---

## Technical Specifications

| Component | Implementation |
|---|---|
| **Core Architecture** | Pure Swift 6.0, AppKit lifecycle, SwiftUI rendering engine |
| **Target Platforms** | Universal Binary: `arm64` (Apple Silicon M1–M4) & `x86_64` (Intel Core) |
| **Deployment Target** | macOS 14.0 (Sonoma) or higher (macOS 15 Sequoia verified) |
| **Screen Capture** | `ScreenCaptureKit` for performant, hardware-accelerated frame acquisition |
| **Machine Vision** | Apple `Vision` framework (`VNRecognizeTextRequest`, `VNDetectBarcodesRequest`) |
| **Image Synthesis** | `CoreImage` (`CIQRCodeGenerator`) with anti-aliased bitmap representation |
| **Input Monitoring** | Global and local `NSEvent` monitors for dismiss gestures and hotkeys |
| **Touch Bar** | Dynamic private framework bindings (`DFRFoundation.framework`) |

---

## Installation

### Option 1: Universal DMG Image (Recommended)

1. Download the latest release from the [Releases](https://github.com/infiniunbetatester/ico/releases) page.
2. Open `ICO.dmg` and drag `ICO.app` into `/Applications`.
3. Launch **ICO** from Spotlight or the Applications folder.

### Option 2: Build from Source

Requirements: macOS 14.0+, Command Line Tools or Xcode (`xcode-select --install`).

```bash
# Clone the repository
git clone https://github.com/infiniunbetatester/ico.git
cd ico

# Compile local binary
./build_app.sh

# Or generate a distribution DMG
./build_dmg.sh
```

---

## Controls & Shortcuts

| Action | Shortcut / Trigger | Description |
|---|---|---|
| **Expand / Collapse** | `Hover` or `Left Click` | Open or close the primary island panel |
| **Dismiss Panel** | <kbd>Esc</kbd> or `External Click` | Closes expanded island if unpinned |
| **Settings Panel** | `Gear Button ⚙️` | Notch size, Always on Top, and Telegram Sync |
| **Pin Island** | `Pin Button 📌` or `Touch Bar Pin` | Prevents auto-dismissal on focus loss |
| **Compact Style** | `Settings → Notch Style` | Standard (24px) / Minimal (6px) / Hidden (0px) |
| **Always on Top** | `Settings → Always on Top` | Toggles whether notch covers fullscreen windows |

---

## License

This project is licensed under the [MIT License](LICENSE).
