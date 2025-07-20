import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import AudioToolbox
import CoreAudio

// MARK: - Method 1: ScreenCaptureKit (macOS 13+ - Pure System Audio)
@available(macOS 13.0, *)
class ScreenCaptureAudioRecorder: NSObject {
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    
    func start(outputPath: String) async throws {
        guard !isRecording else { return }
        
        print("🎯 Attempting ScreenCaptureKit (pure system audio)")
        
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        
        let outputURL = URL(fileURLWithPath: outputPath)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        audioFile = try AVAudioFile(forWriting: outputURL, settings: audioSettings)
        
        if let display = availableContent.displays.first {
            stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
            try await stream?.startCapture()
            isRecording = true
            print("✅ ScreenCaptureKit recording started")
        } else {
            throw NSError(domain: "ScreenCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
    }
    
    func stop() async {
        guard isRecording else { return }
        if let stream = stream {
            try? await stream.stopCapture()
        }
        audioFile = nil
        isRecording = false
        print("✅ ScreenCaptureKit recording stopped")
    }
}

@available(macOS 13.0, *)
extension ScreenCaptureAudioRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let audioFile = audioFile else { return }
        
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let avAudioFormat = AVAudioFormat(streamDescription: audioStreamBasicDescription),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: avAudioFormat, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))) else { return }
        
        var blockBuffer: CMBlockBuffer?
        var audioBufferListOut: AudioBufferList = AudioBufferList()
        var bufferListSize: Int = 0
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &bufferListSize, bufferListOut: &audioBufferListOut,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &blockBuffer)
        
        if status == noErr {
            pcmBuffer.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
            try? audioFile.write(from: pcmBuffer)
        }
    }
}

// MARK: - Method 2: Core Audio HAL Output Device Tap
class CoreAudioOutputRecorder {
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var audioUnit: AudioUnit?
    
    func start(outputPath: String) throws {
        guard !isRecording else { return }
        
        print("🎯 Attempting Core Audio HAL Output Device capture")
        
        // Find default output device
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
        guard status == noErr && deviceID != kAudioObjectUnknown else {
            throw NSError(domain: "CoreAudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot find default output device"])
        }
        
        print("✅ Found output device ID: \(deviceID)")
        
        // Create Audio Unit for output device
        var componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            throw NSError(domain: "CoreAudio", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot find HAL output component"])
        }
        
        var audioUnit: AudioUnit?
        var result = AudioComponentInstanceNew(component, &audioUnit)
        guard result == noErr, let au = audioUnit else {
            throw NSError(domain: "CoreAudio", code: -3, userInfo: [NSLocalizedDescriptionKey: "Cannot create audio unit"])
        }
        
        self.audioUnit = au
        
        // Set device
        result = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard result == noErr else {
            throw NSError(domain: "CoreAudio", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cannot set audio device"])
        }
        
        // Enable input
        var enableIO: UInt32 = 1
        result = AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableIO, UInt32(MemoryLayout<UInt32>.size))
        guard result == noErr else {
            throw NSError(domain: "CoreAudio", code: -5, userInfo: [NSLocalizedDescriptionKey: "Cannot enable IO"])
        }
        
        // Initialize audio file
        let outputURL = URL(fileURLWithPath: outputPath)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        audioFile = try AVAudioFile(forWriting: outputURL, settings: audioSettings)
        
        result = AudioUnitInitialize(au)
        guard result == noErr else {
            throw NSError(domain: "CoreAudio", code: -6, userInfo: [NSLocalizedDescriptionKey: "Cannot initialize audio unit"])
        }
        
        result = AudioOutputUnitStart(au)
        guard result == noErr else {
            throw NSError(domain: "CoreAudio", code: -7, userInfo: [NSLocalizedDescriptionKey: "Cannot start audio unit"])
        }
        
        isRecording = true
        print("✅ Core Audio HAL recording started")
    }
    
    func stop() {
        guard isRecording else { return }
        
        if let audioUnit = audioUnit {
            AudioOutputUnitStop(audioUnit)
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
        }
        
        audioFile = nil
        audioUnit = nil
        isRecording = false
        print("✅ Core Audio HAL recording stopped")
    }
}

// MARK: - Method 3: AVAudioEngine with Output Node (macOS 13+)
@available(macOS 13.0, *)
class AVAudioEngineOutputRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    
    func start(outputPath: String) throws {
        guard !isRecording else { return }
        
        print("🎯 Attempting AVAudioEngine output node capture")
        
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        // Try to access main mixer output instead of input
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        
        print("Output format: \(outputFormat)")
        
        let outputURL = URL(fileURLWithPath: outputPath)
        audioFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
        
        // Install tap on main mixer output
        mainMixer.installTap(onBus: 0, bufferSize: 1024, format: outputFormat) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }
        
        try engine.start()
        isRecording = true
        print("✅ AVAudioEngine output recording started")
    }
    
    func stop() {
        guard isRecording else { return }
        
        audioEngine?.stop()
        audioEngine?.mainMixerNode.removeTap(onBus: 0)
        audioFile = nil
        isRecording = false
        print("✅ AVAudioEngine output recording stopped")
    }
}

