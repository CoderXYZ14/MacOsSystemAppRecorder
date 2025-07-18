import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

@available(macOS 13.0, *)
class ModernSystemAudioRecorder: NSObject {
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    
    func start(outputPath: String) async throws {
        guard !isRecording else { return }
        
        // Get available content
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // Configure stream to capture system audio only
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        
        // Create output file
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
        
        // Create stream with display (required for audio capture)
        if let display = availableContent.displays.first {
            stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
            
            try await stream?.startCapture()
            isRecording = true
            print("Modern system audio recording started to \(outputPath)")
        } else {
            throw NSError(domain: "SystemAudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "No display found for audio capture"])
        }
    }
    
    func stop() async {
        guard isRecording else { return }
        
        if let stream = stream {
            try? await stream.stopCapture()
        }
        
        audioFile = nil
        isRecording = false
        print("Modern system audio recording stopped")
    }
}

@available(macOS 13.0, *)
extension ModernSystemAudioRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let audioFile = audioFile else { return }
        
        // Convert CMSampleBuffer to AVAudioPCMBuffer and write to file
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        guard let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else { return }
        
        let avAudioFormat = AVAudioFormat(streamDescription: audioStreamBasicDescription)
        
        guard let format = avAudioFormat,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))) else { return }
        
        // Copy audio data from CMSampleBuffer to AVAudioPCMBuffer
        var blockBuffer: CMBlockBuffer?
        var audioBufferListOut: AudioBufferList = AudioBufferList()
        var bufferListSize: Int = 0
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: &audioBufferListOut,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        if status == noErr {
            pcmBuffer.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
            try? audioFile.write(from: pcmBuffer)
        }
    }
}

// Legacy recorder for older macOS versions
class LegacySystemAudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    
    func start(outputPath: String) throws {
        guard !isRecording else { return }
        
        print("Attempting legacy audio recording (no Screen Recording permission needed)")
        
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine!.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        print("Input format: \(inputFormat)")
        
        let outputURL = URL(fileURLWithPath: outputPath)
        audioFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }
        
        try audioEngine!.start()
        isRecording = true
        
        print("Legacy system audio recording started to \(outputPath)")
    }
    
    func stop() {
        guard isRecording else { return }
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioFile = nil
        isRecording = false
        
        print("Legacy system audio recording stopped")
    }
}

// Main recorder class that chooses the appropriate implementation
class SystemAudioRecorder {
    private var modernRecorder: Any?
    private var legacyRecorder: LegacySystemAudioRecorder?
    private let useModern: Bool
    
    init() {
        // Force legacy mode for MacinCloud compatibility
        print("Forcing legacy mode for compatibility with cloud Mac services")
        useModern = false
        legacyRecorder = LegacySystemAudioRecorder()
        
        // Original logic (commented out):
        // if #available(macOS 13.0, *) {
        //     useModern = true
        //     modernRecorder = ModernSystemAudioRecorder()
        // } else {
        //     useModern = false
        //     legacyRecorder = LegacySystemAudioRecorder()
        // }
    }
    
    func start(outputPath: String) async throws {
        if useModern {
            if #available(macOS 13.0, *) {
                try await (modernRecorder as! ModernSystemAudioRecorder).start(outputPath: outputPath)
            }
        } else {
            try legacyRecorder?.start(outputPath: outputPath)
        }
    }
    
    func stop() async {
        if useModern {
            if #available(macOS 13.0, *) {
                await (modernRecorder as! ModernSystemAudioRecorder).stop()
            }
        } else {
            legacyRecorder?.stop()
        }
    }
}

// Command-line entry point
@main
struct SystemAudioRecorderApp {
    static func main() async {
        let recorder = SystemAudioRecorder()
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
            print("Recording started. Press Ctrl+C to stop.")
            
            // Keep the process alive using async-friendly approach
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Never resume the continuation - this keeps the process alive
                // The process will exit via the signal handler
            }
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }
}