import AVFoundation
import Foundation

/// 녹음기 (테스트에서는 가짜로 바꾼다). Core 의 녹음 기록(Recording)과 이름이 겹치지 않게 AudioRecording
@MainActor
protocol AudioRecording: AnyObject {
    /// url 에 녹음을 시작한다. 시작하지 못하면 던진다
    func start(to url: URL) throws
    /// 녹음을 끝내고 길이(초)를 돌려준다
    func stop() -> Double
}

/// AVAudioRecorder: AAC, 44.1kHz, 모노, 64kbps (1시간에 약 28MB).
/// 7일 뒤 지울 임시 파일이라 10/10 측정에서 가장 정확했던 형식을 쓴다
final class VoiceRecorder: AudioRecording {
    private var recorder: AVAudioRecorder?

    func start(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
        self.recorder = recorder
    }

    func stop() -> Double {
        guard let recorder else { return 0 }
        let seconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        return seconds
    }
}

enum AudioFileInfo {
    /// 읽히는 녹음 파일이면 길이(초). 녹음 중 앱이 꺼져 마무리되지 않은 파일이면 nil
    static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        guard rate > 0, file.length > 0 else { return nil }
        return Double(file.length) / rate
    }
}
