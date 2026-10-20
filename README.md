<div align="center">

# ICO

**Dynamic Notch & Island Interface for macOS**

[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%7C%20Intel)-1f2328?style=flat-square)](https://github.com/infiniunbetatester/ico/releases)
[![Touch Bar](https://img.shields.io/badge/Hardware-Touch%20Bar%20Native-0969da?style=flat-square)](https://developer.apple.com/design/human-interface-guidelines/touch-bar)
[![License](https://img.shields.io/badge/License-MIT-2da44e?style=flat-square)](LICENSE)

<br/>

*ICO transforms the MacBook hardware notch and menu bar into an interactive, context-aware command center. Engineered natively for macOS with SwiftUI, AppKit, Apple Vision, and ScreenCaptureKit.*

<br/>

[Overview](#overview) • [Features](#key-features) • [Installation](#installation) • [Architecture](#architecture--technologies) • [Shortcuts](#controls--shortcuts) • [Permissions](#security--permissions)

---

</div>

## Overview

ICO bridges the gap between hardware and software on macOS by expanding the display notch into an extensible utility hub. For devices without a hardware notch (Intel MacBook, iMac, Mac mini, external displays), ICO automatically transitions into a floating island anchored to the top of the active workspace.

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

### Workspace & Data Management
* **Temporary File Shelf:** Drag-and-drop landing strip at the upper screen boundary for staging files, images, and folders between spaces and full-screen applications.
* **Clipboard History:** Persistent clipboard stack with keyword search, timestamp tracking, and instant re-insertion.
* **Application Hub:** Fast overview of running GUI applications with window focus switching.

### Display & Hardware Adaptation
* **Hardware Notch Alignment:** Dynamically binds to the physical camera housing on MacBook Pro 14"/16" and MacBook Air models using display safe-area metrics.
* **Multi-Display & Fullscreen Spaces:** Seamlessly migrates to the screen hosting the cursor; persists across Mission Control spaces and fullscreen applications.
* **Native Touch Bar Integration:** Deep integration with MacBook Pro Touch Bar via private `DFRFoundation` APIs, providing persistent Control Strip toggles, section tabs, and pin state control.

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

<details>
<summary><strong>Manual Compilation Commands</strong></summary>

```bash
# Debug build
swift build

# Universal Release Build (Apple Silicon + Intel)
swift build -c release --arch arm64 --arch x86_64
```
</details>

---

## Controls & Shortcuts

| Action | Shortcut / Trigger | Description |
|---|---|---|
| **Expand / Collapse** | `Hover` or `Left Click` | Open or close the primary island panel |
| **Dismiss Panel** | <kbd>Esc</kbd> or `External Click` | Closes expanded island if unpinned |
| **Toggle Island** | <kbd>⌘ Cmd</kbd> + <kbd>D</kbd> | Global hotkey via status item menu |
| **Pin Island** | `Pin Button` or `Touch Bar Pin` | Prevents auto-dismissal on focus loss |
| **Compact Style** | `Status Menu → Style` | Standard (24px) / Minimal (6px) / Hidden (0px) |
| **Recenter Window** | `Status Menu → Recenter` | Recalculates screen geometry for active display |

---

## Security & Permissions

ICO runs as an unprivileged, menu-bar accessory application (`LSUIElement = true`). Specific features require standard macOS user authorizations configured in **System Settings → Privacy & Security**:

* **Screen Recording (`ScreenCaptureKit`):** Required exclusively during user-initiated OCR region selection or QR screen scanning. No continuous or background recording takes place.
* **Audio Capture:** Utilized strictly by the Per-App Mixer to route and scale process-specific audio gain.
* **Accessibility:** Used for window switching in the application overview panel.
* **AppleEvents:** Permits transport controls and metadata retrieval from supported third-party media applications.

> **Note on Code Signing:** Binaries are signed locally with an Ad-Hoc signature (`codesign -s -`) to ensure TCC permission preferences persist across application restarts.

---

## Continuous Delivery

This repository uses automated GitHub Actions workflows to compile and publish Universal Binaries directly on Apple Silicon runners upon tag dispatch:

```bash
git tag v1.0.1
git push origin v1.0.1
```

Releases automatically bundle `ICO.app` into an optimized disk image with Applications folder symlinks and release notes.

---

## License

This project is licensed under the [MIT License](LICENSE).
