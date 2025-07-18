# macOS System Audio Recorder

A cross-platform Electron application with a Swift native bridge for recording system audio only (no microphone) on macOS.

## Features

- **System Audio Only**: Records internal system audio without capturing microphone input
- **Modern macOS Support**: Uses ScreenCaptureKit for macOS 13+ and falls back to AVFoundation for older versions
- **Electron Integration**: Clean UI with real-time recording status and logging
- **Permission Management**: Automatic permission checking and user guidance
- **High Quality**: Records in 48kHz stereo WAV format

## System Requirements

- macOS 10.15+ (macOS 13+ recommended for best performance)
- Node.js 16+
- Xcode Command Line Tools

## Installation & Build

1. **Clone the repository**

   ```bash
   git clone <repository-url>
   cd macos-system-audio-recorder
   ```

2. **Build the application**

   ```bash
   chmod +x build.sh
   ./build.sh
   ```

3. **Run the application**
   ```bash
   npm start
   ```

## Architecture

### High-Level System Design

```
┌─────────────────┐    IPC     ┌──────────────────┐    spawn    ┌─────────────────┐
│   Renderer      │◄─────────►│  Main Process    │◄──────────►│  Swift Binary   │
│   (UI/HTML)     │            │  (Electron)      │             │  (Native Audio) │
└─────────────────┘            └──────────────────┘             └─────────────────┘
       │                              │                                │
       ▼                              ▼                                ▼
  User Interface              Process Management              System Audio Capture
  - Start/Stop                - Binary Path Resolution        - ScreenCaptureKit (macOS 13+)
  - Status Display            - Output Path Management        - AVFoundation (Legacy)
  - Permission Check          - Error Handling                - WAV File Writing
```

### Component Breakdown

#### 1. Electron Main Process (`src/main/main.js`)

- Manages the Swift binary lifecycle
- Handles IPC communication with renderer
- Resolves binary paths for dev vs. packaged app
- Manages recording state and output paths

#### 2. Swift Native Bridge (`native/SystemAudioRecorder.swift`)

**Modern Implementation (macOS 13+):**

- Uses `ScreenCaptureKit` for system audio capture
- Configures audio-only stream with `excludesCurrentProcessAudio`
- Supports 48kHz stereo recording

**Legacy Implementation (macOS 12 and below):**

- Uses `AVFoundation` with `AVAudioEngine`
- Configures audio session for system audio capture
- Fallback for older macOS versions

#### 3. Renderer Process (`src/renderer/index.html`)

- Modern UI with recording status indicators
- Real-time logging and error display
- Permission management interface
- File output path display

## Usage

1. **Check Permissions**: Click "Check Permissions" to verify required access
2. **Grant Permissions**: If needed, enable in System Settings:
   - **Screen Recording** (macOS 13+)
   - **Microphone** (fallback for older systems)
3. **Start Recording**: Click "Start Recording" to begin capturing system audio
4. **Play Audio**: Open any application (YouTube, Spotify, etc.) to record its audio
5. **Stop Recording**: Click "Stop Recording" to save the file
6. **Access Files**: Recordings are saved to your home directory with timestamps

## Technical Implementation

### System Audio Capture Methods

**ScreenCaptureKit (Preferred - macOS 13+):**

```swift
let config = SCStreamConfiguration()
config.capturesAudio = true
config.excludesCurrentProcessAudio = true
config.sampleRate = 48000
config.channelCount = 2
```

**AVFoundation (Legacy):**

```swift
let audioEngine = AVAudioEngine()
let inputNode = audioEngine.inputNode
// Configure for system audio capture
```

### IPC Communication

The Electron app communicates with the Swift binary through:

- **Process spawning**: `child_process.spawn()`
- **Signal handling**: SIGINT for graceful shutdown
- **Output streaming**: Real-time stdout/stderr capture

### File Output

- **Format**: WAV (Linear PCM)
- **Sample Rate**: 48kHz
- **Channels**: Stereo (2)
- **Bit Depth**: 16-bit
- **Location**: `~/system_audio_TIMESTAMP.wav`

## Permissions Required

### macOS 13+ (Ventura and later)

- **Screen Recording**: Required for ScreenCaptureKit audio capture

### macOS 12 and earlier

- **Microphone**: Required for AVFoundation audio input access

### How to Grant Permissions

1. Open **System Settings** (or System Preferences)
2. Go to **Privacy & Security**
3. Select **Screen Recording** and/or **Microphone**
4. Enable access for your application

## Troubleshooting

### Common Issues

1. **"Permission Denied" Error**

   - Grant Screen Recording and Microphone permissions
   - Restart the application after granting permissions

2. **"Binary Not Found" Error**

   - Run `npm run build:swift` to compile the Swift binary
   - Ensure Xcode Command Line Tools are installed

3. **No Audio Recorded**

   - Verify system audio is playing during recording
   - Check that the output file exists and has content
   - Ensure proper permissions are granted

4. **"getHomeDir is not a function" Error**
   - This was a bug in the preload script - now fixed
   - Make sure you're using the updated code

### Development

**Run in development mode:**

```bash
npm run dev
```

**Build Swift binary only:**

```bash
npm run build:swift
```

**Build packaged app:**

```bash
npm run build
```

## Security Considerations

- The app only captures system audio output, never microphone input
- Uses `excludesCurrentProcessAudio` to prevent audio feedback loops
- Follows Electron security best practices with context isolation
- Requires explicit user permission grants

## Browser Limitations Bypass

Modern browsers cannot directly access system audio due to security restrictions. This solution bypasses these limitations by:

1. **Native Bridge**: Using Swift to access macOS audio APIs directly
2. **Process Isolation**: Running audio capture in a separate native process
3. **IPC Communication**: Coordinating between Electron and native components
4. **Permission Handling**: Properly requesting and managing system-level permissions

This approach provides full system audio recording capabilities while maintaining security and user control.
