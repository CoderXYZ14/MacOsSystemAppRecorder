#!/bin/bash

set -e  # Exit on any error

echo "Building macOS System Audio Recorder..."

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Warning: This application is designed for macOS only."
fi

# Build Swift binary with required frameworks
echo "Building Swift binary..."
cd native

# Compile with all required frameworks for macOS
swiftc SystemAudioRecorder.swift \
    -framework AVFoundation \
    -framework ScreenCaptureKit \
    -framework CoreAudio \
    -framework CoreMedia \
    -target x86_64-apple-macos12.0 \
    -parse-as-library \
    -o SystemAudioRecorder

# Make it executable
chmod +x SystemAudioRecorder

echo "Swift binary built successfully!"

# Return to root directory
cd ..

# Install dependencies
echo "Installing npm dependencies..."
npm install

# Build Electron app
echo "Building Electron app..."
npm run build

echo "Build completed successfully!"
echo ""
echo "To run the app:"
echo "  npm start"
echo ""
echo "Note: Make sure to grant Screen Recording and Microphone permissions in System Settings > Privacy & Security"