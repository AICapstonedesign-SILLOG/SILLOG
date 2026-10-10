import AVFoundation
import AppKit
import XCTest
@testable import WorkGraphApp
@testable import WorkGraphCore

/// 녹음기 대신: 파일 자리에 가짜 바이트를 쓰고, 끝내면 정해진 길이를 돌려준다
@MainActor
final class FakeRecorder: AudioRecording {
    let seconds: Double
    private(set) var startedURL: URL?
    private(set) var stopped = false
    init(seconds: Double) { self.seconds = seconds }

    func start(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake audio".utf8).write(to: url)
        startedURL = url
    }

    func stop() -> Double { stopped = true; return seconds }
}

@MainActor
struct FakePermissions: RecordingPermissions {
    let problem: RecordingProblem?
    func check() async -> RecordingProblem? { problem }
}

/// 순서대로 결과를 돌려주는 가짜 받아쓰기 (마지막 결과는 계속 쓴다)
final class FakeTranscriber: Transcribing, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<[String], TranscriptionError>]
    init(_ results: Result<[String], TranscriptionError>...) { self.results = results }

    func transcribe(audio: URL, duration: Double, progress: @escaping @Sendable (Double) -> Void) async throws -> [String] {
        let next: Result<[String], TranscriptionError> = lock.withLock { results.count > 1 ? results.removeFirst() : results[0] }
        progress(0.5)
        return try next.get()
    }
}

/// 제목만 지어 주는 가짜 빠른 모델
struct NamingLLM: LLMClient {
    let modelName = "naming-stub"
    func callFunction(system: String, user: String, tool: ToolSpec) async throws -> LLMResult {
        let json = #"{"title":"자료구조 3주차 강의","summary":"연결 리스트를 설명한 강의."}"#
        return LLMResult(arguments: Data(json.utf8), model: modelName, promptTokens: 1, completionTokens: 1, raw: json)
    }
}