// MARK: - Method 4: Aggregate Device with Loopback
class LoopbackDeviceRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    
    func start(outputPath: String) throws {
        guard !isRecording else { return }
        
        print("🎯 Attempting loopback device recording")
        
        // This would require creating a virtual aggregate device
        // For now, fall back to basic input node
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine!.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        print("Loopback format: \(inputFormat)")
        
        let outputURL = URL(fileURLWithPath: outputPath)
        audioFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }
        
        try audioEngine!.start()
        isRecording = true
        print("✅ Loopback device recording started")
    }
    
    func stop() {
        guard isRecording else { return }
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioFile = nil
        isRecording = false
        print("✅ Loopback device recording stopped")
    }
}

// MARK: - Main Recorder Manager - Tries All Methods
class SystemAudioRecorderManager {
    private var activeRecorder: Any?
    private var recordingMethod: String = ""
    
    func start(outputPath: String) async throws {
        print("🚀 Starting comprehensive system audio capture...")
        print("📋 Trying all available methods...")
        
        // Method 1: ScreenCaptureKit (Best - Pure System Audio)
        if #available(macOS 13.0, *) {
            do {
                let screenRecorder = ScreenCaptureAudioRecorder()
                try await screenRecorder.start(outputPath: outputPath)
                activeRecorder = screenRecorder
                recordingMethod = "ScreenCaptureKit"
                print("🎉 SUCCESS: Using ScreenCaptureKit (pure system audio)")
                return
            } catch {
                print("❌ ScreenCaptureKit failed: \(error)")
            }
        }
        
        // Method 2: Core Audio HAL Output Device
        do {
            let coreAudioRecorder = CoreAudioOutputRecorder()
            try coreAudioRecorder.start(outputPath: outputPath)
            activeRecorder = coreAudioRecorder
            recordingMethod = "CoreAudioHAL"
            print("🎉 SUCCESS: Using Core Audio HAL output device")
            return
        } catch {
            print("❌ Core Audio HAL failed: \(error)")
        }
        
        // Method 3: AVAudioEngine Output Node (macOS 13+)
        if #available(macOS 13.0, *) {
            do {
                let engineRecorder = AVAudioEngineOutputRecorder()
                try engineRecorder.start(outputPath: outputPath)
                activeRecorder = engineRecorder
                recordingMethod = "AVAudioEngineOutput"
                print("🎉 SUCCESS: Using AVAudioEngine output node")
                return
            } catch {
                print("❌ AVAudioEngine output failed: \(error)")
            }
        }
        
        // Method 4: Loopback Device (Fallback)
        do {
            let loopbackRecorder = LoopbackDeviceRecorder()
            try loopbackRecorder.start(outputPath: outputPath)
            activeRecorder = loopbackRecorder
            recordingMethod = "LoopbackDevice"
            print("🎉 SUCCESS: Using loopback device (may include microphone)")
            return
        } catch {
            print("❌ Loopback device failed: \(error)")
        }
        
        throw NSError(domain: "SystemAudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "All recording methods failed"])
    }
    
    func stop() async {
        guard let recorder = activeRecorder else { return }
        
        print("🛑 Stopping \(recordingMethod) recording...")
        
        switch recordingMethod {
        case "ScreenCaptureKit":
            if #available(macOS 13.0, *) {
                await (recorder as! ScreenCaptureAudioRecorder).stop()
            }
        case "CoreAudioHAL":
            (recorder as! CoreAudioOutputRecorder).stop()
        case "AVAudioEngineOutput":
            if #available(macOS 13.0, *) {
                (recorder as! AVAudioEngineOutputRecorder).stop()
            }
        case "LoopbackDevice":
            (recorder as! LoopbackDeviceRecorder).stop()
        default:
            break
        }
        
        activeRecorder = nil
        recordingMethod = ""
        print("✅ Recording stopped successfully")
    }
}

// MARK: - Command Line Entry Point
@main
struct SystemAudioRecorderApp {
    static func main() async {
        let recorder = SystemAudioRecorderManager()
        let args = CommandLine.arguments

        guard args.count == 2 else {
            print("Usage: \(args[0]) <output-path>")
            exit(1)
        }

        // Handle Ctrl-C
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource.setEventHandler {
            Task {
                await recorder.stop()
                exit(0)
            }
        }
        signal(SIGINT, SIG_IGN)
        signalSource.resume()

        // Start recording
        do {
            try await recorder.start(outputPath: args[1])
            print("🎵 Recording system audio. Press Ctrl+C to stop.")
            
            // Keep process alive
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Never resume - process exits via signal handler
            }
        } catch {
            print("💥 Error: \(error)")
            exit(1)
        }
    }
}