#!/bin/bash

# Build Swift binary
echo "Building Swift binary..."
swiftc ./native/SystemAudioRecorder.swift -o ./native/SystemAudioRecorder

# Make it executable
chmod +x ./native/SystemAudioRecorder

# Build Electron app
echo "Building Electron app..."
npm install
npm run build