/// 메뉴 막대 녹음: 시작 → 끝 → 받아쓰기 → 제목·.md, 그리고 권한·받아쓰기 꺼짐·이어 하기·종료
@MainActor
final class RecordingFlowTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        _ = NSApplication.shared                                            // 파일 제안 새로 고침이 Dock 배지를 건드린다
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("wg-recording-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func makeState(transcriber: FakeTranscriber = FakeTranscriber(.success(["첫 문장입니다.", "둘째 문장입니다."])),
                           problem: RecordingProblem? = nil) throws -> (AppState, WGDatabase, FakeRecorder) {
        let db = try WGDatabase.inMemory()
        addTeardownBlock { try? FileManager.default.removeItem(at: db.recordingsDirectory) }
        let recorder = FakeRecorder(seconds: 95)
        let textFolder = folder.appendingPathComponent("Sillog 녹음")
        let state = AppState(preview: { s in
            s.phase = .ready
            s.recorder = recorder
            s.recordingPermissions = FakePermissions(problem: problem)
            s.recordingPipeline = RecordingPipeline(db: db, transcriber: transcriber, llm: NamingLLM(), textFolder: textFolder)
        }, database: db)
        return (state, db, recorder)
    }

    static func writeSilence(to url: URL, seconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let frames = AVAudioFrameCount(16_000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    func testStartAndStopTranscribesNamesAndSavesTheText() async throws {
        let (state, db, recorder) = try makeState()
        await state.startRecording()
        let active = try XCTUnwrap(state.activeRecording)
        XCTAssertEqual(recorder.startedURL?.lastPathComponent, "\(active.id).m4a")
        XCTAssertEqual(recorder.startedURL?.deletingLastPathComponent().path, db.recordingsDirectory.path)
        XCTAssertEqual(try RecordingStore(db).find(id: active.id)?.status, .recording)

        await state.stopRecording()
        XCTAssertNil(state.activeRecording)
        XCTAssertNil(state.recordingWork)
        XCTAssertNil(state.recordingProblem)
        let saved = try XCTUnwrap(RecordingStore(db).find(id: active.id))
        XCTAssertEqual(saved.status, .ready)
        XCTAssertEqual(saved.duration, 95)
        XCTAssertEqual(saved.title, "자료구조 3주차 강의")
        let text = try String(contentsOfFile: try XCTUnwrap(saved.textPath), encoding: .utf8)
        XCTAssertTrue(text.contains("첫 문장입니다.\n\n둘째 문장입니다."))
        XCTAssertEqual(state.recordings.map(\.id), [active.id])
    }

    func testMicrophoneOffShowsTheProblemAndRecordsNothing() async throws {
        let (state, db, recorder) = try makeState(problem: .microphone)
        await state.startRecording()
        XCTAssertNil(state.activeRecording)
        XCTAssertNil(recorder.startedURL)
        XCTAssertEqual(state.recordingProblem, .microphone)
        XCTAssertTrue(try RecordingStore(db).all().isEmpty)
    }

    func testWithoutUsageStringsItRefusesBeforeAskingTheSystem() async {
        // 테스트 실행 파일에는 마이크·음성 인식 사용 문구가 없다 (swift run 과 같은 상황). 시스템에 묻기 전에 멈춰야 한다
        let problem = await SystemRecordingPermissions().check()
        XCTAssertEqual(problem, .notBundled)
    }

    func testDictationOffFailsKeepsTheAudioAndRetranscribeFinishes() async throws {
        let (state, db, _) = try makeState(transcriber: FakeTranscriber(.failure(.dictationDisabled), .success(["다시 받아쓴 문장."])))
        await state.startRecording()
        await state.stopRecording()
        XCTAssertEqual(state.recordingProblem, .dictation)
        let failed = try XCTUnwrap(RecordingStore(db).all().first)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.audioPath), "실패한 녹음은 다시 받아쓸 수 있게 남긴다")

        await state.retranscribe(failed)
        XCTAssertNil(state.recordingProblem)
        let ready = try XCTUnwrap(RecordingStore(db).find(id: failed.id!))
        XCTAssertEqual(ready.status, .ready)
        XCTAssertEqual(ready.transcript, "다시 받아쓴 문장.")
    }

    func testUnfinishedRecordingsResumeOrFailOnLaunch() async throws {
        let (state, db, _) = try makeState()
        let store = RecordingStore(db)
        let audio = folder.appendingPathComponent("pending.m4a")
        try Data("audio".utf8).write(to: audio)
        let pending = try store.insert(Recording(startedAt: 1_000, endedAt: 1_095, duration: 95, audioPath: audio.path, status: .transcribing))
        let readable = folder.appendingPathComponent("crash-ok.caf")
        try Self.writeSilence(to: readable, seconds: 2)
        let survived = try store.insert(Recording(startedAt: 2_000, audioPath: readable.path, status: .recording))
        let broken = folder.appendingPathComponent("crash-broken.m4a")
        try Data("not audio".utf8).write(to: broken)
        let lost = try store.insert(Recording(startedAt: 3_000, audioPath: broken.path, status: .recording))

        await state.resumeRecordings()
        XCTAssertEqual(try store.find(id: pending.id!)?.status, .ready)
        let resumed = try XCTUnwrap(store.find(id: survived.id!))
        XCTAssertEqual(resumed.status, .ready)
        XCTAssertEqual(resumed.duration, 2, accuracy: 0.05)
        let failed = try XCTUnwrap(store.find(id: lost.id!))
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.error, AppState.crashedRecordingMessage)
    }

    func testQuittingWhileRecordingClosesTheFileForTheNextLaunch() async throws {
        let (state, db, recorder) = try makeState()
        await state.startRecording()
        let id = try XCTUnwrap(state.activeRecording?.id)
        state.finishRecordingOnQuit()
        XCTAssertTrue(recorder.stopped)
        XCTAssertNil(state.activeRecording)
        let saved = try XCTUnwrap(RecordingStore(db).find(id: id))
        XCTAssertEqual(saved.status, .transcribing, "다음 실행 때 받아쓰기부터 이어 간다")
        XCTAssertEqual(saved.duration, 95)
        XCTAssertNotNil(saved.endedAt)
    }

    func testLateProgressFromAFinishedRunIsIgnored() async throws {
        let (state, _, _) = try makeState()
        await state.startRecording()
        await state.stopRecording()
        XCTAssertNil(state.recordingWork)
        state.applyRecordingStep(.naming, token: state.recordingStepToken - 1)
        XCTAssertNil(state.recordingWork, "끝난 정리의 늦은 단계 알림은 버린다")
    }

    func testANewRecordingCanStartWhileTheLastIsStillBeingProcessed() async throws {
        let (state, _, recorder) = try makeState()
        state.recordingWork = .transcribing(0.4)
        await state.startRecording()
        XCTAssertNotNil(state.activeRecording)
        XCTAssertNotNil(recorder.startedURL)
    }

    func testSpeechErrorsAreSortedIntoDictationOffNoSpeechAndOther() {
        XCTAssertEqual(SpeechTranscriber.kind(of: NSError(domain: "kLSRErrorDomain", code: 201)), .dictationOff)
        XCTAssertEqual(SpeechTranscriber.kind(of: NSError(domain: "kAFAssistantErrorDomain", code: 1110)), .noSpeech)
        XCTAssertEqual(SpeechTranscriber.kind(of: NSError(domain: "kLSRErrorDomain", code: 300)), .other)
    }

    func testEachProblemSaysWhatIsOffAndOpensTheRightSettings() {
        XCTAssertEqual(RecordingProblem.microphone.text, "마이크 권한이 꺼져 있어요")
        XCTAssertEqual(RecordingProblem.microphone.settingsURL?.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        XCTAssertEqual(RecordingProblem.speech.settingsURL?.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        XCTAssertEqual(RecordingProblem.dictation.text, "받아쓰기가 꺼져 있어요")
        XCTAssertEqual(RecordingProblem.dictation.settingsURL?.absoluteString, "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        XCTAssertNil(RecordingProblem.notBundled.settingsURL)
        XCTAssertEqual(RecordingProblem(TranscriptionError.dictationDisabled), .dictation)
        XCTAssertEqual(RecordingProblem(TranscriptionError.speechDenied), .speech)
    }
}
