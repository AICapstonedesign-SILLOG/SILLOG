import Foundation
import Speech
import WorkGraphCore

/// 기기 안 음성 인식(ko-KR)으로 녹음 파일 하나를 한 번에 받아쓴다.
/// 10/10 측정: 기기 안 인식에는 1분 제한이 없고(8분 17초를 한 요청으로), 결과는 발화마다 나뉘어 마지막 결과에는 마지막 발화만 남는다.
/// 그래서 중간 결과를 켜고, 발화 끝 표시(speechRecognitionMetadata)가 붙은 결과를 TranscriptCollector 로 모은다
struct SpeechTranscriber: Transcribing {
    /// 인식 오류의 뜻
    enum ErrorKind: Equatable {
        /// 시스템 설정 → 키보드 → 받아쓰기가 꺼짐 (kLSRErrorDomain 201)
        case dictationOff
        /// 말소리가 없음 (kAFAssistantErrorDomain 1110): 받아쓴 글 없이 끝낸다
        case noSpeech
        case other
    }

    static func kind(of error: Error) -> ErrorKind {
        let error = error as NSError
        if error.domain == "kLSRErrorDomain", error.code == 201 { return .dictationOff }
        if error.domain == "kAFAssistantErrorDomain", error.code == 1110 { return .noSpeech }
        return .other
    }

    func transcribe(audio: URL, duration: Double, progress: @escaping @Sendable (Double) -> Void) async throws -> [String] {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw TranscriptionError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")), recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.unavailable("이 Mac 에서는 한국어를 기기 안에서 받아쓸 수 없어요")
        }
        let request = SFSpeechURLRecognitionRequest(url: audio)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        let session = RecognitionSession(duration: duration, progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
                session.begin(continuation) {
                    recognizer.recognitionTask(with: request) { result, error in session.receive(result, error, recognizer: recognizer) }
                }
            }
        } onCancel: {
            session.cancel()
        }
    }
}

/// 인식 한 번의 상태. 인식기 콜백과 취소가 겹쳐도 continuation 은 한 번만 이어진다
private final class RecognitionSession: @unchecked Sendable {
    private let lock = NSLock()
    private var collector: TranscriptCollector
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<[String], Error>?
    private var task: SFSpeechRecognitionTask?
    private var cancelled = false

    init(duration: Double, progress: @escaping @Sendable (Double) -> Void) {
        collector = TranscriptCollector(duration: duration)
        self.progress = progress
    }

    func begin(_ continuation: CheckedContinuation<[String], Error>, start: () -> SFSpeechRecognitionTask) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
        let task = start()
        lock.lock()
        self.task = task
        lock.unlock()
    }

    /// recognizer 는 인식이 끝날 때까지 붙잡아 두려고 받는다
    func receive(_ result: SFSpeechRecognitionResult?, _ error: Error?, recognizer: SFSpeechRecognizer) {
        lock.lock()
        guard continuation != nil else { lock.unlock(); return }
        var outcome: Result<[String], Error>?
        if let result {
            let segments = result.bestTranscription.segments
            var end = segments.last.map { $0.timestamp + $0.duration } ?? 0
            if let metadata = result.speechRecognitionMetadata { end = max(end, metadata.speechStartTimestamp + metadata.speechDuration) }
            collector.add(text: result.bestTranscription.formattedString, utteranceEnded: result.speechRecognitionMetadata != nil,
                          isFinal: result.isFinal, lastWordEnd: end)
            if result.isFinal { outcome = .success(collector.finish()) }
        }
        if outcome == nil, let error {
            switch SpeechTranscriber.kind(of: error) {
            case .dictationOff: outcome = .failure(TranscriptionError.dictationDisabled)
            case .noSpeech: outcome = .success(collector.finish())
            case .other: outcome = .failure(TranscriptionError.failed(error.localizedDescription))
            }
        }
        let value = collector.progress
        let waiting = outcome == nil ? nil : continuation
        if outcome != nil { continuation = nil; task = nil }
        lock.unlock()
        progress(value)
        if let waiting, let outcome { waiting.resume(with: outcome) }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task, waiting = continuation
        continuation = nil
        lock.unlock()
        task?.cancel()
        waiting?.resume(throwing: CancellationError())
    }
}
