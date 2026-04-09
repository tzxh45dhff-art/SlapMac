# 👋 SlapMac

**SlapMac** is a fun macOS utility app that utilizes your MacBook's built-in accelerometer to detect physical slaps on the device and plays a dynamic sound effect based on the slap's intensity! It runs quietly in your menu bar and allows you to adjust the sensitivity threshold and sound repetition cooldown.

## Features
- **Accelerometer Integration**: Detects physical slaps on your Mac in real-time.
- **Dynamic Audio**: The sound intensity and effect scales with the strength of the slap.
- **Customizable**: Adjust the slap sensitivity threshold and cooldown right from the interface.
- **Menu Bar Ready**: SlapMac lives right in your menu bar and keeps track of your total slap count.
- **Auto-Updates**: Built-in Sparkle integration ensures you receive new updates automatically.

## 📥 Installation

1. Navigate to the [Releases page](https://github.com/tzxh45dhff-art/SlapMac/releases/latest).
2. Download the latest `SlapMac-x.x.x.dmg` file.
3. Open the `.dmg` file and drag **SlapMac.app** into your `Applications` folder.
4. **Note for macOS Gatekeeper**: Because this app is independently developed and not notarized through the Mac App Store, macOS may warn you on the first launch. To open it initially:
   - Go to your `Applications` folder.
   - **Right-click** (or Control-click) on `SlapMac.app` and choose **Open**.
   - Click **Open** in the confirmation dialog.

## 🛠 Building from Source

### Prerequisites
- macOS 13.0 or later
- Xcode 16.0 or later
- Homebrew (for the GitHub CLI if you plan to use release scripts)

### Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/tzxh45dhff-art/SlapMac.git
   cd SlapMac
   ```
2. Open `SlapMac/SlapMac.xcodeproj` in Xcode.
3. The project utilizes **Sparkle** (installed via Swift Package Manager) for auto-updates. Xcode should automatically resolve this dependency.
4. Build and run the `SlapMac` target.

### Releasing a new version
This repository contains a handy automated build script inside the `/scripts` directory.

```bash
# Update the version label in Xcode first, then run:
./scripts/build-release.sh 1.0.2
```

## 📜 License
Distributed under the MIT License. See `LICENSE` for more information.
