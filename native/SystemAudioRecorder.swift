import Foundation
import AVFoundation
import CoreAudio

class SystemAudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    
    func start(outputPath: String) throws {
        guard !isRecording else { return }
        
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)
        
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine!.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Configure to capture system audio
        try inputNode.setVoiceProcessingEnabled(false)
        
        let outputURL = URL(fileURLWithPath: outputPath)
        audioFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }
        
        try audioEngine!.start()
        isRecording = true
        
        print("Recording started to \(outputPath)")
        
        // Keep process alive
        RunLoop.current.run()
    }
    
    func stop() {
        guard isRecording else { return }
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioFile = nil
        isRecording = false
        
        print("Recording stopped")
    }
}

@main
struct Main {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 2 else {
            print("Usage: SystemAudioRecorder <output-path>")
            exit(1)
        }
        
        let recorder = SystemAudioRecorder()
        
        // Handle SIGINT (Ctrl-C)
        signal(SIGINT, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        src.setEventHandler {
            recorder.stop()
            exit(0)
        }
        src.resume()
        
        do {
            try recorder.start(outputPath: args[1])
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }
}