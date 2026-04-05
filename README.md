# StableClaw

[![Download APK](https://img.shields.io/badge/Download-APK-green?style=for-the-badge&logo=android)](https://github.com/ctz168/stableclaw_android/releases/latest)
[![Build Flutter APK & AAB](https://github.com/ctz168/stableclaw_android/actions/workflows/flutter-build.yml/badge.svg)](https://github.com/ctz168/stableclaw_android/actions/workflows/flutter-build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Node.js](https://img.shields.io/badge/Node.js-22-green?logo=node.js)](https://nodejs.org/)
[![Android](https://img.shields.io/badge/Android-10%2B-brightgreen?logo=android)](https://www.android.com/)
[![Flutter](https://img.shields.io/badge/Flutter-3.24-02569B?logo=flutter)](https://flutter.dev/)

<p align="center">
  <img src="assets/ic_launcher.png" alt="StableClaw App Mockup" width="700"/>
</p>

> Run **StableClaw AI Gateway** on Android — standalone Flutter app with built-in terminal, web dashboard, optional dev tools, and one-tap setup.

---

## What is StableClaw?

StableClaw brings the [StableClaw](https://github.com/ctz168/stableclaw) AI gateway to Android. It sets up a full Ubuntu environment via proot, installs Node.js and StableClaw, and provides a native Flutter UI to manage everything — no root required.

---

## Features

### Flutter App
- **One-Tap Setup** — Downloads Ubuntu rootfs, Node.js 22, and StableClaw automatically
- **Built-in Terminal** — Full terminal emulator with extra keys toolbar, copy/paste, clickable URLs
- **Gateway Controls** — Start/stop gateway with status indicator and health checks
- **AI Providers** — Configure API keys and select models for 7 providers (Anthropic, OpenAI, Google Gemini, OpenRouter, NVIDIA NIM, DeepSeek, xAI)
- **SSH Remote Access** — Start/stop SSH server, set root password, view connection info with copyable commands
- **Configure Menu** — Run `stableclaw configure` in a built-in terminal to manage gateway settings
- **Node Device Capabilities** — 7 capabilities (15 commands) exposed to AI via WebSocket node protocol
- **Token URL Display** — Captures auth token from onboarding, shows it with a copy button
- **Web Dashboard** — Embedded WebView loads the dashboard with authentication token
- **View Logs** — Real-time gateway log viewer with search/filter
- **Onboarding** — Configure API keys and binding directly in-app
- **Optional Packages** — Install Go (Golang), Homebrew, and OpenSSH as optional dev tools
- **Settings** — Auto-start, battery optimization, system info, package status, re-run setup
- **Foreground Service** — Keeps the gateway alive in the background with uptime tracking
- **Setup Notifications** — Progress bar notifications during environment setup

### Node Device Capabilities

The Flutter app connects to the gateway as a **node**, exposing Android hardware to the AI.

| Capability | Commands | Permission |
|------------|----------|------------|
| **Camera** | `camera.snap`, `camera.clip`, `camera.list` | Camera |
| **Canvas** | `canvas.navigate`, `canvas.eval`, `canvas.snapshot` | None (not implemented) |
| **Flash** | `flash.on`, `flash.off`, `flash.toggle`, `flash.status` | Camera (torch) |
| **Location** | `location.get` | Location |
| **Screen** | `screen.record` | MediaProjection consent |
| **Sensor** | `sensor.read`, `sensor.list` | Body Sensors |
| **Haptic** | `haptic.vibrate` | None |

---

## Quick Start

### Flutter App

1. Download the latest APK from [Releases](https://github.com/ctz168/stableclaw_android/releases)
2. Install the APK on your Android device
3. Open the app and tap **Begin Setup**
4. After setup completes, optionally install **Go** or **Homebrew** from the package cards
5. Configure your API keys in **Onboarding**
6. Tap **Start Gateway** on the dashboard

Or build from source:

```bash
git clone https://github.com/ctz168/stableclaw_android.git
cd stableclaw_android/flutter_app
flutter build apk --release
```

### CLI

```bash
curl -fsSL https://raw.githubusercontent.com/ctz168/stableclaw_android/main/install.sh | bash
stableclawx setup
stableclawx start
```

---

## Requirements

| Requirement | Details |
|-------------|---------|
| **Android** | 10 or higher (API 29) |
| **Storage** | ~500MB for Ubuntu + Node.js + StableClaw |
| **Architectures** | arm64-v8a, armeabi-v7a, x86_64 |

---

## Architecture

```
┌───────────────────────────────────────────────────┐
│                Flutter App (Dart)                 │
│  ┌──────────┐ ┌──────────┐ ┌──────────────┐       │
│  │ Terminal │ │ Gateway  │ │ Web Dashboard│       │
│  │ Emulator │ │ Controls │ │   (WebView)  │       │
│  └─────┬────┘ └─────┬────┘ └──────┬───────┘       │
│        │            │             │               │
│  ┌─────┴────────────┴─────────────┴─────────────┐ │
│  │           Native Bridge (Kotlin)             │ │
│  └─────────────────┬────────────────────────────┘ │
│                    │                              │
│  ┌─────────────────┴────────────────────────────┐ │
│  │         Node Provider (WebSocket)            │ │
│  │  Camera · Flash · Location · Screen          │ │
│  │  Sensor · Haptic · Canvas                    │ │
│  └─────────────────┬────────────────────────────┘ │
└────────────────────┼──────────────────────────────┘
                     │
┌────────────────────┼──────────────────────────────┐
│  proot-distro      │              Ubuntu          │
│  ┌─────────────────┴──────────────────────────┐   │
│  │   Node.js 22 + Bionic Bypass               │   │
│  │   ┌─────────────────────────────────────┐  │   │
│  │   │  StableClaw AI Gateway               │  │   │
│  │   │  http://localhost:18789              │  │   │
│  │   │  ← Node WS: 15 device commands      │  │   │
│  │   └─────────────────────────────────────┘  │   │
│  │   Optional: Go, Homebrew                   │   │
│  └────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────┘
```

---

## Author

**ctz168**

- GitHub: [@ctz168](https://github.com/ctz168)

---

## License

MIT License - see [LICENSE](LICENSE) file for details.
