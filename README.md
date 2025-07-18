# macOS System Audio Recorder

A simple Electron app that records system audio on macOS using a Swift native bridge.

## 🚀 Quick Start

### Prerequisites

- macOS 10.15+ (Catalina or later)
- Node.js 16+ installed
- Xcode Command Line Tools

### Installation & Setup

1. **Clone or download the project**

   ```bash
   cd macos-system-audio-recorder
   ```

2. **Build the Swift binary**

   ```bash
   npm run build:swift
   ```

   _Or use the build script:_

   ```bash
   chmod +x build.sh
   ./build.sh
   ```

3. **Install dependencies**

   ```bash
   npm install
   ```

4. **Run the app**
   ```bash
   npm start
   ```

## 🎵 How to Use

1. **Launch the app** with `npm start`
2. **Click "Check Permissions"** - Should show ✅ if everything is ready
3. **Click "Start Recording"** - Recording begins immediately
4. **Play any audio** - YouTube, Spotify, games, system sounds, etc.
5. **Click "Stop Recording"** - Audio file is saved to your home directory

## 📁 Output Files

Recordings are saved as:

```
~/system_audio_YYYY-MM-DD-HH-MM-SS.wav
```

Example: `~/system_audio_2025-07-18T16-04-33.wav`

## 🔧 Troubleshooting

### "Audio recorder failed to start"

- **Grant Microphone permission** in System Settings → Privacy & Security → Microphone
- **Add Terminal or your app** to the allowed list
- **Restart the app** after granting permissions

### "Permission denied" errors

- Make sure you have **Microphone access** enabled
- For macOS 13+, you might also need **Screen Recording** permission

### "Binary not found" error

- Run `npm run build:swift` to compile the Swift binary
- Make sure Xcode Command Line Tools are installed: `xcode-select --install`

## 🛠️ Development

### Build Swift binary only

```bash
npm run build:swift
```

### Run in development mode

```bash
npm run dev
```

### Test Swift binary directly

```bash
./native/SystemAudioRecorder /tmp/test_audio.wav
```

_Press Ctrl+C to stop_

## 💡 How It Works

1. **Electron frontend** provides the user interface
2. **Swift binary** handles actual audio recording using AVFoundation
3. **IPC communication** coordinates between Electron and Swift
4. **Legacy mode** ensures compatibility with cloud Mac services

## 📋 System Requirements

- **macOS 10.15+** (Catalina or newer)
- **Node.js 16+**
- **Microphone permission** (required for audio input access)
- **Screen Recording permission** (for advanced features on macOS 13+)

## 🎯 Features

- ✅ Records system audio only (no microphone input)
- ✅ High-quality WAV output (48kHz stereo)
- ✅ Simple one-click recording
- ✅ Works on cloud Mac services (MacinCloud, etc.)
- ✅ Automatic file naming with timestamps
- ✅ Real-time recording status and logs

---

**Quick Commands:**

```bash
# Full setup and run
npm run build:swift && npm install && npm start

# Just run (if already built)
npm start
```
