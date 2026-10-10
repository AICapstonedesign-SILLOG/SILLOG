# 녹음 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 메뉴 막대에서 녹음하고, 끝내면 이 Mac 안에서 받아써 제목을 붙인 `.md`로 저장하고, 그 파일의 폴더를 추천하며, 채팅·보관함·정리(업무 연결)에서 언제든 참고할 수 있게 한다.

**Architecture:** Core에 녹음 기록(`recordings` 표 + trigram 색인)과 순수 로직(발화 모으기, 제목·파일 만들기, 정리 파이프라인)을 둔다. App은 마이크(AVAudioRecorder)·음성 인식(SFSpeechRecognizer) 같은 시스템 의존부와 화면만 맡는다. 파이프라인은 받아쓰기 → 제목 → `.md` → 폴더 추천 → ready 순서로 단계마다 DB에 남겨, 앱이 꺼졌다 켜져도 끝난 단계는 건너뛰고 이어 간다. 정리·채팅·보관함은 기존 AI 도구 대화(`chat_messages`)와 같은 방식(행 합치기, 출처 검색)으로 녹음을 받는다.

**Tech Stack:** Swift 5 모드(Swift 6.2 툴체인), SwiftUI MenuBarExtra, GRDB 7 + SQLite FTS5(trigram), AVFoundation(AVAudioRecorder·AVAudioPlayer·AVAudioFile), Speech(SFSpeechURLRecognitionRequest, 기기 안), UserNotifications, XCTest(+ Vision 글자 인식으로 화면 확인).

**Spec:** `docs/superpowers/specs/2026-10-10-voice-recording-design.md`

## Global Constraints

- macOS 14 이상(`platforms: [.macOS(.v14)]`). Swift 6.2 툴체인에서 `swift build`·`swift test`가 통과해야 한다. 긴 식은 나눠 쓰고 타입을 적는다(타입 계산 시간 초과 방지).
- 녹음 파일: `~/Library/Application Support/WorkGraph/recordings/<id>.m4a`, AAC, 44.1kHz, 모노, 64kbps.
- 받아쓰기: `SFSpeechURLRecognitionRequest` 한 번(기기 안, ko-KR, 문장부호 넣기, 중간 결과 켬). 조각으로 자르지 않는다. 발화 끝 표시(`speechRecognitionMetadata`)가 붙은 결과를 모은다. 진행률 = 마지막 단어 시각 ÷ 녹음 길이.
- 제목: 빠른 모델(`makeQuickClient`)에 받아쓴 글 앞 4,000자. 제목 20자 안팎 + 한 줄 요약. 실패하면 제목은 "녹음 2026-10-10 15-32".
- 받아쓴 글: `~/Documents/Sillog 녹음/2026-10-10 <제목>.md`. 같은 이름이 있으면 " (2)". 내용: 제목(`#`), 녹음 시각과 길이, 요약, 발화마다 한 문단.
- 폴더 추천: 기존 `FolderSuggester.suggest`에 녹음 종류 + 내용 발췌(요약 + 받아쓴 글 앞 800자). 옮기면 `recordings.text_path`를 새 경로로.
- 녹음 파일은 `ready`가 된 지 7일 지나면 지운다(앱 켤 때와 하루 한 번). `failed`는 지우지 않는다. 받아쓴 글 `.md`는 앱이 지우지 않는다.
- 1초 미만이거나 받아쓴 글이 빈 녹음: 이름·폴더 추천을 건너뛰고 정리 행에 넣지 않는다. 보관함에는 보인다.
- DB: 마이그레이션 이름 `v16-recordings`, 색인 `recordings_fts`(trigram; 제목+요약+받아쓴 글).
- 정리 행: app "녹음", appBundle `sillog.recording`, type `Recording`, uri `recording:<id>`, dwell 0. 창 끝까지 끝났고 24시간 이내이며 받아쓴 글이 있는 미처리 녹음만.
- 문구는 스펙 그대로: "녹음 중 12:31", "받아쓰는 중 37%", "녹음을 정리하는 중", "마이크 권한이 꺼져 있어요", "받아쓰기가 꺼져 있어요", "받아쓴 녹음을 정리할까요?", "녹음을 받아썼어요", "N일 뒤 지워져요", "다시 받아쓰기", "Finder에서 보기", "파일을 찾을 수 없어요".
- 실제 마이크·음성 인식은 자동 테스트하지 않는다. 사용 중인 Sillog 앱은 자동으로 조작하지 않는다(검증은 테스트, 스냅샷, 빌드, 시험 앱으로만). 설치·실행은 사용자가 한다.
- 커밋은 사용자가 실행을 승인한 작업 브랜치에서만 한다. 메시지 끝에 `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. 푸시·PR은 따로 요청이 있을 때만.

## Review Focus

1. **녹음 중에 앱을 끝냄**(메뉴 [종료], 로그아웃): 파일이 닫히지 않으면 다시 받아쓸 수 없다. 끝낼 때 녹음기를 멈추고 `transcribing`으로 두어 다음 실행 때 이어 받아써야 한다. → Task 8 `testQuittingWhileRecordingClosesTheFileForTheNextLaunch`.
2. **Info.plist 없는 실행(`swift run`)에서 [녹음 시작]**: 사용 문구 없이 마이크·음성 인식 권한을 물으면 시스템이 앱을 끝낸다. 묻지 말고 안내만 해야 한다. → Task 8 `testWithoutUsageStringsItRefusesBeforeAskingTheSystem`, Task 9 `testAppBundleDeclaresMicrophoneSpeechAndDocumentsUsage`.
3. **정리가 끝난 뒤 늦게 도착한 진행 알림**: "녹음을 정리하는 중"이 메뉴에 남으면 안 된다. → Task 8 `testLateProgressFromAFinishedRunIsIgnored`.
4. **받아쓴 글 `.md`를 앱 밖에서 옮기거나 지움**: 보관함은 "파일을 찾을 수 없어요"와 앱 안의 글을 보여 주고, 그래프 카드 열기는 조용히 실패해야 한다. → Task 11 `testMissingTextFileIsReportedAndNotOpened`.
5. **받아쓰는 동안 새 녹음 시작**: 긴 강의를 받아쓰는 몇 분 동안 녹음 버튼이 막히면 안 된다. 새 녹음은 바로 시작하고 정리는 차례로 한다. → Task 8 `testANewRecordingCanStartWhileTheLastIsStillBeingProcessed`.

---

## 시작 전에

- 작업 브랜치 `feat/voice-recording`은 실행 방식을 고를 때 사용자와 정한 기준 커밋에서 만든다. 기준 커밋은 Swift 6.2 빌드 수정(`9a3a5fe`)을 포함해야 한다. 확인: `git merge-base --is-ancestor 9a3a5fe HEAD && echo ok` → `ok`.
- `swift build 2>&1 | tail -3` 이 `Build complete!` 로 끝나야 한다.
- 전체 테스트는 `swift test 2>&1 | tail -5` (Vision 글자 인식 테스트가 있어 몇 분 걸린다). 태스크 중간에는 `swift test --filter <클래스이름>` 으로 좁힌다.
- 스냅샷: `WORKGRAPH_SNAPSHOT=/tmp/wg-shots swift run WorkGraphApp` → `/tmp/wg-shots/*.png` 를 Read 로 열어 본다.
- 이 계획의 결정 사항 (스펙에 없는 세부를 정한 것):
  - 녹음 상태를 하나(`RecordingPhase`)로 두지 않고 `activeRecording`(녹음 중) · `recordingWork`(받아쓰는 중·정리하는 중) · `recordingProblem`(권한·받아쓰기 꺼짐 등)으로 나눈다. 받아쓰는 동안에도 새로 녹음할 수 있게 하려는 것이다. 메뉴에 보이는 줄과 문구는 스펙 그대로다.
  - 정리 파이프라인(`RecordingPipeline`)은 Core에 둔다. 가짜 받아쓰기·가짜 LLM으로 Core에서 단계 순서까지 시험할 수 있다. `AppState+Recording`은 녹음기·권한·알림만 잇는다.
  - 녹음 행은 `ActivityRow.isChat = true`로 만든다. 이 값은 "창 기록이 아닌 행"(체류 0, 앱 노드 없음, 화면 카드 없음, 기본은 자료)으로 쓰이고 있어 녹음에도 그대로 맞는다. 필드 설명을 그렇게 고친다.
  - `ready_at` 열을 더한다. 7일 규칙의 기준("ready 가 된 지 7일")이 필요하기 때문이다.
  - `Recording` 자료 종류의 상위 클래스는 `참고자료`로 둔다.
  - 업무 합치기·없애기, 다시 판정, `wgctl rebuild-graph` 때 녹음의 `task_id`·`batch_id`도 대화 기록처럼 따라가게 한다.
  - 앱을 끝낼 때 녹음 중이면 파일을 닫고 `transcribing`으로 둔다(다음 실행 때 이어 받아씀).
  - 보관함 '전체 종류'에도 녹음을 날짜순으로 섞어 보인다. 프로젝트를 고르면 녹음은 빠진다(녹음은 프로젝트에 연결하지 않는다).

## 파일 구조

Core (`Sources/WorkGraphCore/Recording/`, 새 폴더)
- `Recording.swift` — 녹음 기록 모델과 상태.
- `RecordingStore.swift` — `v16-recordings` 마이그레이션, 조회, 배치 표시·배정, 7일 삭제, 받아쓴 글 경로 갱신.
- `TranscriptCollector.swift` — 인식 결과 → 발화별 문장과 진행률.
- `RecordingTitler.swift` — 제목·요약(LLM), 파일 이름, `.md` 본문·쓰기, 내용 발췌, `RecordingText`(길이·시계 문구).
- `RecordingPipeline.swift` — `Transcribing` 프로토콜, `TranscriptionError`, 받아쓰기 → 제목 → `.md` → 폴더 추천 → ready.

Core (수정)
- `Storage/WGDatabase.swift` — 마이그레이션 등록, `recordingsDirectory`.
- `Storage/StorageUsage.swift` — '녹음' 범주. `Storage/Pruner.swift` — FTS 정리 목록.
- `Storage/EventStore.swift` — 다시 판정할 때 녹음도 되돌린다.
- `Files/FolderSuggester.swift` — `Context.kind`, `contentExcerpt`, 녹음용 시스템 프롬프트. `Files/FileSuggestionCopy.swift` — 녹음 알림 문구.
- `Ontology/EventCompressor.swift` — `ActivityRow.recordingIds`, `merge(recordings:)`. `Ontology/OntologyBatcher.swift` — 녹음 합치기, mark·assign.
- `Ontology/Staged/StagePrompts.swift`, `Ontology/OntologyPrompt.swift` — 녹음 행 설명 한 줄.
- `Ontology/TBox.swift`, `Ontology/AssignmentApplier.swift` — `Recording` 자료 종류. `Ontology/TaskMerger.swift` — 업무 합치기·없애기.
- `Chat/ContextSearch.swift`, `Chat/ChatTools.swift`, `Chat/Prompts/chat-system-prompt.md` — `recording:` 출처.
- `Sources/wgctl/main.swift` — `rebuild-graph` 때 녹음 되돌리기.

Collectors (수정)
- `Sources/WorkGraphCollectors/Permissions.swift` — 마이크·음성 인식 패널, 받아쓰기 설정 주소.

App (`Sources/WorkGraphApp/Recording/`, 새 폴더)
- `RecordingPermissions.swift` — `RecordingProblem`, `RecordingPermissions`, `SystemRecordingPermissions`.
- `VoiceRecorder.swift` — `AudioRecording`, `VoiceRecorder`, `AudioFileInfo`.
- `SpeechTranscriber.swift` — 기기 안 받아쓰기.

App (새·수정)
- `AppState+Recording.swift`(새) — 시작·끝·정리 차례·이어 하기·다시 받아쓰기·7일 삭제·폴더 제안·알림·경로 갱신.
- `AppState.swift` — 상태 값, 파이프라인 만들기, 시작 작업, 종료 처리. `AppState+Files.swift` — 옮기기·되돌리기 때 녹음 경로 갱신.
- `SuggestionNotifier.swift` — 녹음 문구, 저장 알림.
- `Views/MenuBarView.swift`, `WorkGraphApp.swift` — 녹음 줄, 빨간 점.
- `Views/LibraryView.swift`, `Views/RecordingDetailView.swift`(새) — '녹음' 종류, 상세, 듣기.
- `Views/GraphWebView.swift`, `Resources/graph/index.html` — 카드에서 녹음 열기. `Views/ChatMessageText.swift` — 인용 패턴.
- `Snapshots/SnapshotCatalog.swift` — 녹음 스냅샷. `scripts/make-app.sh` — Info.plist 사용 문구.

Tests
- Core(새): `RecordingStoreTests`, `TranscriptCollectorTests`, `RecordingTitlerTests`, `RecordingPipelineTests`, `RecordingBatchTests`, `RecordingSearchTests`.
- Core(추가): `FolderSuggesterTests`, `FileSuggestionCopyTests`, `EventCompressorTests`, `StorageUsageTests`, `OntologyBatcherTests.swift` 의 `StubLLM`(`lastSystem`).
- App(새): `RecordingFlowTests`, `RecordingMenuTests`, `RecordingLibraryTests`, `RecordingCitationTests`.

---

### Task 1: 녹음 기록과 저장소

**Files:**
- Create: `Sources/WorkGraphCore/Recording/Recording.swift`
- Create: `Sources/WorkGraphCore/Recording/RecordingStore.swift`
- Modify: `Sources/WorkGraphCore/Storage/WGDatabase.swift` (`libraryDirectory` 바로 아래, `migrator` 끝)
- Modify: `Sources/WorkGraphCore/Storage/StorageUsage.swift` (범주 enum, `category(of:)`, `measure`)
- Modify: `Sources/WorkGraphCore/Storage/Pruner.swift:302` (FTS 정리 목록)
- Test: `Tests/WorkGraphCoreTests/RecordingStoreTests.swift` (새), `Tests/WorkGraphCoreTests/StorageUsageTests.swift` (추가)

**Interfaces:**
- Consumes: 없음.
- Produces:
  - `public struct Recording` — `id: Int64?, startedAt: Double, endedAt: Double?, duration: Double, audioPath: String, audioDeletedAt: Double?, textPath: String?, title: String?, summary: String?, transcript: String, status: Recording.Status, error: String?, readyAt: Double?, batchId: Int64?, taskId: Int64?, suggestionId: Int64?`. init 은 `startedAt`·`audioPath` 만 필수(나머지 기본값: `duration 0`, `transcript ""`, `status .recording`, 나머지 nil).
  - `Recording.Status`: `.recording | .transcribing | .ready | .failed` (String raw value).
  - `Recording.hasTranscript: Bool`, `Recording.utterances: [String]`(transcript 의 줄), `Recording.displayTitle: String`.
  - `public struct RecordingStore` — `init(_ db: WGDatabase)`, `static let audioKeepDays: Double = 7`, `insert(_:) -> Recording`, `update(_:)`, `delete(id:)`, `find(id:) -> Recording?`, `find(textPath:) -> Recording?`, `all() -> [Recording]`(최신순), `unfinished() -> [Recording]`(recording·transcribing, 오래된 순), `unprocessed(upTo:notOlderThan:) -> [Recording]`, `static mark(_ conn: Database, ids: [Int64], batchId: Int64)`, `static assign(_ conn: Database, ids: [Int64], taskId: Int64?)`, `expiredAudio(now:) -> [Recording]`, `deleteExpiredAudio(now:) -> Int`, `moveText(from:to:) -> Bool`.
  - `WGDatabase.recordingsDirectory: URL`.
  - `StorageUsage.Category.recordings` (제목 "녹음").

- [ ] **Step 1: 실패하는 테스트 쓰기**

`Tests/WorkGraphCoreTests/RecordingStoreTests.swift`:

```swift
import XCTest
import GRDB
@testable import WorkGraphCore

/// 녹음 기록: 검색 색인, 남은 녹음, 정리 대기·표시·배정, 7일 지난 녹음 파일, 받아쓴 글 경로
final class RecordingStoreTests: XCTestCase {
    private var db: WGDatabase!
    private var store: RecordingStore!
    private var folder: URL!

    override func setUpWithError() throws {
        db = try WGDatabase.inMemory()
        store = RecordingStore(db)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("wg-recordings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func matches(_ word: String) throws -> [Int64] {
        try db.writer.read { try Int64.fetchAll($0, sql: "SELECT rowid FROM recordings_fts WHERE recordings_fts MATCH ?", arguments: ["\"\(word)\""]) }
    }

    private func file(_ name: String) throws -> String {
        let url = folder.appendingPathComponent(name)
        try Data("audio".utf8).write(to: url)
        return url.path
    }

    func testSearchIndexFollowsInsertUpdateAndDelete() throws {
        var recording = try store.insert(Recording(startedAt: 1, audioPath: "/a.m4a"))
        XCTAssertEqual(recording.status, .recording)
        XCTAssertTrue(try matches("연결리스트").isEmpty)
        recording.title = "자료구조 3주차"
        recording.transcript = "오늘은 연결리스트를 봅니다."
        try store.update(recording)
        XCTAssertEqual(try matches("연결리스트"), [recording.id!])
        XCTAssertEqual(try matches("자료구조"), [recording.id!])
        try store.delete(id: recording.id!)
        XCTAssertTrue(try matches("연결리스트").isEmpty)
        XCTAssertNil(try store.find(id: recording.id!))
    }

    func testUnfinishedIsRecordingOrTranscribingOldestFirstAndAllIsNewestFirst() throws {
        let a = try store.insert(Recording(startedAt: 10, audioPath: "/a", status: .transcribing))
        let b = try store.insert(Recording(startedAt: 20, audioPath: "/b", status: .recording))
        let c = try store.insert(Recording(startedAt: 30, audioPath: "/c", transcript: "가", status: .ready, readyAt: 31))
        let d = try store.insert(Recording(startedAt: 40, audioPath: "/d", status: .failed, error: "x"))
        XCTAssertEqual(try store.unfinished().map(\.id), [a.id, b.id])
        XCTAssertEqual(try store.all().map(\.id), [d.id, c.id, b.id, a.id])
    }

    func testUnprocessedIsReadyWithTextInsideTheWindowUntilMarked() throws {
        let ready = try store.insert(Recording(startedAt: 100, endedAt: 200, duration: 100, audioPath: "/a", transcript: "가나다", status: .ready, readyAt: 210))
        _ = try store.insert(Recording(startedAt: 100, endedAt: 200, duration: 100, audioPath: "/b", transcript: "  ", status: .ready, readyAt: 210))     // 받아쓴 글 없음
        _ = try store.insert(Recording(startedAt: 100, endedAt: 200, duration: 100, audioPath: "/c", transcript: "가나다", status: .transcribing))        // 아직 정리 중
        _ = try store.insert(Recording(startedAt: 900, endedAt: 1_000, duration: 100, audioPath: "/d", transcript: "가나다", status: .ready, readyAt: 1_010)) // 창보다 뒤
        _ = try store.insert(Recording(startedAt: 0, endedAt: 10, duration: 10, audioPath: "/e", transcript: "가나다", status: .ready, readyAt: 20))       // 너무 오래됨
        XCTAssertEqual(try store.unprocessed(upTo: 500, notOlderThan: 50).map(\.id), [ready.id])

        try db.writer.write { conn in
            try RecordingStore.mark(conn, ids: [ready.id!], batchId: 3)
            try RecordingStore.assign(conn, ids: [ready.id!], taskId: 9)
        }
        XCTAssertTrue(try store.unprocessed(upTo: 500, notOlderThan: 50).isEmpty)
        let saved = try XCTUnwrap(store.find(id: ready.id!))
        XCTAssertEqual(saved.batchId, 3)
        XCTAssertEqual(saved.taskId, 9)
    }

    func testOldReadyAudioIsDeletedOnceButFailedAndRecentAreKept() throws {
        let now = 100 * 86_400.0
        let old = try store.insert(Recording(startedAt: 0, endedAt: 60, duration: 60, audioPath: try file("old.m4a"), transcript: "가", status: .ready, readyAt: now - 8 * 86_400))
        let recent = try store.insert(Recording(startedAt: 0, endedAt: 60, duration: 60, audioPath: try file("recent.m4a"), transcript: "가", status: .ready, readyAt: now - 2 * 86_400))
        let failed = try store.insert(Recording(startedAt: 0, endedAt: 60, duration: 60, audioPath: try file("failed.m4a"), status: .failed, error: "받아쓰기 꺼짐"))
        XCTAssertEqual(try store.expiredAudio(now: now).map(\.id), [old.id])

        XCTAssertEqual(try store.deleteExpiredAudio(now: now), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.audioPath))
        XCTAssertEqual(try store.find(id: old.id!)?.audioDeletedAt, now)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.audioPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.audioPath), "받아쓰기에 실패한 녹음은 다시 받아쓸 수 있게 남긴다")
        XCTAssertEqual(try store.deleteExpiredAudio(now: now), 0, "한 번 지운 것은 다시 고르지 않는다")
    }

    func testTextPathFollowsTheMovedFile() throws {
        let recording = try store.insert(Recording(startedAt: 1, audioPath: "/a", textPath: "/Docs/Sillog 녹음/회의.md", transcript: "가", status: .ready))
        XCTAssertTrue(try store.moveText(from: "/Docs/Sillog 녹음/회의.md", to: "/Docs/학교/회의.md"))
        XCTAssertEqual(try store.find(textPath: "/Docs/학교/회의.md")?.id, recording.id)
        XCTAssertNil(try store.find(textPath: "/Docs/Sillog 녹음/회의.md"))
        XCTAssertFalse(try store.moveText(from: "/없는/경로.md", to: "/x.md"))
    }
}
```

`Tests/WorkGraphCoreTests/StorageUsageTests.swift` 클래스 안 끝에 추가:

```swift
    func testRecordingsAreTheirOwnCategoryWithTheAudioFolder() throws {
        XCTAssertEqual(StorageUsage.category(of: "recordings"), .recordings)
        XCTAssertEqual(StorageUsage.category(of: "recordings_fts_data"), .recordings)
        XCTAssertEqual(StorageUsage.Category.recordings.title, "녹음")
        let db = try WGDatabase.inMemory()
        try FileManager.default.createDirectory(at: db.recordingsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: db.recordingsDirectory) }
        try Data(repeating: 1, count: 10_000).write(to: db.recordingsDirectory.appendingPathComponent("1.m4a"))
        let usage = try StorageUsage.measure(db: db, capturesDir: nil)
        XCTAssertGreaterThanOrEqual(usage.bytes[.recordings] ?? 0, 10_000)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter "RecordingStoreTests|StorageUsageTests" 2>&1 | tail -5`
Expected: 컴파일 실패 — `cannot find 'Recording' in scope`, `type 'StorageUsage.Category' has no member 'recordings'`.

- [ ] **Step 3: 모델 만들기**

`Sources/WorkGraphCore/Recording/Recording.swift`:

```swift
import Foundation
import GRDB

/// 메뉴 막대에서 녹음한 것 한 건. status: recording → transcribing → ready | failed
/// 녹음 파일(audioPath)은 앱 데이터 폴더에 두었다가 ready 가 되고 7일 뒤 지운다. 받아쓴 글(textPath)은 사용자 파일이라 지우지 않는다
public struct Recording: Codable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord, Identifiable {
    public enum Status: String, Codable, Sendable { case recording, transcribing, ready, failed }

    public static let databaseTableName = "recordings"
    public var id: Int64?
    public var startedAt: Double
    public var endedAt: Double?
    /// 녹음 길이(초)
    public var duration: Double
    public var audioPath: String
    public var audioDeletedAt: Double?
    /// 받아쓴 글 .md. 받아쓴 글이 없으면 nil
    public var textPath: String?
    public var title: String?
    public var summary: String?
    /// 발화마다 한 줄
    public var transcript: String
    public var status: Status
    public var error: String?
    /// ready 가 된 시각 (녹음 파일 7일 규칙의 기준)
    public var readyAt: Double?
    public var batchId: Int64?
    public var taskId: Int64?
    public var suggestionId: Int64?

    public init(id: Int64? = nil, startedAt: Double, endedAt: Double? = nil, duration: Double = 0, audioPath: String,
                audioDeletedAt: Double? = nil, textPath: String? = nil, title: String? = nil, summary: String? = nil,
                transcript: String = "", status: Status = .recording, error: String? = nil, readyAt: Double? = nil,
                batchId: Int64? = nil, taskId: Int64? = nil, suggestionId: Int64? = nil) {
        self.id = id; self.startedAt = startedAt; self.endedAt = endedAt; self.duration = duration; self.audioPath = audioPath
        self.audioDeletedAt = audioDeletedAt; self.textPath = textPath; self.title = title; self.summary = summary
        self.transcript = transcript; self.status = status; self.error = error; self.readyAt = readyAt
        self.batchId = batchId; self.taskId = taskId; self.suggestionId = suggestionId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at", endedAt = "ended_at", duration
        case audioPath = "audio_path", audioDeletedAt = "audio_deleted_at", textPath = "text_path"
        case title, summary, transcript, status, error
        case readyAt = "ready_at", batchId = "batch_id", taskId = "task_id", suggestionId = "suggestion_id"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public var hasTranscript: Bool { !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 발화별 문장 (빈 줄은 뺀다)
    public var utterances: [String] {
        transcript.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 목록에 보일 이름: 제목, 없으면 상태
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        switch status {
        case .recording: return "녹음 중"
        case .transcribing: return "받아쓰는 중인 녹음"
        case .ready, .failed: return "제목 없는 녹음"
        }
    }
}
```

- [ ] **Step 4: 저장소 만들기**

`Sources/WorkGraphCore/Recording/RecordingStore.swift`:

```swift
import Foundation
import GRDB

/// 녹음 기록 저장소. 받아쓴 글은 trigram 색인(recordings_fts)으로 채팅에서 찾는다
public struct RecordingStore: Sendable {
    /// 받아쓰기가 끝난 녹음 파일을 두는 기간 (일)
    public static let audioKeepDays: Double = 7

    let db: WGDatabase
    public init(_ db: WGDatabase) { self.db = db }

    static func migrate(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v16-recordings") { conn in
            try conn.execute(sql: """
                CREATE TABLE recordings (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  started_at REAL NOT NULL,
                  ended_at REAL,
                  duration REAL NOT NULL DEFAULT 0,
                  audio_path TEXT NOT NULL,
                  audio_deleted_at REAL,
                  text_path TEXT,
                  title TEXT,
                  summary TEXT,
                  transcript TEXT NOT NULL DEFAULT '',
                  status TEXT NOT NULL,
                  error TEXT,
                  ready_at REAL,
                  batch_id INTEGER,
                  task_id INTEGER,
                  suggestion_id INTEGER
                );
                CREATE INDEX idx_recordings_status ON recordings(status, batch_id, ended_at);
                CREATE INDEX idx_recordings_text_path ON recordings(text_path);
                CREATE VIRTUAL TABLE recordings_fts USING fts5(title, summary, transcript, content='recordings', content_rowid='id', tokenize='trigram');
                CREATE TRIGGER recordings_ai AFTER INSERT ON recordings BEGIN
                  INSERT INTO recordings_fts(rowid, title, summary, transcript) VALUES (new.id, new.title, new.summary, new.transcript);
                END;
                CREATE TRIGGER recordings_ad AFTER DELETE ON recordings BEGIN
                  INSERT INTO recordings_fts(recordings_fts, rowid, title, summary, transcript) VALUES ('delete', old.id, old.title, old.summary, old.transcript);
                END;
                CREATE TRIGGER recordings_au AFTER UPDATE ON recordings BEGIN
                  INSERT INTO recordings_fts(recordings_fts, rowid, title, summary, transcript) VALUES ('delete', old.id, old.title, old.summary, old.transcript);
                  INSERT INTO recordings_fts(rowid, title, summary, transcript) VALUES (new.id, new.title, new.summary, new.transcript);
                END;
                """)
        }
    }

    @discardableResult
    public func insert(_ recording: Recording) throws -> Recording {
        try db.writer.write { conn in var copy = recording; try copy.insert(conn); return copy }
    }

    public func update(_ recording: Recording) throws {
        try db.writer.write { try recording.update($0) }
    }

    /// 녹음을 시작하지 못했을 때 만든 기록을 지운다
    public func delete(id: Int64) throws {
        _ = try db.writer.write { try Recording.deleteOne($0, key: id) }
    }

    public func find(id: Int64) throws -> Recording? {
        try db.writer.read { try Recording.fetchOne($0, key: id) }
    }

    public func find(textPath: String) throws -> Recording? {
        try db.writer.read { try Recording.fetchOne($0, sql: "SELECT * FROM recordings WHERE text_path = ? ORDER BY id DESC LIMIT 1", arguments: [textPath]) }
    }

    /// 최신순 전부 (보관함)
    public func all() throws -> [Recording] {
        try db.writer.read { try Recording.fetchAll($0, sql: "SELECT * FROM recordings ORDER BY started_at DESC, id DESC") }
    }

    /// 앱이 꺼진 동안 끝나지 않은 것 (녹음 중·받아쓰는 중), 오래된 것부터
    public func unfinished() throws -> [Recording] {
        try db.writer.read { try Recording.fetchAll($0, sql: "SELECT * FROM recordings WHERE status IN ('recording', 'transcribing') ORDER BY started_at, id") }
    }

    /// 정리 대기: ready 이고 받아쓴 글이 있으며 아직 어느 배치에도 안 들어간 것 중 [notOlderThan, upTo] 안에 끝난 것
    public func unprocessed(upTo: Double, notOlderThan: Double) throws -> [Recording] {
        try db.writer.read { conn in
            try Recording.fetchAll(conn, sql: """
                SELECT * FROM recordings WHERE status = 'ready' AND batch_id IS NULL AND trim(transcript) != ''
                  AND ended_at <= ? AND ended_at >= ? ORDER BY started_at, id
                """, arguments: [upTo, notOlderThan])
        }
    }

    public static func mark(_ conn: Database, ids: [Int64], batchId: Int64) throws {
        guard !ids.isEmpty else { return }
        let list = ids.map(String.init).joined(separator: ",")
        try conn.execute(sql: "UPDATE recordings SET batch_id = ? WHERE id IN (\(list))", arguments: [batchId])
    }

    public static func assign(_ conn: Database, ids: [Int64], taskId: Int64?) throws {
        guard !ids.isEmpty else { return }
        let list = ids.map(String.init).joined(separator: ",")
        try conn.execute(sql: "UPDATE recordings SET task_id = ? WHERE id IN (\(list))", arguments: [taskId])
    }

    /// ready 가 된 지 7일 지났고 아직 녹음 파일을 지우지 않은 것 (받아쓰기에 실패한 녹음은 다시 받아쓸 수 있게 뺀다)
    public func expiredAudio(now: Double) throws -> [Recording] {
        try db.writer.read { conn in
            try Recording.fetchAll(conn, sql: """
                SELECT * FROM recordings WHERE status = 'ready' AND audio_deleted_at IS NULL AND ready_at IS NOT NULL AND ready_at <= ?
                ORDER BY ready_at, id
                """, arguments: [now - Self.audioKeepDays * 86_400])
        }
    }

    /// 7일 지난 녹음 파일을 지우고 지운 시각을 남긴다. 지우지 못한 것은 다음에 다시 해 본다. 지운 개수
    @discardableResult
    public func deleteExpiredAudio(now: Double) throws -> Int {
        var count = 0
        for var recording in try expiredAudio(now: now) {
            if FileManager.default.fileExists(atPath: recording.audioPath) {
                do { try FileManager.default.removeItem(atPath: recording.audioPath) } catch { continue }
            }
            recording.audioDeletedAt = now
            try update(recording)
            count += 1
        }
        return count
    }

    /// 받아쓴 글 파일이 옮겨졌을 때 (폴더 제안 수락·되돌리기). 바꾼 기록이 있으면 true
    @discardableResult
    public func moveText(from old: String, to new: String) throws -> Bool {
        try db.writer.write { conn in
            try conn.execute(sql: "UPDATE recordings SET text_path = ? WHERE text_path = ?", arguments: [new, old])
            return conn.changesCount > 0
        }
    }
}
```

- [ ] **Step 5: DB 에 연결하기**

`Sources/WorkGraphCore/Storage/WGDatabase.swift` — `libraryDirectory` 바로 아래에 추가:

```swift
    /// 녹음 파일 폴더 (받아쓰기가 끝나고 7일 뒤 지운다). 메모리 DB 는 임시 폴더
    public var recordingsDirectory: URL {
        path.map { URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("recordings", isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Sillog-recordings-\(memoryLibraryID)", isDirectory: true)
    }
```

같은 파일 `migrator` 끝의 `ConsolidationStore.migrate(&migrator)` 다음 줄에 추가:

```swift
        RecordingStore.migrate(&migrator)
```

- [ ] **Step 6: 저장 공간 범주와 FTS 정리**

`Sources/WorkGraphCore/Storage/StorageUsage.swift`:
- `case screenshots, screenText, batchLog, observations, screenCards, aiRequests, digests, graph, chatLibrary, other` → `case screenshots, screenText, batchLog, observations, screenCards, aiRequests, digests, graph, chatLibrary, recordings, other`
- `title` 의 `case .chatLibrary: "채팅·보관함"` 다음 줄에 `case .recordings: "녹음"` 추가.
- `category(of:)` 의 `prefixes` 배열 마지막 요소 뒤에 `("recordings", .recordings), ("idx_recordings", .recordings),` 추가.
- `measure` 의 `usage.bytes[.chatLibrary, default: 0] += folderBytes(db.libraryDirectory)` 다음 줄에 추가:

```swift
        usage.bytes[.recordings, default: 0] += folderBytes(db.recordingsDirectory)
```

`Sources/WorkGraphCore/Storage/Pruner.swift:302` 의 목록 끝에 `"recordings_fts"` 를 더한다:

```swift
        for index in ["text_snapshots_chat_fts", "nodes_chat_fts", "chat_messages_chat_fts", "screen_cards_fts", "app_messages_fts", "digests_fts", "recordings_fts"] {
```

- [ ] **Step 7: 통과 확인**

Run: `swift test --filter "RecordingStoreTests|StorageUsageTests|PrunerTests|DatabaseTests" 2>&1 | tail -5`
Expected: 모두 통과 (`Executed N tests, with 0 failures`).

- [ ] **Step 8: 커밋**

```bash
git add Sources/WorkGraphCore/Recording Sources/WorkGraphCore/Storage/WGDatabase.swift Sources/WorkGraphCore/Storage/StorageUsage.swift Sources/WorkGraphCore/Storage/Pruner.swift Tests/WorkGraphCoreTests/RecordingStoreTests.swift Tests/WorkGraphCoreTests/StorageUsageTests.swift
git commit -m "$(cat <<'EOF'
녹음 기록 표(v16-recordings)와 저장소: 검색 색인, 정리 대기, 7일 지난 녹음 파일 지우기

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 2: 발화 모으기 (TranscriptCollector)

**Files:**
- Create: `Sources/WorkGraphCore/Recording/TranscriptCollector.swift`
- Test: `Tests/WorkGraphCoreTests/TranscriptCollectorTests.swift` (새)

**Interfaces:**
- Consumes: 없음.
- Produces: `public struct TranscriptCollector: Sendable` — `init(duration: Double)`, `mutating func add(text: String, utteranceEnded: Bool, isFinal: Bool, lastWordEnd: Double)`, `mutating func finish() -> [String]`, `private(set) var utterances: [String]`, `private(set) var progress: Double`(0~0.99, `finish()` 뒤 1).

- [ ] **Step 1: 실패하는 테스트 쓰기**

`Tests/WorkGraphCoreTests/TranscriptCollectorTests.swift`:

```swift
import XCTest
@testable import WorkGraphCore

/// 기기 안 인식 결과는 발화마다 나뉘고, 마지막 결과에는 마지막 발화만 다시 온다 (10/10 측정)
final class TranscriptCollectorTests: XCTestCase {
    func testUtterancesAreCollectedAtEachEndMarkAndTheRepeatedFinalIsDropped() {
        var collector = TranscriptCollector(duration: 100)
        collector.add(text: "오늘은", utteranceEnded: false, isFinal: false, lastWordEnd: 1)
        collector.add(text: "오늘은 연결 리스트를", utteranceEnded: false, isFinal: false, lastWordEnd: 2)
        collector.add(text: "오늘은 연결 리스트를 봅니다.", utteranceEnded: true, isFinal: false, lastWordEnd: 3)
        collector.add(text: "노드는", utteranceEnded: false, isFinal: false, lastWordEnd: 50)
        collector.add(text: "노드는 값을 가집니다.", utteranceEnded: true, isFinal: false, lastWordEnd: 60)
        collector.add(text: "노드는 값을 가집니다.", utteranceEnded: false, isFinal: true, lastWordEnd: 60)
        XCTAssertEqual(collector.finish(), ["오늘은 연결 리스트를 봅니다.", "노드는 값을 가집니다."])
    }

    func testAnUnfinishedUtteranceIsKeptWhenTheFileEnds() {
        var collector = TranscriptCollector(duration: 100)
        collector.add(text: "첫 문장.", utteranceEnded: true, isFinal: false, lastWordEnd: 10)
        collector.add(text: "끝나지 않은 말", utteranceEnded: false, isFinal: false, lastWordEnd: 20)
        XCTAssertEqual(collector.finish(), ["첫 문장.", "끝나지 않은 말"])
    }

    func testAFinalWithANewUtteranceIsAdded() {
        var collector = TranscriptCollector(duration: 100)
        collector.add(text: "첫 문장.", utteranceEnded: true, isFinal: false, lastWordEnd: 10)
        collector.add(text: "둘째 문장.", utteranceEnded: false, isFinal: true, lastWordEnd: 20)
        XCTAssertEqual(collector.finish(), ["첫 문장.", "둘째 문장."])
    }

    func testAFinalCarryingTheWholeTextIsNotAddedAgain() {
        var collector = TranscriptCollector(duration: 100)
        collector.add(text: "첫 문장.", utteranceEnded: true, isFinal: false, lastWordEnd: 10)
        collector.add(text: "둘째 문장.", utteranceEnded: true, isFinal: false, lastWordEnd: 20)
        collector.add(text: "첫 문장. 둘째 문장.", utteranceEnded: false, isFinal: true, lastWordEnd: 20)
        XCTAssertEqual(collector.finish(), ["첫 문장.", "둘째 문장."])
    }

    func testProgressFollowsTheLastWordNeverGoesBackAndStaysBelowOneUntilFinished() {
        var collector = TranscriptCollector(duration: 200)
        collector.add(text: "가", utteranceEnded: false, isFinal: false, lastWordEnd: 74)
        XCTAssertEqual(collector.progress, 0.37, accuracy: 0.001)
        collector.add(text: "가", utteranceEnded: false, isFinal: false, lastWordEnd: 10)
        XCTAssertEqual(collector.progress, 0.37, accuracy: 0.001, "앞으로만 간다")
        collector.add(text: "가", utteranceEnded: false, isFinal: false, lastWordEnd: 500)
        XCTAssertEqual(collector.progress, 0.99, accuracy: 0.001)
        _ = collector.finish()
        XCTAssertEqual(collector.progress, 1)
    }

    func testEmptyResultsAreIgnored() {
        var collector = TranscriptCollector(duration: 10)
        collector.add(text: "  ", utteranceEnded: true, isFinal: false, lastWordEnd: 1)
        XCTAssertEqual(collector.finish(), [])
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter TranscriptCollectorTests 2>&1 | tail -5`
Expected: 컴파일 실패 — `cannot find 'TranscriptCollector' in scope`.

- [ ] **Step 3: 구현**

`Sources/WorkGraphCore/Recording/TranscriptCollector.swift`:

```swift
import Foundation

/// 음성 인식 결과를 차례로 받아 발화별 문장을 모은다.
/// 기기 안 인식은 말이 쉬는 틈마다 결과를 새로 시작하고, 마지막(isFinal) 결과에는 마지막 발화만 남는다 (10/10 측정).
/// 그래서 발화 끝 표시(speechRecognitionMetadata)가 붙은 결과를 모으고, 마지막 결과가 이미 모은 글이면 다시 붙이지 않는다
public struct TranscriptCollector: Sendable {
    public private(set) var utterances: [String] = []
    /// 0~0.99 (끝까지 받으면 1)
    public private(set) var progress: Double = 0
    private var pending = ""
    private let duration: Double

    public init(duration: Double) { self.duration = duration }

    /// Args: text 는 이 결과의 글(한 발화), utteranceEnded 는 발화 끝 표시, isFinal 은 마지막 결과,
    ///   lastWordEnd 는 마지막 단어가 끝난 시각(초, 파일 처음부터)이다.
    public mutating func add(text: String, utteranceEnded: Bool, isFinal: Bool, lastWordEnd: Double) {
        if duration > 0 { progress = min(0.99, max(progress, lastWordEnd / duration)) }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if isFinal {
            pending = ""
            if !alreadyCollected(clean) { utterances.append(clean) }
        } else if utteranceEnded {
            pending = ""
            utterances.append(clean)
        } else {
            pending = clean
        }
    }

    /// 끝까지 받은 뒤: 끝나지 않은 발화도 붙인다
    public mutating func finish() -> [String] {
        if !pending.isEmpty, !alreadyCollected(pending) { utterances.append(pending) }
        pending = ""
        progress = 1
        return utterances
    }

    /// 마지막 발화와 같거나, 모은 발화 전부를 이은 것과 같으면 (공백 차이는 무시)
    private func alreadyCollected(_ text: String) -> Bool {
        guard let last = utterances.last else { return false }
        if last == text { return true }
        let squeezed = text.filter { !$0.isWhitespace }
        return squeezed == utterances.joined().filter { !$0.isWhitespace }
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter TranscriptCollectorTests 2>&1 | tail -5`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: 커밋**

```bash
git add Sources/WorkGraphCore/Recording/TranscriptCollector.swift Tests/WorkGraphCoreTests/TranscriptCollectorTests.swift
git commit -m "$(cat <<'EOF'
받아쓰기 결과를 발화별로 모으기: 발화 끝 표시로 모으고 마지막 결과 중복은 빼기

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 제목·요약과 받아쓴 글 파일 (RecordingTitler)

**Files:**
- Create: `Sources/WorkGraphCore/Recording/RecordingTitler.swift`
- Test: `Tests/WorkGraphCoreTests/RecordingTitlerTests.swift` (새)

**Interfaces:**
- Consumes: `Recording` (Task 1), `LLMClient`·`ToolSpec`·`AppLog` (기존), 테스트의 `StubLLM`(`Tests/WorkGraphCoreTests/OntologyBatcherTests.swift`).
- Produces:
  - `public enum RecordingText` — `static func duration(_ seconds: Double) -> String`("45초", "52분 10초", "2분", "1시간 3분"), `static func clock(_ seconds: Double) -> String`("12:31", "1:02:03").
  - `public struct RecordingTitler: Sendable` — `init(llm: any LLMClient)`, `struct Naming: Equatable { title: String; summary: String? }`, `func name(transcript:startedAt:duration:timeZone:) async -> Naming`(실패 시 날짜 제목), `static let headChars = 4_000`, `static let excerptChars = 800`, `static func fallbackTitle(startedAt:timeZone:) -> String`, `static func fileName(title:startedAt:timeZone:) -> String`, `static func sanitize(_:) -> String`, `static func markdown(title:summary:utterances:startedAt:duration:timeZone:) -> String`, `static func write(_ recording: Recording, into folder: URL, timeZone: TimeZone) throws -> URL`, `static func excerpt(summary: String?, transcript: String) -> String`.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`Tests/WorkGraphCoreTests/RecordingTitlerTests.swift`:

```swift
import XCTest
@testable import WorkGraphCore

/// 녹음 제목·요약(빠른 모델), 받아쓴 글 파일 이름과 본문
final class RecordingTitlerTests: XCTestCase {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    /// 2026-10-10 15:32 (서울)
    private var start: Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 15, minute: 32))!.timeIntervalSince1970
    }

    func testNameSendsTheTranscriptHeadAndReadsTheToolAnswer() async {
        let llm = StubLLM([.success(#"{"title":" “자료구조 3주차 강의” ","summary":"연결 리스트를 설명한 강의."}"#)])
        let transcript = String(repeating: "가", count: 4_000) + "끝부분은보내지않음"
        let naming = await RecordingTitler(llm: llm).name(transcript: transcript, startedAt: start, duration: 3_130, timeZone: seoul)
        XCTAssertEqual(naming, RecordingTitler.Naming(title: "자료구조 3주차 강의", summary: "연결 리스트를 설명한 강의."))
        XCTAssertTrue(llm.lastUser.contains("RECORDED: 2026-10-10 15:32 (52분 10초)"))
        XCTAssertTrue(llm.lastUser.contains("TRANSCRIPT (first 4000 characters):"))
        XCTAssertFalse(llm.lastUser.contains("끝부분은보내지않음"), "앞 4,000자만 보낸다")
    }

    func testEmptyTranscriptModelFailureAndBlankAnswerGiveTheDateTitle() async {
        let llm = StubLLM([.failure(.transport("offline")), .success(#"{"title":"  ","summary":""}"#)])
        let titler = RecordingTitler(llm: llm)
        let fallback = RecordingTitler.Naming(title: "녹음 2026-10-10 15-32", summary: nil)
        let empty = await titler.name(transcript: " \n ", startedAt: start, duration: 5, timeZone: seoul)
        XCTAssertEqual(empty, fallback)
        XCTAssertEqual(llm.calls, 0, "받아쓴 글이 비면 모델을 부르지 않는다")
        let failed = await titler.name(transcript: "말", startedAt: start, duration: 5, timeZone: seoul)
        XCTAssertEqual(failed, fallback)
        let blank = await titler.name(transcript: "말", startedAt: start, duration: 5, timeZone: seoul)
        XCTAssertEqual(blank, fallback)
    }

    func testFileNameDropsCharactersFilesCannotHaveAndKeepsOneDate() {
        XCTAssertEqual(RecordingTitler.fileName(title: "자료구조: 3주차/강의?", startedAt: start, timeZone: seoul), "2026-10-10 자료구조 3주차 강의.md")
        XCTAssertEqual(RecordingTitler.fileName(title: "녹음 2026-10-10 15-32", startedAt: start, timeZone: seoul), "녹음 2026-10-10 15-32.md")
        XCTAssertEqual(RecordingTitler.fileName(title: "...", startedAt: start, timeZone: seoul), "녹음 2026-10-10 15-32.md", "남는 글자가 없으면 날짜 제목")
    }

    func testMarkdownHasTitleTimeLengthSummaryAndOneParagraphPerUtterance() {
        let text = RecordingTitler.markdown(title: "자료구조 3주차 강의", summary: "연결 리스트를 설명한 강의.", utterances: ["첫 문장.", "둘째 문장."],
                                            startedAt: start, duration: 3_130, timeZone: seoul)
        XCTAssertEqual(text, """
        # 자료구조 3주차 강의

        - 녹음: 2026년 10월 10일 15:32, 52분 10초
        - 요약: 연결 리스트를 설명한 강의.

        ## 받아쓴 글

        첫 문장.

        둘째 문장.

        """)
    }

    func testWriteAddsANumberWhenTheNameIsTaken() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wg-titler-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let recording = Recording(id: 1, startedAt: start, endedAt: start + 60, duration: 60, audioPath: "/a.m4a", title: "회의", transcript: "가\n나", status: .transcribing)
        let first = try RecordingTitler.write(recording, into: folder, timeZone: seoul)
        let second = try RecordingTitler.write(recording, into: folder, timeZone: seoul)
        XCTAssertEqual(first.lastPathComponent, "2026-10-10 회의.md")
        XCTAssertEqual(second.lastPathComponent, "2026-10-10 회의 (2).md")
        XCTAssertTrue(try String(contentsOf: first, encoding: .utf8).contains("가\n\n나"))
    }

    func testDurationAndClockText() {
        XCTAssertEqual(RecordingText.duration(45), "45초")
        XCTAssertEqual(RecordingText.duration(120), "2분")
        XCTAssertEqual(RecordingText.duration(3_130), "52분 10초")
        XCTAssertEqual(RecordingText.duration(3_780), "1시간 3분")
        XCTAssertEqual(RecordingText.clock(751), "12:31")
        XCTAssertEqual(RecordingText.clock(3_723), "1:02:03")
    }

    func testExcerptIsTheSummaryThenTheFirst800Characters() {
        let transcript = "첫 줄\n" + String(repeating: "나", count: 900)
        let excerpt = RecordingTitler.excerpt(summary: "요약 한 줄.", transcript: transcript)
        XCTAssertTrue(excerpt.hasPrefix("요약 한 줄.\n첫 줄 나"))
        XCTAssertEqual(excerpt.count, "요약 한 줄.\n".count + 800)
        XCTAssertEqual(RecordingTitler.excerpt(summary: nil, transcript: "가\n나"), "가 나")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter RecordingTitlerTests 2>&1 | tail -5`
Expected: 컴파일 실패 — `cannot find 'RecordingTitler' in scope`.

- [ ] **Step 3: 구현**

`Sources/WorkGraphCore/Recording/RecordingTitler.swift`:

```swift
import Foundation

/// 녹음 길이·시계 문구
public enum RecordingText {
    /// "45초", "2분", "52분 10초", "1시간 3분"
    public static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)초" }
        if total < 3_600 {
            let minutes = total / 60, rest = total % 60
            return rest == 0 ? "\(minutes)분" : "\(minutes)분 \(rest)초"
        }
        let hours = total / 3_600, minutes = (total % 3_600) / 60
        return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분"
    }

    /// 메뉴 막대의 지난 시간: "12:31", "1:02:03"
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3_600, minutes = (total % 3_600) / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}

/// 받아쓴 글에 제목과 한 줄 요약을 붙이고, 받아쓴 글 .md 를 만든다
public struct RecordingTitler: Sendable {
    public struct Naming: Equatable, Sendable {
        public var title: String
        public var summary: String?
        public init(title: String, summary: String?) { self.title = title; self.summary = summary }
    }

    /// 모델에 보내는 받아쓴 글 앞부분 길이
    public static let headChars = 4_000
    /// 폴더 추천에 넘기는 받아쓴 글 앞부분 길이
    public static let excerptChars = 800

    let llm: any LLMClient
    public init(llm: any LLMClient) { self.llm = llm }

    /// 받아쓴 글이 비었거나 모델이 실패하면 날짜 제목 ("녹음 2026-10-10 15-32")
    public func name(transcript: String, startedAt: Double, duration: Double, timeZone: TimeZone = .current) async -> Naming {
        let fallback = Naming(title: Self.fallbackTitle(startedAt: startedAt, timeZone: timeZone), summary: nil)
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }
        do {
            let prompt = Self.prompt(transcript: transcript, startedAt: startedAt, duration: duration, timeZone: timeZone)
            let result = try await llm.callFunction(system: Self.system, user: prompt, tool: Self.tool)
            return Self.parse(result.arguments) ?? fallback
        } catch {
            AppLog.write("녹음 제목 짓기 실패: \(String(describing: error).prefix(200))")
            return fallback
        }
    }

    static let system = """
    You name a voice recording the user made on their Mac, from its transcript.
    The transcript comes from on-device speech recognition: some words may be misheard, and speakers are not marked.
    Give a short Korean title of about 20 characters that says what the recording is about, such as the course and topic of a lecture or the subject of a meeting. Do not put dates, times or the word 녹음 in the title.
    Give a one-sentence Korean summary of what was said.
    Always answer by calling name_recording.
    """

    static var tool: ToolSpec {
        ToolSpec(name: "name_recording", description: "Give the recording a title and a one-sentence summary.", parameters: .object([
            "type": "object",
            "properties": .object([
                "title": .object(["type": "string", "description": "short Korean title, about 20 characters"]),
                "summary": .object(["type": "string", "description": "one Korean sentence"]),
            ]),
            "required": .array(["title", "summary"]),
        ]))
    }

    static func prompt(transcript: String, startedAt: Double, duration: Double, timeZone: TimeZone) -> String {
        let recorded = "RECORDED: \(format(startedAt, "yyyy-MM-dd HH:mm", timeZone)) (\(RecordingText.duration(duration)))"
        let label = transcript.count > headChars ? "TRANSCRIPT (first \(headChars) characters):" : "TRANSCRIPT:"
        return [recorded, label, String(transcript.prefix(headChars))].joined(separator: "\n")
    }

    static func parse(_ data: Data) -> Naming? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let quotes = CharacterSet(charactersIn: "\"'“”‘’「」『』").union(.whitespacesAndNewlines)
        let title = (object["title"] as? String ?? "").trimmingCharacters(in: quotes)
        guard !title.isEmpty else { return nil }
        let summary = (object["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept: String? = (summary?.isEmpty ?? true) ? nil : summary
        return Naming(title: String(title.prefix(40)), summary: kept)
    }

    public static func fallbackTitle(startedAt: Double, timeZone: TimeZone) -> String {
        "녹음 " + format(startedAt, "yyyy-MM-dd HH-mm", timeZone)
    }

    /// 파일 이름: 날짜 + 제목 + .md. 쓸 수 없는 글자는 빼고, 제목에 이미 날짜가 있으면 한 번만
    public static func fileName(title: String, startedAt: Double, timeZone: TimeZone) -> String {
        let day = format(startedAt, "yyyy-MM-dd", timeZone)
        var base = sanitize(title)
        if base.isEmpty { base = fallbackTitle(startedAt: startedAt, timeZone: timeZone) }
        return (base.contains(day) ? base : "\(day) \(base)") + ".md"
    }

    /// `/ \ : * ? " < > |` 와 줄바꿈은 빈칸으로 바꾸고, 빈칸을 하나로, 앞뒤 점·빈칸은 뺀다 (60자까지)
    public static func sanitize(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let space: Unicode.Scalar = " "
        var scalars = String.UnicodeScalarView()
        for scalar in title.unicodeScalars { scalars.append(forbidden.contains(scalar) ? space : scalar) }
        let collapsed = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return String(trimmed.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    /// .md 본문: 제목, 녹음 시각과 길이, 요약, 받아쓴 글(발화마다 한 문단)
    public static func markdown(title: String, summary: String?, utterances: [String], startedAt: Double, duration: Double, timeZone: TimeZone) -> String {
        var lines: [String] = ["# \(title)", ""]
        lines.append("- 녹음: \(format(startedAt, "yyyy년 M월 d일 HH:mm", timeZone)), \(RecordingText.duration(duration))")
        if let summary, !summary.isEmpty { lines.append("- 요약: \(summary)") }
        lines += ["", "## 받아쓴 글", ""]
        lines.append(utterances.joined(separator: "\n\n"))
        return lines.joined(separator: "\n") + "\n"
    }

    /// 받아쓴 글 .md 를 folder 에 만든다. 같은 이름이 있으면 " (2)" 를 붙인다. 만든 파일 주소
    public static func write(_ recording: Recording, into folder: URL, timeZone: TimeZone) throws -> URL {
        let title = recording.title ?? fallbackTitle(startedAt: recording.startedAt, timeZone: timeZone)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = fileName(title: title, startedAt: recording.startedAt, timeZone: timeZone)
        let base = (name as NSString).deletingPathExtension
        var url = folder.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(counter)).md")
            counter += 1
        }
        let text = markdown(title: title, summary: recording.summary, utterances: recording.utterances,
                            startedAt: recording.startedAt, duration: recording.duration, timeZone: timeZone)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 폴더 추천에 넘기는 내용 발췌: 요약 + 받아쓴 글 앞 800자
    public static func excerpt(summary: String?, transcript: String) -> String {
        let head = String(transcript.replacingOccurrences(of: "\n", with: " ").prefix(excerptChars))
        guard let summary, !summary.isEmpty else { return head }
        return summary + "\n" + head
    }

    static func format(_ time: Double, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: Date(timeIntervalSince1970: time))
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter RecordingTitlerTests 2>&1 | tail -5`
Expected: 7 tests, 0 failures.

- [ ] **Step 5: 커밋**

```bash
git add Sources/WorkGraphCore/Recording/RecordingTitler.swift Tests/WorkGraphCoreTests/RecordingTitlerTests.swift
git commit -m "$(cat <<'EOF'
녹음 제목·요약(빠른 모델)과 받아쓴 글 .md 만들기: 파일 이름 정리, 같은 이름 번호, 내용 발췌

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: 폴더 추천이 받아쓴 녹음을 읽게 하기

**Files:**
- Modify: `Sources/WorkGraphCore/Files/FolderSuggester.swift` (`Context` 9-18, `suggest` 47-58, `system`·`tool` 151-170, `prompt` 172-177, `encodeContext`·`decodeContext` 198-207)
- Modify: `Sources/WorkGraphCore/Files/FileSuggestionCopy.swift`
- Modify: `Tests/WorkGraphCoreTests/OntologyBatcherTests.swift` (`StubLLM` 에 `lastSystem`)
- Test: `Tests/WorkGraphCoreTests/FolderSuggesterTests.swift`, `Tests/WorkGraphCoreTests/FileSuggestionCopyTests.swift` (추가)

**Interfaces:**
- Consumes: 없음 (기존 `FolderSuggester`, `FolderIndex`).
- Produces:
  - `FolderSuggester.Context.Kind`: `.download | .recording`.
  - `FolderSuggester.Context` init 끝에 `contentExcerpt: String? = nil, kind: Kind = .download` (기존 호출은 그대로 컴파일된다).
  - `FileSuggestionCopy.recordingTitle`, `recordingBody(fileName:folder:home:)`, `transcribedTitle`, `transcribedBody(fileName:folder:home:)`.
  - 테스트 도우미 `StubLLM.lastSystem: String`.

- [ ] **Step 1: StubLLM 이 시스템 프롬프트도 남기게 하기**

`Tests/WorkGraphCoreTests/OntologyBatcherTests.swift` 의 `StubLLM`:
- `private(set) var lastUser = ""` 다음 줄에 `private(set) var lastSystem = ""` 추가.
- `callFunction` 안 `lastUser = user` 다음 줄에 `lastSystem = system` 추가.

- [ ] **Step 2: 실패하는 테스트 쓰기**

`Tests/WorkGraphCoreTests/FolderSuggesterTests.swift` 클래스 안 끝에 추가:

```swift
    private func recordingText(_ name: String) throws -> String {
        let url = root.appendingPathComponent("Documents/Sillog 녹음/\(name)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# 녹음".utf8).write(to: url)
        return url.path
    }

    func testRecordingTranscriptIsFiledByWhatWasSaid() async throws {
        let dsFolder = root.appendingPathComponent("Desktop/5-1/자료구조").path
        let llm = StubLLM([.success(#"{"folder":"\#(dsFolder)","confidence":0.9,"reason":"자료구조 강의 녹음"}"#)])
        let suggester = FolderSuggester(db: db, llm: llm, home: root.path)
        let excerpt = "연결 리스트를 설명한 강의.\n오늘은 자료구조 3주차, 연결 리스트의 삽입과 삭제를 봅니다."
        let suggestion = try await suggester.suggest(filePath: try recordingText("2026-10-10 녹음 15-32.md"), originURL: nil, index: index,
                                                     context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 1_000,
                                                                                      contentExcerpt: excerpt, kind: .recording))
        XCTAssertEqual(try XCTUnwrap(suggestion).suggestedFolder, dsFolder)
        XCTAssertTrue(llm.lastSystem.contains("voice recording"))
        XCTAssertFalse(llm.lastSystem.contains("newly downloaded document"))
        XCTAssertTrue(llm.lastUser.contains("THIS FILE IS: the transcript of a voice recording the user just made"))
        XCTAssertTrue(llm.lastUser.contains("CONTENT (transcript excerpt): 연결 리스트를 설명한 강의. 오늘은 자료구조 3주차"))
        XCTAssertTrue(llm.lastUser.contains("~/Desktop/5-1/자료구조"), "내용 발췌가 후보를 끌어올린다")
        XCTAssertFalse(llm.lastUser.contains("ai 기초수학"), "내용과 맞지 않는 폴더는 후보에 없다")
    }

    func testARecordingNamedOnlyByDateHasNoCandidatesWithoutAnExcerpt() async throws {
        let llm = StubLLM([])
        let suggestion = try await FolderSuggester(db: db, llm: llm, home: root.path)
            .suggest(filePath: try recordingText("2026-10-10 녹음 15-32.md"), originURL: nil, index: index,
                     context: FolderSuggester.Context(recentTitles: [], openTasks: [], now: 1_000, kind: .recording))
        XCTAssertNil(suggestion)
        XCTAssertEqual(llm.calls, 0)
    }

    func testDownloadsKeepTheDownloadWording() async throws {
        let mathFolder = root.appendingPathComponent("Desktop/5-1/ai 기초수학").path
        let llm = StubLLM([.success(#"{"folder":"\#(mathFolder)","confidence":0.9,"reason":"r"}"#)])
        _ = try await FolderSuggester(db: db, llm: llm, home: root.path)
            .suggest(filePath: try download("week4.pdf"), originURL: nil, index: index,
                     context: FolderSuggester.Context(recentTitles: ["AI기초수학"], openTasks: [], now: 1_000))
        XCTAssertTrue(llm.lastSystem.contains("newly downloaded document"))
        XCTAssertFalse(llm.lastUser.contains("CONTENT (transcript excerpt)"))
        XCTAssertFalse(llm.lastUser.contains("THIS FILE IS"))
    }
```

`Tests/WorkGraphCoreTests/FileSuggestionCopyTests.swift` 클래스 안 끝에 추가:

```swift
    func testRecordingNotificationCopy() {
        let home = "/Users/me"
        XCTAssertEqual(FileSuggestionCopy.recordingTitle, "받아쓴 녹음을 정리할까요?")
        XCTAssertEqual(FileSuggestionCopy.recordingBody(fileName: "2026-10-10 자료구조 3주차 강의.md", folder: "/Users/me/Documents/학교/자료구조", home: home),
                       "'2026-10-10 자료구조 3주차 강의.md'를 문서 / 학교 / 자료구조 폴더로 옮겨 보세요.")
        XCTAssertEqual(FileSuggestionCopy.transcribedTitle, "녹음을 받아썼어요")
        XCTAssertEqual(FileSuggestionCopy.transcribedBody(fileName: "2026-10-10 회의.md", folder: "/Users/me/Documents/Sillog 녹음", home: home),
                       "'2026-10-10 회의.md'를 문서 / Sillog 녹음 폴더에 저장했어요.")
    }
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --filter "FolderSuggesterTests|FileSuggestionCopyTests" 2>&1 | tail -5`
Expected: 컴파일 실패 — `extra arguments at positions #6, #7 in call` (Context 에 `contentExcerpt`·`kind` 없음), `type 'FileSuggestionCopy' has no member 'recordingTitle'`.

- [ ] **Step 4: FolderSuggester 고치기**

`Context` 를 아래로 바꾼다:

```swift
    public struct Context: Sendable {
        /// 무엇을 정리하는지: 내려받은 파일 또는 받아쓴 녹음
        public enum Kind: String, Sendable { case download, recording }

        public var recentTitles: [String]         // 받기 직전 10분 동안 본 창 제목·주소 (녹음은 녹음하는 동안 본 것)
        public var screenText: String?            // 받기 직전 화면의 텍스트 앞부분 (강의 사이트의 과목명·주차 등)
        public var openTasks: [TaskDigest]
        public var currentTaskKey: String?
        public var now: Double
        /// 파일 내용 발췌 (받아쓴 녹음: 요약 + 받아쓴 글 앞부분)
        public var contentExcerpt: String?
        public var kind: Kind
        public init(recentTitles: [String], screenText: String? = nil, openTasks: [TaskDigest], currentTaskKey: String? = nil, now: Double,
                    contentExcerpt: String? = nil, kind: Kind = .download) {
            self.recentTitles = recentTitles; self.screenText = screenText; self.openTasks = openTasks; self.currentTaskKey = currentTaskKey; self.now = now
            self.contentExcerpt = contentExcerpt; self.kind = kind
        }
    }
```

`suggest` 안:
- `if let screenText = context.screenText { contextStrings.append(String(screenText.prefix(300))) }` 다음 줄에 추가:

```swift
        if let excerpt = context.contentExcerpt { contextStrings.append(String(excerpt.prefix(300))) }   // 받아쓴 글의 과목·주제가 후보 순위에 들어간다
```

- `let result = try await llm.callFunction(system: Self.system, user: prompt, tool: Self.tool)` → `let result = try await llm.callFunction(system: Self.system(for: context.kind), user: prompt, tool: Self.tool)`

`static let system = """ … """` 바로 아래에 추가:

```swift
    static let recordingSystem = """
    You file the transcript of a voice recording the user just made into one of the user's existing folders.
    Judge from what was said (CONTENT: the course, topic or project it is about), the file name, and what the user was looking at and working on while recording (window titles, recent tasks).
    CANDIDATES are real folders with a few of the files already inside. Pick the single best candidate: the folder of the same course, project or meeting series. Use the most specific folder that fits, not a parent.
    Earlier choices, if given, are hints about the user's habits, not rules.
    If no candidate clearly fits, return an empty folder with low confidence. Never invent a path: the folder must be copied exactly from CANDIDATES.
    Always answer by calling suggest_folder.
    """

    static func system(for kind: Context.Kind) -> String { kind == .recording ? recordingSystem : system }
```

`tool` 의 설명 `"Choose the folder the downloaded file belongs in."` → `"Choose the folder the file belongs in."`

`prompt` 의 앞부분(`var lines = ["FILE: \(fileName)"]` 부터 `USER WAS LOOKING AT` 줄까지)을 아래로 바꾼다:

```swift
        var lines = ["FILE: \(fileName)"]
        if context.kind == .recording { lines.append("THIS FILE IS: the transcript of a voice recording the user just made") }
        if let originURL { lines.append("DOWNLOADED FROM: \(originURL)") }
        if let excerpt = context.contentExcerpt, !excerpt.isEmpty {
            let flat = String(excerpt.replacingOccurrences(of: "\n", with: " ").prefix(800))
            lines.append("CONTENT (transcript excerpt): \(flat)")
        }
        if !context.recentTitles.isEmpty {
            let label = context.kind == .recording ? "USER WAS LOOKING AT WHILE RECORDING: " : "USER WAS LOOKING AT: "
            lines.append(label + context.recentTitles.prefix(12).joined(separator: " | "))
        }
```

(`TEXT ON SCREEN WHEN THE FILE ARRIVED` 줄부터 끝까지는 그대로 둔다.)

`encodeContext` 의 object 에 `"kind": context.kind.rawValue` 를 더하고, `decodeContext` 가 읽게 한다:

```swift
    static func encodeContext(_ context: Context) -> String? {
        let object: [String: Any] = ["titles": Array(context.recentTitles.prefix(12)), "tasks": context.openTasks.prefix(6).map(\.title),
                                     "task": context.currentTaskKey ?? "", "kind": context.kind.rawValue]
        return (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decodeContext(_ text: String) -> Context? {
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let task = object["task"] as? String
        let kind = Context.Kind(rawValue: object["kind"] as? String ?? "") ?? .download
        return Context(recentTitles: object["titles"] as? [String] ?? [], openTasks: [], currentTaskKey: (task?.isEmpty ?? true) ? nil : task, now: 0, kind: kind)
    }
```

- [ ] **Step 5: 알림 문구 더하기**

`Sources/WorkGraphCore/Files/FileSuggestionCopy.swift` 의 `title` 아래에 추가:

```swift
    /// 받아쓴 녹음의 폴더 제안 알림 (버튼은 옮기기·무시 그대로)
    public static let recordingTitle = "받아쓴 녹음을 정리할까요?"

    /// "'2026-10-10 자료구조 3주차 강의.md'를 문서 / 학교 / 자료구조 폴더로 옮겨 보세요." (.md 는 '엠디'로 읽어 '를')
    public static func recordingBody(fileName: String, folder: String, home: String) -> String {
        "'\(fileName)'를 \(folderLabel(folder, home: home)) 폴더로 옮겨 보세요."
    }

    /// 폴더 제안이 없을 때: 저장한 곳만 알린다
    public static let transcribedTitle = "녹음을 받아썼어요"

    public static func transcribedBody(fileName: String, folder: String, home: String) -> String {
        "'\(fileName)'를 \(folderLabel(folder, home: home)) 폴더에 저장했어요."
    }
```

- [ ] **Step 6: 통과 확인**

Run: `swift test --filter "FolderSuggesterTests|FileSuggestionCopyTests|OntologyBatcherTests" 2>&1 | tail -5`
Expected: 모두 통과.

- [ ] **Step 7: 커밋**

```bash
git add Sources/WorkGraphCore/Files Tests/WorkGraphCoreTests/FolderSuggesterTests.swift Tests/WorkGraphCoreTests/FileSuggestionCopyTests.swift Tests/WorkGraphCoreTests/OntologyBatcherTests.swift
git commit -m "$(cat <<'EOF'
폴더 추천: 받아쓴 녹음은 내용 발췌로 판단하고 녹음용 문구 쓰기

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 녹음 정리 파이프라인 (RecordingPipeline)

**Files:**
- Create: `Sources/WorkGraphCore/Recording/RecordingPipeline.swift`
- Test: `Tests/WorkGraphCoreTests/RecordingPipelineTests.swift` (새)

**Interfaces:**
- Consumes: `Recording`, `RecordingStore` (Task 1), `RecordingTitler`, `RecordingText` (Task 3), `FileSuggestion`·`FileSuggestionStore` (기존), 테스트의 `StubLLM`.
- Produces:
  - `public protocol Transcribing: Sendable { func transcribe(audio: URL, duration: Double, progress: @escaping @Sendable (Double) -> Void) async throws -> [String] }`
  - `public enum TranscriptionError: Error, Equatable, Sendable { case dictationDisabled, speechDenied, unavailable(String), failed(String) }` + `var message: String`.
  - `public struct RecordingPipeline: Sendable` — `enum Step: Equatable { case transcribing(Double), naming }`, `enum Outcome: Equatable { case ready(Recording), empty(Recording), failed(Recording, TranscriptionError) }`, `static let minDuration: Double = 1`, `init(db:transcriber:llm:textFolder:timeZone: = .current, clock: = now)`, `static func defaultTextFolder(home:) -> URL`(`~/Documents/Sillog 녹음`), `func prepareRetry(id: Int64, duration: Double? = nil) throws`, `func process(id: Int64, onStep: @escaping @Sendable (Step) -> Void = { _ in }, suggest: @escaping @Sendable (Recording, String) async -> FileSuggestion? = { _, _ in nil }) async throws -> Outcome`.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`Tests/WorkGraphCoreTests/RecordingPipelineTests.swift`:

```swift
import XCTest
@testable import WorkGraphCore

/// 순서대로 결과를 돌려주는 가짜 받아쓰기. 부를 때마다 진행률 0.5 를 한 번 알린다
final class FakeTranscriber: Transcribing, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<[String], TranscriptionError>]
    private(set) var calls = 0
    init(_ results: [Result<[String], TranscriptionError>]) { self.results = results }

    func transcribe(audio: URL, duration: Double, progress: @escaping @Sendable (Double) -> Void) async throws -> [String] {
        let next: Result<[String], TranscriptionError> = lock.withLock {
            calls += 1
            return results.isEmpty ? .failure(.failed("no stub")) : results.removeFirst()
        }
        progress(0.5)
        return try next.get()
    }
}

/// @Sendable 콜백이 남긴 값을 모은다
final class Collected<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Value] = []
    func append(_ value: Value) { lock.withLock { items.append(value) } }
    var values: [Value] { lock.withLock { items } }
}

/// 받아쓰기 → 제목·요약 → 받아쓴 글 .md → 폴더 추천 → ready, 그리고 실패·짧은 녹음·이어 하기
final class RecordingPipelineTests: XCTestCase {
    private var db: WGDatabase!
    private var folder: URL!
    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    private let naming = #"{"title":"자료구조 3주차 강의","summary":"연결 리스트를 설명한 강의."}"#

    /// 2026-10-10 15:32 (서울)
    private var start: Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 15, minute: 32))!.timeIntervalSince1970
    }

    override func setUpWithError() throws {
        db = try WGDatabase.inMemory()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("wg-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private var textFolder: URL { folder.appendingPathComponent("Sillog 녹음") }

    private func pipeline(_ transcriber: FakeTranscriber, _ llm: StubLLM) -> RecordingPipeline {
        RecordingPipeline(db: db, transcriber: transcriber, llm: llm, textFolder: textFolder, timeZone: seoul, clock: { 5_000 })
    }

    /// 끝난 녹음 (status transcribing). 녹음 파일도 만든다
    private func finished(duration: Double = 95) throws -> Recording {
        let audio = folder.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: audio)
        return try RecordingStore(db).insert(Recording(startedAt: start, endedAt: start + duration, duration: duration, audioPath: audio.path, status: .transcribing))
    }

    func testTranscribesNamesWritesTheTextFileSuggestsAFolderAndBecomesReady() async throws {
        let item = try finished()
        let llm = StubLLM([.success(naming)])
        let steps = Collected<RecordingPipeline.Step>()
        let excerpts = Collected<String>()
        let database = db!
        let outcome = try await pipeline(FakeTranscriber([.success(["오늘은 연결 리스트를 봅니다.", "노드는 값과 포인터를 가집니다."])]), llm)
            .process(id: item.id!, onStep: { steps.append($0) }, suggest: { recording, excerpt in
                excerpts.append(excerpt)
                return try? FileSuggestionStore(database).insert(FileSuggestion(ts: 5_000, path: recording.textPath!, fileName: "x.md", originUrl: nil,
                                                                                suggestedFolder: "/Users/me/학교/자료구조", confidence: 0.9, reason: "r", source: "llm"))
            })
        guard case .ready(let saved) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(saved.status, .ready)
        XCTAssertEqual(saved.readyAt, 5_000)
        XCTAssertEqual(saved.title, "자료구조 3주차 강의")
        XCTAssertEqual(saved.summary, "연결 리스트를 설명한 강의.")
        XCTAssertEqual(saved.transcript, "오늘은 연결 리스트를 봅니다.\n노드는 값과 포인터를 가집니다.")
        let path = try XCTUnwrap(saved.textPath)
        XCTAssertEqual((path as NSString).lastPathComponent, "2026-10-10 자료구조 3주차 강의.md")
        XCTAssertTrue(try String(contentsOfFile: path, encoding: .utf8).hasPrefix("# 자료구조 3주차 강의\n"))
        XCTAssertNotNil(saved.suggestionId)
        XCTAssertEqual(excerpts.values, ["연결 리스트를 설명한 강의.\n오늘은 연결 리스트를 봅니다. 노드는 값과 포인터를 가집니다."])
        XCTAssertEqual(steps.values, [.transcribing(0), .transcribing(0.5), .naming])
        XCTAssertEqual(try RecordingStore(db).find(id: item.id!), saved, "돌려준 값이 저장된 값")
    }

    func testDictationOffFailsKeepsTheAudioAndCanBeRetried() async throws {
        let item = try finished()
        let llm = StubLLM([.success(naming)])
        let runner = pipeline(FakeTranscriber([.failure(.dictationDisabled), .success(["다시 받아쓴 문장."])]), llm)
        let first = try await runner.process(id: item.id!)
        guard case .failed(let failed, .dictationDisabled) = first else { return XCTFail("\(first)") }
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.error, TranscriptionError.dictationDisabled.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.audioPath))
        XCTAssertEqual(llm.calls, 0)

        try runner.prepareRetry(id: item.id!)
        XCTAssertEqual(try RecordingStore(db).find(id: item.id!)?.status, .transcribing)
        let second = try await runner.process(id: item.id!)
        guard case .ready(let ready) = second else { return XCTFail("\(second)") }
        XCTAssertEqual(ready.transcript, "다시 받아쓴 문장.")
        XCTAssertNil(ready.error)
    }

    func testAShortRecordingIsReadyWithoutTranscriptionNamingOrAFile() async throws {
        let item = try finished(duration: 0.6)
        let transcriber = FakeTranscriber([.success(["들리면 안 됨"])])
        let llm = StubLLM([])
        let outcome = try await pipeline(transcriber, llm).process(id: item.id!)
        guard case .empty(let saved) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(transcriber.calls, 0)
        XCTAssertEqual(llm.calls, 0)
        XCTAssertNil(saved.textPath)
        XCTAssertEqual(saved.status, .ready)
        XCTAssertEqual(saved.title, "녹음 2026-10-10 15-32")
    }

    func testASilentRecordingMakesNoTextFile() async throws {
        let item = try finished()
        let llm = StubLLM([])
        let outcome = try await pipeline(FakeTranscriber([.success([])]), llm).process(id: item.id!)
        guard case .empty(let saved) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(llm.calls, 0)
        XCTAssertNil(saved.textPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: textFolder.path))
    }

    func testModelFailureFallsBackToTheDateTitle() async throws {
        let item = try finished()
        let outcome = try await pipeline(FakeTranscriber([.success(["회의 내용입니다."])]), StubLLM([.failure(.transport("offline"))])).process(id: item.id!)
        guard case .ready(let saved) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(saved.title, "녹음 2026-10-10 15-32")
        XCTAssertNil(saved.summary)
        XCTAssertEqual((saved.textPath! as NSString).lastPathComponent, "녹음 2026-10-10 15-32.md")
    }

    func testResumingSkipsTheStepsAlreadyDone() async throws {
        var item = try finished()
        let md = folder.appendingPathComponent("이미.md")
        try Data("# 이미".utf8).write(to: md)
        item.transcript = "이미 받아쓴 문장."
        item.title = "이미 지은 제목"
        item.textPath = md.path
        try RecordingStore(db).update(item)
        let transcriber = FakeTranscriber([])
        let llm = StubLLM([])
        let asked = Collected<String>()
        let outcome = try await pipeline(transcriber, llm).process(id: item.id!, suggest: { recording, _ in asked.append(recording.textPath ?? ""); return nil })
        guard case .ready(let saved) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(transcriber.calls, 0)
        XCTAssertEqual(llm.calls, 0)
        XCTAssertEqual(asked.values, [md.path], "폴더 추천만 다시 한다")
        XCTAssertEqual(saved.textPath, md.path)
    }

    func testProcessingAReadyRecordingChangesNothing() async throws {
        let ready = try RecordingStore(db).insert(Recording(startedAt: start, endedAt: start + 60, duration: 60, audioPath: "/a.m4a",
                                                             transcript: "가", status: .ready, readyAt: 100))
        let outcome = try await pipeline(FakeTranscriber([]), StubLLM([])).process(id: ready.id!)
        XCTAssertEqual(outcome, .ready(ready))
        XCTAssertEqual(try RecordingStore(db).find(id: ready.id!)?.readyAt, 100)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter RecordingPipelineTests 2>&1 | tail -5`
Expected: 컴파일 실패 — `cannot find type 'Transcribing' in scope`.

- [ ] **Step 3: 구현**

`Sources/WorkGraphCore/Recording/RecordingPipeline.swift`:

```swift
import Foundation

/// 녹음 파일 하나를 받아쓴다 (App 의 SpeechTranscriber, 테스트에서는 가짜)
public protocol Transcribing: Sendable {
    /// Args: audio 는 녹음 파일, duration 은 녹음 길이(초), progress 는 0~1 진행률을 받는다.
    /// Returns: 발화별 문장. 말소리가 없으면 빈 배열.
    /// Raises: TranscriptionError.
    func transcribe(audio: URL, duration: Double, progress: @escaping @Sendable (Double) -> Void) async throws -> [String]
}

public enum TranscriptionError: Error, Equatable, Sendable {
    /// 시스템 설정 → 키보드 → 받아쓰기가 꺼져 있음 (기기 안 인식이 kLSRErrorDomain 201 로 실패)
    case dictationDisabled
    /// 음성 인식 권한이 없음
    case speechDenied
    /// 이 Mac 에서 인식기를 쓸 수 없음 (언어 지원 등)
    case unavailable(String)
    case failed(String)

    public var message: String {
        switch self {
        case .dictationDisabled: "받아쓰기가 꺼져 있어요. 시스템 설정 → 키보드 → 받아쓰기를 켠 뒤 다시 받아쓰세요."
        case .speechDenied: "음성 인식 권한이 꺼져 있어요. 시스템 설정 → 개인정보 보호 및 보안 → 음성 인식에서 Sillog을 켜 주세요."
        case .unavailable(let reason): reason
        case .failed(let reason): "받아쓰지 못했어요: \(reason)"
        }
    }
}

/// 녹음 정리: 받아쓰기 → 제목·요약 → 받아쓴 글 .md → 폴더 추천 → ready.
/// 단계마다 DB 에 남기므로 앱이 꺼졌다 켜져도 끝난 단계는 건너뛴다 (받아쓴 글이 있으면 받아쓰기, .md 가 있으면 제목, 제안이 있으면 추천)
public struct RecordingPipeline: Sendable {
    /// 메뉴 막대에 보이는 단계
    public enum Step: Equatable, Sendable { case transcribing(Double), naming }

    public enum Outcome: Equatable, Sendable {
        /// 받아쓴 글 .md 까지 만들었다 (폴더 제안이 있으면 recording.suggestionId)
        case ready(Recording)
        /// 1초 미만이거나 받아쓴 글이 비었다: 이름·폴더 추천 없음
        case empty(Recording)
        /// 받아쓰기 실패: 녹음 파일은 남겨 둔다
        case failed(Recording, TranscriptionError)
    }

    /// 이보다 짧은 녹음은 받아쓰지 않는다 (초)
    public static let minDuration: Double = 1

    let store: RecordingStore
    let transcriber: any Transcribing
    let titler: RecordingTitler
    let textFolder: URL
    let timeZone: TimeZone
    let clock: @Sendable () -> Double

    public init(db: WGDatabase, transcriber: any Transcribing, llm: any LLMClient, textFolder: URL, timeZone: TimeZone = .current,
                clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.store = RecordingStore(db); self.transcriber = transcriber; self.titler = RecordingTitler(llm: llm)
        self.textFolder = textFolder; self.timeZone = timeZone; self.clock = clock
    }

    /// 받아쓴 글을 두는 기본 폴더: ~/Documents/Sillog 녹음
    public static func defaultTextFolder(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent("Documents", isDirectory: true).appendingPathComponent("Sillog 녹음", isDirectory: true)
    }

    /// 실패한 녹음을 다시 받아쓰게 되돌린다. duration: 다시 잰 녹음 길이 (앱이 꺼져 길이를 몰랐던 녹음)
    public func prepareRetry(id: Int64, duration: Double? = nil) throws {
        guard var recording = try store.find(id: id) else { throw CocoaError(.fileNoSuchFile) }
        recording.status = .transcribing
        recording.error = nil
        if let duration, recording.duration < Self.minDuration { recording.duration = duration }
        try store.update(recording)
    }

    /// Args: id 는 끝난 녹음(status transcribing). onStep 은 메뉴 막대 단계,
    ///   suggest 는 받아쓴 글 .md 의 폴더 제안을 만든다 (녹음 기록, 내용 발췌).
    /// Returns: 결과와 저장된 녹음 기록.
    /// Raises: DB·파일 쓰기 오류. 받아쓰기 실패는 Outcome.failed 로 돌려준다.
    public func process(id: Int64, onStep: @escaping @Sendable (Step) -> Void = { _ in },
                        suggest: @escaping @Sendable (Recording, String) async -> FileSuggestion? = { _, _ in nil }) async throws -> Outcome {
        guard var recording = try store.find(id: id) else { throw CocoaError(.fileNoSuchFile) }
        switch recording.status {
        case .transcribing: break
        case .ready: return recording.hasTranscript ? .ready(recording) : .empty(recording)
        case .failed: return .failed(recording, .failed(recording.error ?? ""))
        case .recording: throw CocoaError(.fileReadUnknown)               // 아직 녹음 중
        }

        // 1. 받아쓰기 (이미 받아쓴 글이나 .md 가 있으면 건너뛴다)
        if !recording.hasTranscript, recording.textPath == nil, recording.duration >= Self.minDuration {
            onStep(.transcribing(0))
            let gate = PercentGate()
            do {
                let audio = URL(fileURLWithPath: recording.audioPath)
                let utterances = try await transcriber.transcribe(audio: audio, duration: recording.duration) { progress in
                    if gate.advance(to: progress) { onStep(.transcribing(progress)) }
                }
                let lines = utterances.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                recording.transcript = lines.joined(separator: "\n")
                recording.error = nil
                try store.update(recording)
            } catch {
                let failure = (error as? TranscriptionError) ?? .failed(error.localizedDescription)
                recording.status = .failed
                recording.error = failure.message
                try store.update(recording)
                return .failed(recording, failure)
            }
        }

        // 2. 짧거나 소리가 없는 녹음: 이름·폴더 추천 없이 끝낸다
        guard recording.hasTranscript else {
            if recording.title == nil { recording.title = RecordingTitler.fallbackTitle(startedAt: recording.startedAt, timeZone: timeZone) }
            recording.status = .ready
            recording.readyAt = clock()
            try store.update(recording)
            return .empty(recording)
        }

        // 3. 제목·요약과 받아쓴 글 .md
        var announced = false
        if recording.textPath == nil {
            onStep(.naming)
            announced = true
            let naming = await titler.name(transcript: recording.transcript, startedAt: recording.startedAt, duration: recording.duration, timeZone: timeZone)
            recording.title = naming.title
            recording.summary = naming.summary
            recording.textPath = try RecordingTitler.write(recording, into: textFolder, timeZone: timeZone).path
            try store.update(recording)
        }

        // 4. 폴더 추천 (제안이 이미 있으면 건너뛴다)
        if recording.suggestionId == nil {
            if !announced { onStep(.naming) }
            let excerpt = RecordingTitler.excerpt(summary: recording.summary, transcript: recording.transcript)
            if let suggestion = await suggest(recording, excerpt) { recording.suggestionId = suggestion.id }
        }

        recording.status = .ready
        recording.readyAt = clock()
        try store.update(recording)
        return .ready(recording)
    }
}

/// 진행률을 1% 단위로만 넘긴다 (인식기는 중간 결과마다 부른다)
private final class PercentGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = 0

    func advance(to progress: Double) -> Bool {
        let percent = Int(progress * 100)
        return lock.withLock {
            guard percent > last else { return false }
            last = percent
            return true
        }
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter RecordingPipelineTests 2>&1 | tail -5`
Expected: 7 tests, 0 failures.

- [ ] **Step 5: 커밋**

```bash
git add Sources/WorkGraphCore/Recording/RecordingPipeline.swift Tests/WorkGraphCoreTests/RecordingPipelineTests.swift
git commit -m "$(cat <<'EOF'
녹음 정리 파이프라인: 받아쓰기 → 제목 → 받아쓴 글 .md → 폴더 추천, 끝난 단계는 건너뛰고 이어 하기

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: 정리(업무 연결)에 녹음 넣기

**Files:**
- Modify: `Sources/WorkGraphCore/Ontology/EventCompressor.swift` (`ActivityRow` 4-29, `merge` 95-135)
- Modify: `Sources/WorkGraphCore/Ontology/OntologyBatcher.swift:105-106`, `:153-157`
- Modify: `Sources/WorkGraphCore/Ontology/Staged/StagePrompts.swift:19-23` (`rowsGuide`), `Sources/WorkGraphCore/Ontology/OntologyPrompt.swift:10-12` (`system`)
- Modify: `Sources/WorkGraphCore/Ontology/TBox.swift:19-24`, `Sources/WorkGraphCore/Ontology/AssignmentApplier.swift:168-171`
- Modify: `Sources/WorkGraphCore/Ontology/TaskMerger.swift:128`, `:174`
- Modify: `Sources/WorkGraphCore/Storage/EventStore.swift:213` (`reopenBatches`)
- Modify: `Sources/wgctl/main.swift:499` (`rebuild-graph`)
- Test: `Tests/WorkGraphCoreTests/RecordingBatchTests.swift` (새)

**Interfaces:**
- Consumes: `Recording`, `RecordingStore.unprocessed/mark/assign` (Task 1), 테스트의 `StubLLM`, `BatchConfig.singleCall`(`OntologyBatcherTests.swift`).
- Produces:
  - `ActivityRow.recordingIds: [Int64]` (init 끝 인자 `recordingIds: [Int64] = []`).
  - `EventCompressor.merge(_ rows:, chats:, recordings: [Recording] = [], home:, fileExists:, snippetChars:)` — 녹음 행: app "녹음", appBundle `sillog.recording`, type `Recording`, uri `recording:<id>`, title = 제목, snippet = `"요약: <요약> 「<받아쓴 글 발췌>」"`, dwell 0, `isChat = true`, `recordingIds = [id]`.
  - `TBox.resourceTypes` 에 `("Recording", "참고자료")`.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`Tests/WorkGraphCoreTests/RecordingBatchTests.swift`:

```swift
import XCTest
import GRDB
@testable import WorkGraphCore

/// 받아쓴 녹음이 정리 행이 되고, 업무에 붙고, 업무가 합쳐지거나 다시 판정될 때 따라간다
final class RecordingBatchTests: XCTestCase {
    private func lecture(id: Int64? = 7, start: Double = 1_100, end: Double = 1_500) -> Recording {
        Recording(id: id, startedAt: start, endedAt: end, duration: end - start, audioPath: "/r/7.m4a", title: "자료구조 3주차 강의",
                  summary: "연결 리스트 강의.", transcript: "오늘은 연결 리스트를 봅니다.\n노드는 값과 포인터를 가집니다.", status: .ready, readyAt: end + 10)
    }

    func testARecordingBecomesAZeroDwellRowWithItsSummaryAndTranscript() {
        let window = [ActivityRow(row: 1, start: 1_000, end: 1_600, dwell: 600, app: "Chrome", appBundle: "com.google.Chrome", title: "자료구조 강의자료",
                                  uri: "https://lms.example/ds", type: "WebPage", projectKey: nil, projectTitle: nil, snippet: nil, observationIds: [1])]
        let rows = EventCompressor.merge(window, chats: [], recordings: [lecture()], home: "/Users/me", fileExists: { _ in false }, snippetChars: 300)
        XCTAssertEqual(rows.map(\.row), [1, 2])
        let row = rows[1]
        XCTAssertEqual(row.app, "녹음")
        XCTAssertEqual(row.appBundle, "sillog.recording")
        XCTAssertEqual(row.type, "Recording")
        XCTAssertEqual(row.uri, "recording:7")
        XCTAssertEqual(row.title, "자료구조 3주차 강의")
        XCTAssertEqual(row.dwell, 0, "창 기록과 겹치므로 작업 시간에 더하지 않는다")
        XCTAssertEqual(row.recordingIds, [7])
        XCTAssertTrue(row.isChat, "창 기록이 아닌 행: 앱 노드·화면 카드 없음")
        XCTAssertEqual(row.snippet, "요약: 연결 리스트 강의. 「오늘은 연결 리스트를 봅니다. 노드는 값과 포인터를 가집니다.」")
        XCTAssertEqual(rows.reduce(0) { $0 + $1.dwell }, 600)
    }

    func testARecordingWithoutTranscriptMakesNoRow() {
        var silent = lecture()
        silent.transcript = ""
        let window = [ActivityRow(row: 1, start: 1_000, end: 1_600, dwell: 600, app: "Chrome", appBundle: "com.google.Chrome", title: "t",
                                  uri: nil, type: nil, projectKey: nil, projectTitle: nil, snippet: nil, observationIds: [1])]
        XCTAssertEqual(EventCompressor.merge(window, chats: [], recordings: [silent], home: "/Users/me", fileExists: { _ in false }, snippetChars: 300).count, 1)
    }

    func testAReadyRecordingJoinsTheNextBatchOnceAndGetsItsTask() async throws {
        let db = try WGDatabase.inMemory()
        let store = EventStore(db)
        for (i, ts) in [100.0, 160, 400, 460].enumerated() {
            try store.insert(Observation(ts: ts, trigger: "app_activate", appBundle: "b\(i % 2)", appName: "App\(i % 2)", windowTitle: "w\(i % 2)"))
        }
        let recordings = RecordingStore(db)
        let ready = try recordings.insert(lecture(id: nil, start: 120, end: 380))
        let silent = try recordings.insert(Recording(startedAt: 130, endedAt: 131, duration: 0.5, audioPath: "/r/2.m4a", status: .ready, readyAt: 140))
        let llm = StubLLM([.success("""
        {"tasks":[{"ref":"A","match":"new","title":"자료구조 공부","task_type":"강의수강"}],"rows":[{"rows":"1-5","task":"A"}],"work":[{"task":"A","summary":"s","topics":[]}]}
        """), .success("""
        {"tasks":[{"ref":"A","match":"new","title":"다른 작업","task_type":"기타"}],"rows":[{"rows":"1-2","task":"A"}],"work":[{"task":"A","summary":"s","topics":[]}]}
        """)])
        let batcher = OntologyBatcher(db: db, llm: llm, config: .singleCall, home: "/Users/me", fileExists: { _ in false }, clock: { 2_000 })
        guard case .ok = await batcher.runIfDue(force: true) else { return XCTFail("첫 배치가 성공해야 한다") }
        XCTAssertTrue(llm.lastUser.contains("| 0s | 녹음 | Recording | 자료구조 3주차 강의 | recording:\(ready.id!)"), llm.lastUser)
        XCTAssertTrue(llm.lastUser.contains("text: 요약: 연결 리스트 강의. 「오늘은 연결 리스트를 봅니다."))
        XCTAssertFalse(llm.lastUser.contains("recording:\(silent.id!)"), "받아쓴 글이 없는 녹음은 넣지 않는다")

        let used = try XCTUnwrap(recordings.find(id: ready.id!))
        XCTAssertNotNil(used.batchId)
        let taskId = try await db.writer.read { try Int64.fetchOne($0, sql: "SELECT id FROM nodes WHERE label = 'Task' AND title = '자료구조 공부'") }
        XCTAssertEqual(used.taskId, taskId)
        let resource = try await db.writer.read { try GraphTx($0).node(label: NodeLabel.resource, key: "recording:\(ready.id!)") }
        XCTAssertEqual(resource?.subtype, "Recording")
        let appNode = try await db.writer.read { try GraphTx($0).node(label: NodeLabel.app, key: "sillog.recording") }
        XCTAssertNil(appNode, "녹음은 앱 노드로 만들지 않는다")
        XCTAssertTrue(try recordings.unprocessed(upTo: 10_000, notOlderThan: 0).isEmpty)

        // 두 번째 배치에는 다시 들어가지 않는다
        try store.insert(Observation(ts: 900, trigger: "app_activate", appBundle: "b9", appName: "App9"))
        try store.insert(Observation(ts: 960, trigger: "app_activate", appBundle: "b8", appName: "App8"))
        guard case .ok = await batcher.runIfDue(force: true) else { return XCTFail("둘째 배치가 성공해야 한다") }
        XCTAssertFalse(llm.lastUser.contains("Recording"))
    }

    func testMergingAndRetiringTasksMoveTheRecordingsTask() throws {
        let db = try WGDatabase.inMemory()
        let (keep, victim, game) = try db.writer.write { conn -> (Int64, Int64, Int64) in
            let tx = GraphTx(conn)
            return (try tx.upsertNode(label: NodeLabel.task, key: "t_keep", subtype: nil, title: "남는 업무", props: ["status": "active"], at: 0),
                    try tx.upsertNode(label: NodeLabel.task, key: "t_victim", subtype: nil, title: "사라지는 업무", props: ["status": "active"], at: 0),
                    try tx.upsertNode(label: NodeLabel.task, key: "t_game", subtype: nil, title: "게임 리그", props: ["status": "active"], at: 0))
        }
        let recordings = RecordingStore(db)
        let merged = try recordings.insert(Recording(startedAt: 1, audioPath: "/a", transcript: "가", status: .ready, taskId: victim))
        let retired = try recordings.insert(Recording(startedAt: 2, audioPath: "/b", transcript: "나", status: .ready, taskId: game))
        try db.writer.write { conn in
            _ = try TaskMerger.merge(TaskMerger.Group(keep: "t_keep", merge: ["t_victim"]), conn: conn, now: 10)
            _ = try TaskMerger.retire("t_game", conn: conn, now: 10)
        }
        XCTAssertEqual(try recordings.find(id: merged.id!)?.taskId, keep)
        XCTAssertNil(try recordings.find(id: retired.id!)?.taskId)
    }

    func testReopeningABatchSendsItsRecordingsBackToTheQueue() throws {
        let db = try WGDatabase.inMemory()
        let recordings = RecordingStore(db)
        let recording = try recordings.insert(Recording(startedAt: 100, endedAt: 200, duration: 100, audioPath: "/a", transcript: "가나다",
                                                         status: .ready, readyAt: 210, batchId: 5, taskId: 9))
        _ = try EventStore(db).reopenBatches([5])
        let reopened = try XCTUnwrap(recordings.find(id: recording.id!))
        XCTAssertNil(reopened.batchId)
        XCTAssertNil(reopened.taskId)
    }

    func testBothJudgmentPromptsExplainRecordingRows() {
        let line = #"Rows whose app is "녹음" (type Recording, dwell 0)"#
        XCTAssertTrue(StagePrompt.classifySystem.contains(line))
        XCTAssertTrue(OntologyPrompt.system.contains(line))
    }

    func testARecordingIsAReferenceResourceByDefault() {
        XCTAssertTrue(TBox.resourceTypes.contains { $0.name == "Recording" && $0.parent == "참고자료" })
        let row = ActivityRow(row: 1, start: 0, end: 0, dwell: 0, app: "녹음", appBundle: "sillog.recording", title: "회의", uri: "recording:1",
                              type: "Recording", projectKey: nil, projectTitle: nil, snippet: nil, observationIds: [])
        XCTAssertTrue(AssignmentApplier.defaultResource(row))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter RecordingBatchTests 2>&1 | tail -5`
Expected: 컴파일 실패 — `extra argument 'recordings' in call`, `value of type 'ActivityRow' has no member 'recordingIds'`.

- [ ] **Step 3: 행에 녹음 id 더하기**

`Sources/WorkGraphCore/Ontology/EventCompressor.swift` 의 `ActivityRow`:
- `isChat` 위 주석을 `/// 창 기록이 아닌 행인지: AI 도구와의 대화 또는 녹음 (체류시간 없음, 시간 집계·앱 노드·화면 카드에 들어가지 않음)` 로 바꾼다.
- `public var chatMessageIds: [Int64] = []` 다음에 추가:

```swift
    /// 이 행에 들어간 녹음 id (처리 완료 표시용)
    public var recordingIds: [Int64] = []
```

- init 을 아래로 바꾼다:

```swift
    public init(row: Int, start: Double, end: Double, dwell: Int, app: String, appBundle: String, title: String?, uri: String?, type: String?,
                projectKey: String?, projectTitle: String?, snippet: String?, observationIds: [Int64], isChat: Bool = false, chatMessageIds: [Int64] = [],
                recordingIds: [Int64] = []) {
        self.row = row; self.start = start; self.end = end; self.dwell = dwell; self.app = app; self.appBundle = appBundle
        self.title = title; self.uri = uri; self.type = type; self.projectKey = projectKey; self.projectTitle = projectTitle
        self.snippet = snippet; self.observationIds = observationIds; self.isChat = isChat; self.chatMessageIds = chatMessageIds
        self.recordingIds = recordingIds
    }
```

- [ ] **Step 4: merge 가 녹음을 행으로 만들게 하기**

`merge` 위의 주석 두 줄(`/// AI 대화를 행으로 끼워 넣는다. …`)부터 `func clamp` 줄까지를 아래로 바꾼다:

```swift
    /// AI 대화와 받아쓴 녹음을 행으로 끼워 넣는다. 같은 세션의 메시지는 한 행, 녹음은 한 건에 한 행.
    /// 체류시간은 0 이라 앱 시간 집계를 건드리지 않는다 (녹음은 창 기록과 겹친다). 창보다 오래된 것은 창 시작 시각에 놓는다.
    /// 사용자가 AI 에게 한 말은 업무 의도를 그대로 담고 있어서 LLM 이 업무 제목·주제를 잡는 데 가장 강한 단서다.
    public static func merge(_ rows: [ActivityRow], chats: [ChatMessage], recordings: [Recording] = [], home: String, fileExists: (String) -> Bool,
                             snippetChars: Int) -> [ActivityRow] {
        guard !chats.isEmpty || !recordings.isEmpty else { return rows }
        // 늦게 읽힌 메시지(창보다 오래된 것)는 창 시작 시각에 놓는다. 세션 시작이 과거로 밀리는 것을 막는다.
        let extraStarts: [Double] = chats.map(\.ts) + recordings.map(\.startedAt)
        let extraEnds: [Double] = chats.map(\.ts) + recordings.map { $0.endedAt ?? $0.startedAt }
        let windowStart = rows.map(\.start).min() ?? extraStarts.min() ?? 0
        let windowEnd = rows.map(\.end).max() ?? extraEnds.max() ?? windowStart
        func clamp(_ ts: Double) -> Double { min(max(ts, windowStart), windowEnd) }
```

`chatRows.removeAll { $0.snippet?.isEmpty ?? true }` 와 `var merged = rows + chatRows` 사이에 추가하고, `var merged` 줄을 바꾼다:

```swift
        // 녹음: 받아쓴 글이 있는 것만. 요약 + 받아쓴 글 앞부분을 text: 로
        let recordingRows: [ActivityRow] = recordings.compactMap { recording in
            guard let id = recording.id, recording.hasTranscript else { return nil }
            let excerpt = makeSnippet(recording.transcript, limit: snippetChars * 2)
            var parts: [String] = []
            if let summary = recording.summary, !summary.isEmpty { parts.append("요약: " + makeSnippet(summary, limit: 200)) }
            if !excerpt.isEmpty { parts.append("「\(excerpt)」") }
            let start = clamp(recording.startedAt)
            let end = max(clamp(recording.endedAt ?? recording.startedAt), start)
            return ActivityRow(row: 0, start: start, end: end, dwell: 0, app: "녹음", appBundle: "sillog.recording",
                               title: recording.title ?? "녹음", uri: "recording:\(id)", type: "Recording",
                               projectKey: nil, projectTitle: nil, snippet: parts.joined(separator: " "), observationIds: [],
                               isChat: true, recordingIds: [id])
        }
        var merged = rows + chatRows + recordingRows
```

- [ ] **Step 5: 배치가 녹음을 합치고 표시·배정하게 하기**

`Sources/WorkGraphCore/Ontology/OntologyBatcher.swift:105-106` 을 아래로 바꾼다:

```swift
        let chats = (try? store.unprocessedChatMessages(upTo: windowEnd, notOlderThan: first.ts - 24 * 3600)) ?? []
        // 창 끝까지 끝난 받아쓴 녹음 (24시간 이내, 아직 어느 배치에도 안 들어간 것)
        let recordings = (try? RecordingStore(db).unprocessed(upTo: windowEnd, notOlderThan: first.ts - 24 * 3600)) ?? []
        let rows = EventCompressor.merge(compressed, chats: chats, recordings: recordings, home: home, fileExists: fileExists, snippetChars: config.snippetChars)
```

같은 파일 반영 트랜잭션(`try EventStore.markChats(...)` 와 `for item in assignments` 블록)을 아래로 바꾼다:

```swift
                try EventStore.markChats(conn, ids: rows.flatMap(\.chatMessageIds), batchId: batchId)
                try RecordingStore.mark(conn, ids: rows.flatMap(\.recordingIds), batchId: batchId)
                for item in assignments {
                    try EventStore.assign(conn, observationIds: item.row.observationIds, taskId: item.taskId, relevant: item.resource, offTask: item.offTask, reason: item.reason)
                    try EventStore.assignChats(conn, ids: item.row.chatMessageIds, taskId: item.taskId)
                    try RecordingStore.assign(conn, ids: item.row.recordingIds, taskId: item.taskId)
                }
```

- [ ] **Step 6: 판정 프롬프트에 녹음 행 설명 한 줄**

`Sources/WorkGraphCore/Ontology/Staged/StagePrompts.swift` 의 `rowsGuide` 와 `Sources/WorkGraphCore/Ontology/OntologyPrompt.swift` 의 `system` 에서, `      Rows whose app is "Claude Code"` 로 시작하는 줄 바로 다음에 같은 들여쓰기로 이 줄을 넣는다:

```text
      Rows whose app is "녹음" (type Recording, dwell 0) are voice recordings the user made in Sillog, such as a lecture, a meeting or a memo. `text:` holds a summary and the start of what was said. Judge them by what was said, like content the user engaged with.
```

- [ ] **Step 7: 자료 종류와 기본 자료 판단**

`Sources/WorkGraphCore/Ontology/TBox.swift` 의 `("Video", "참고자료"), ("AIChat", "참고자료"), ("WebPage", "참고자료"),` → `("Video", "참고자료"), ("AIChat", "참고자료"), ("WebPage", "참고자료"), ("Recording", "참고자료"),`

`Sources/WorkGraphCore/Ontology/AssignmentApplier.swift` 의 `defaultResource` 목록에 `"Recording"` 을 더한다:

```swift
        return ["CodeFile", "Document", "Design", "Note", "AIChat", "Documentation", "QnA", "Paper", "Video", "Recording"].contains(row.type ?? "")
```

- [ ] **Step 8: 업무 합치기·없애기, 다시 판정, 그래프 다시 만들기**

`Sources/WorkGraphCore/Ontology/TaskMerger.swift:128` (`UPDATE chat_messages SET task_id = ? WHERE task_id = ?`) 다음 줄에 추가:

```swift
            try conn.execute(sql: "UPDATE recordings SET task_id = ? WHERE task_id = ?", arguments: [keep.id, victim.id])
```

같은 파일 `:174` (`UPDATE chat_messages SET task_id = NULL WHERE task_id = ?`) 다음 줄에 추가:

```swift
        try conn.execute(sql: "UPDATE recordings SET task_id = NULL WHERE task_id = ?", arguments: [task.id])
```

`Sources/WorkGraphCore/Storage/EventStore.swift` `reopenBatches` 의 `UPDATE chat_messages SET batch_id = NULL, task_id = NULL WHERE batch_id IN (\(list))` 다음 줄에 추가:

```swift
            try conn.execute(sql: "UPDATE recordings SET batch_id = NULL, task_id = NULL WHERE batch_id IN (\(list))")
```

`Sources/wgctl/main.swift` `rebuild-graph` 의 `UPDATE chat_messages SET batch_id = NULL, task_id = NULL` 다음 줄에 추가:

```swift
            try conn.execute(sql: "UPDATE recordings SET batch_id = NULL, task_id = NULL")
```

- [ ] **Step 9: 통과 확인**

Run: `swift test --filter "RecordingBatchTests|EventCompressorTests|OntologyBatcherTests|ChatLogTests|ChatBatchTests|ThemeTests|GoalAndRejudgeTests|StagedPipelineTests|LedgerTests" 2>&1 | tail -5`
Expected: 모두 통과. 그리고 `swift build 2>&1 | tail -3` → `Build complete!` (wgctl 포함).

- [ ] **Step 10: 커밋**

```bash
git add Sources/WorkGraphCore/Ontology Sources/WorkGraphCore/Storage/EventStore.swift Sources/wgctl/main.swift Tests/WorkGraphCoreTests/RecordingBatchTests.swift
git commit -m "$(cat <<'EOF'
정리에 받아쓴 녹음 넣기: 녹음 행(체류 0), 업무 배정, 업무 합치기·다시 판정 때 따라가기

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: 채팅에서 녹음 찾고 읽고 인용하기

**Files:**
- Modify: `Sources/WorkGraphCore/Chat/ContextSearch.swift` (`search` 156-159 다음, `read` 217-227·230-260, 끝에 도우미)
- Modify: `Sources/WorkGraphCore/Chat/ChatTools.swift:46-47`
- Modify: `Sources/WorkGraphCore/Chat/Prompts/chat-system-prompt.md:23`, `:101`
- Modify: `Sources/WorkGraphApp/Views/ChatMessageText.swift:10`
- Test: `Tests/WorkGraphCoreTests/RecordingSearchTests.swift` (새), `Tests/WorkGraphAppTests/RecordingCitationTests.swift` (새)

**Interfaces:**
- Consumes: `recordings`·`recordings_fts` (Task 1), `RecordingText.duration` (Task 3).
- Produces: 채팅 출처 id `recording:<id>` — 제목 `"녹음 · <제목>"`, location = 받아쓴 글 `.md` 경로(없으면 ""), excerpt 첫 줄 = `"<날짜> 녹음 (<길이>) · 이 Mac 의 음성 인식으로 받아쓴 글 …"`, 둘째 줄 = `"요약: <요약>"`. `read("recording:<id>", start:)` 는 받아쓴 글을 18,000자씩.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`Tests/WorkGraphCoreTests/RecordingSearchTests.swift`:

```swift
import XCTest
@testable import WorkGraphCore

/// 채팅의 기록 검색: 받아쓴 녹음을 찾고 읽는다. 프로젝트 전용 업무의 녹음은 그 프로젝트 안에서만
final class RecordingSearchTests: XCTestCase {
    func testRecordingsAreFoundAndReadOnlyWhereTheirTaskIsVisible() throws {
        let db = try WGDatabase.inMemory()
        let taskId = try db.writer.write { conn in
            try GraphTx(conn).upsertNode(label: NodeLabel.task, key: "t_ds", subtype: nil, title: "자료구조", props: ["status": "active"], at: 0)
        }
        let recordings = RecordingStore(db)
        let lecture = try recordings.insert(Recording(startedAt: 1_000, endedAt: 1_600, duration: 600, audioPath: "/r/1.m4a",
                                                       textPath: "/Users/me/Documents/학교/자료구조/강의.md", title: "자료구조 3주차 강의",
                                                       summary: "연결 리스트 강의.", transcript: "오늘은 연결리스트의 삽입과 삭제를 봅니다.\n다음 시간에는 스택입니다.",
                                                       status: .ready, readyAt: 1_700, taskId: taskId))
        _ = try recordings.insert(Recording(startedAt: 2_000, audioPath: "/r/2.m4a", transcript: "연결리스트 이야기", status: .transcribing))   // 정리 중인 것은 안 보인다

        let found = try ContextSearch(db).search(query: "연결리스트", from: 0, to: 10_000).filter { $0.id.hasPrefix("recording:") }
        XCTAssertEqual(found.map(\.id), ["recording:\(lecture.id!)"])
        XCTAssertEqual(found.first?.title, "녹음 · 자료구조 3주차 강의")
        XCTAssertEqual(found.first?.location, "/Users/me/Documents/학교/자료구조/강의.md")
        XCTAssertTrue(found.first?.excerpt.contains("요약: 연결 리스트 강의.") ?? false)
        XCTAssertTrue(found.first?.excerpt.contains("받아쓴 글") ?? false)

        let read = try XCTUnwrap(ContextSearch(db).read("recording:\(lecture.id!)").first)
        XCTAssertTrue(read.excerpt.contains("다음 시간에는 스택입니다."))
        XCTAssertTrue(read.excerpt.contains("[전체 "))

        // 업무를 프로젝트 전용으로 옮기면 프로젝트 밖에서는 찾지도 읽지도 못한다
        let projects = ProjectStore(db)
        var project = ChatProject(title: "전용", goal: "분리")
        project.memoryMode = .projectOnly
        try projects.save(project)
        try projects.move("task:\(taskId)", to: project.id)
        XCTAssertTrue(try ContextSearch(db).search(query: "연결리스트", from: 0, to: 10_000).filter { $0.id.hasPrefix("recording:") }.isEmpty)
        XCTAssertTrue(try ContextSearch(db).read("recording:\(lecture.id!)").isEmpty)
        let inside = try ContextSearch(db, projectID: project.id).search(query: "연결리스트", from: 0, to: 10_000).filter { $0.id.hasPrefix("recording:") }
        XCTAssertEqual(inside.count, 1)
    }

    func testRecordingsAreLeftOutWhenActivityRecordsAreOff() throws {
        let db = try WGDatabase.inMemory()
        let recording = try RecordingStore(db).insert(Recording(startedAt: 1_000, endedAt: 1_100, duration: 100, audioPath: "/r/1.m4a",
                                                                 title: "회의", transcript: "분기 목표를 정했습니다.", status: .ready, readyAt: 1_200))
        let search = ContextSearch(db, includeActivity: false)
        XCTAssertTrue(try search.search(query: "분기 목표", from: 0, to: 10_000).filter { $0.id.hasPrefix("recording:") }.isEmpty)
        XCTAssertTrue(try search.read("recording:\(recording.id!)").isEmpty)
    }

    func testTheChatPromptNamesRecordingSources() throws {
        let template = try ChatSystemPrompt.template()
        XCTAssertTrue(template.contains("message:, recording:, library:"))
        XCTAssertTrue(template.contains("Voice recordings (recording:)"))
    }
}
```

`Tests/WorkGraphAppTests/RecordingCitationTests.swift`:

```swift
import XCTest
@testable import WorkGraphApp
@testable import WorkGraphCore

/// 채팅 답의 [recording:N] 인용이 근거 칩이 된다
final class RecordingCitationTests: XCTestCase {
    func testRecordingCitationsBecomeSourceChips() {
        let source = ChatSource(id: "recording:7", title: "녹음 · 자료구조 3주차 강의", location: "/Users/me/Documents/학교/자료구조/강의.md", excerpt: "…")
        let (body, cited, missing) = ChatMessageText.citations(in: "연결 리스트는 3주차에 다뤘어요. [recording:7]", sources: [source])
        XCTAssertEqual(body, "연결 리스트는 3주차에 다뤘어요.")
        XCTAssertEqual(cited.map(\.id), ["recording:7"])
        XCTAssertFalse(missing)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter "RecordingSearchTests|RecordingCitationTests" 2>&1 | tail -8`
Expected: FAIL — `XCTAssertEqual failed: ("[]") is not equal to ("["recording:1"]")`, 프롬프트 두 줄 없음, 인용 칩 `cited` 가 비어 있음. (`testRecordingsAreLeftOutWhenActivityRecordsAreOff` 는 지금도 통과한다. 새 출처가 활동 기록 끄기를 따르는지 지키는 테스트다.)

- [ ] **Step 3: 검색에 녹음 출처 더하기**

`Sources/WorkGraphCore/Chat/ContextSearch.swift` `search` 의 chat 블록(`for row in try Row.fetchAll(conn, sql: "SELECT * FROM chat_messages …") { … }`) 바로 다음, `let filter = try conversationFilter(conn)` 앞에 추가:

```swift
            // 받아쓴 녹음: 제목·요약·받아쓴 글. 업무 접근 범위를 AI 도구 대화처럼 따른다
            let recording = Self.match(needle, index: "recordings_fts", row: "id", fallback: "COALESCE(title, '') || ' ' || COALESCE(summary, '') || ' ' || transcript")
            for row in try Row.fetchAll(conn, sql: """
                SELECT id, started_at, duration, title, summary, transcript, text_path FROM recordings
                WHERE status = 'ready' AND trim(transcript) != '' AND started_at <= ? AND COALESCE(ended_at, started_at) >= ?
                  AND (\(recording.0))\(Self.taskRestriction("task_id", access))\(activity)
                ORDER BY started_at DESC LIMIT 6
                """, arguments: [to, from, recording.1]) {
                results.append(Self.recordingSource(row, needle: needle))
            }
```

`read` 의 접근 확인 `switch pieces[0]` 에서 `case "chat": …` 다음 줄에 추가:

```swift
                case "recording":
                    allowed = try Bool.fetchOne(conn, sql: "SELECT EXISTS(SELECT 1 FROM recordings WHERE id = ?\(Self.taskRestriction("task_id", access)))", arguments: [id]) == true
```

`read` 의 본문 `switch pieces[0]` 에서 `case "digest":` 블록 다음, `default: return []` 앞에 추가:

```swift
            case "recording":
                guard let row = try Row.fetchOne(conn, sql: "SELECT * FROM recordings WHERE id = ? AND status = 'ready'", arguments: [id]) else { return [] }
                let transcript: String = row["transcript"]
                let title: String? = row["title"]
                let offset = max(1, start)
                let page = String(transcript.dropFirst(offset - 1).prefix(18000))
                let footer = "[전체 \(transcript.count)자 · 다음 시작 위치 \(offset + page.count)]"
                return [.init(id: sourceID, title: "녹음 · \(title ?? "제목 없음")", location: row["text_path"] ?? "",
                              excerpt: Self.recordingHeader(row) + "\n\n" + page + "\n" + footer)]
```

같은 파일 `private static func date(_ time: Double)` 위에 도우미를 추가:

```swift
    /// 녹음 출처 머리: 녹음 시각·길이, 받아쓴 글이라는 표시, 요약
    private static func recordingHeader(_ row: Row) -> String {
        let startedAt: Double = row["started_at"], duration: Double = row["duration"]
        let summary: String? = row["summary"]
        var header = "\(date(startedAt)) 녹음 (\(RecordingText.duration(duration))) · 이 Mac 의 음성 인식으로 받아쓴 글 (잘못 들은 단어가 있을 수 있음)"
        if let summary, !summary.isEmpty { header += "\n요약: \(summary)" }
        return header
    }

    /// 녹음 검색 결과: 받아쓴 글에서 검색어가 처음 나온 곳 앞뒤
    private static func recordingSource(_ row: Row, needle: String) -> ChatSource {
        let transcript: String = row["transcript"]
        let words = needle.split(whereSeparator: \.isWhitespace).map(String.init)
        let range = words.compactMap { transcript.range(of: $0, options: .caseInsensitive) }.first
        let start = range.map { transcript.distance(from: transcript.startIndex, to: $0.lowerBound) } ?? 0
        let id: Int64 = row["id"]
        let title: String? = row["title"]
        let body = String(transcript.dropFirst(max(0, start - 200)).prefix(1400))
        return .init(id: "recording:\(id)", title: "녹음 · \(title ?? "제목 없음")", location: row["text_path"] ?? "",
                     excerpt: recordingHeader(row) + "\n" + body)
    }
```

- [ ] **Step 4: 채팅 도구 설명과 시스템 프롬프트**

`Sources/WorkGraphCore/Chat/ChatTools.swift`:
- `search_context` 설명 `"허용된 업무·대화·결과물의 전체 기록을 검색한다. …"` → `"허용된 업무·대화·결과물·녹음의 전체 기록을 검색한다. …"` (뒤 문장은 그대로).
- `read_context` 의 `"start"` 설명 `"대화는 시작 메시지 번호, 메시지는 시작 문자 위치. 처음이면 1"` → `"대화는 시작 메시지 번호, 메시지·녹음은 시작 문자 위치. 처음이면 1"`.

`Sources/WorkGraphCore/Chat/Prompts/chat-system-prompt.md`:
- `- Weekly and monthly digests (digest:): …` 줄 다음에 추가:

```text
- Voice recordings (recording:): lectures, meetings, and memos the user recorded in Sillog, transcribed on this Mac. They are original material for what was said, but speech recognition can mishear names, numbers, and technical terms.
```

- 인용 규칙 줄의 `IDs start with node:, observation:, card:, digest:, usage:, chat:, conversation:, message:, library:,` → `IDs start with node:, observation:, card:, digest:, usage:, chat:, conversation:, message:, recording:, library:,` (나머지는 그대로).

- [ ] **Step 5: 인용 패턴**

`Sources/WorkGraphApp/Views/ChatMessageText.swift:10` 의 패턴에 `recording` 을 더한다:

```swift
    private static let citationPattern = try! NSRegularExpression(pattern: #"\[((?:(?:node|observation|card|chat|conversation|message|library|file|git|gmail|drive|notion|digest|usage|recording):|https?://)[^\]\n]+)\]"#)
```

(근거 칩을 누르면 뜨는 출처 창은 location 이 `/` 로 시작하면 이미 [Finder에서 보기]를 보인다.)

- [ ] **Step 6: 통과 확인**

Run: `swift test --filter "RecordingSearchTests|RecordingCitationTests|ChatTests|LibraryTests|ConsolidatorTests" 2>&1 | tail -5`
Expected: 모두 통과.

- [ ] **Step 7: 커밋**

```bash
git add Sources/WorkGraphCore/Chat Sources/WorkGraphApp/Views/ChatMessageText.swift Tests/WorkGraphCoreTests/RecordingSearchTests.swift Tests/WorkGraphAppTests/RecordingCitationTests.swift
git commit -m "$(cat <<'EOF'
채팅: 받아쓴 녹음을 recording: 출처로 찾고 읽고 인용하기 (프로젝트 전용 범위 따름)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: 앱 녹음 엔진 (녹음기·받아쓰기·권한·AppState)

**Files:**
- Modify: `Sources/WorkGraphCollectors/Permissions.swift` (`Pane`, `openSettings`)
- Create: `Sources/WorkGraphApp/Recording/RecordingPermissions.swift`
- Create: `Sources/WorkGraphApp/Recording/VoiceRecorder.swift`
- Create: `Sources/WorkGraphApp/Recording/SpeechTranscriber.swift`
- Create: `Sources/WorkGraphApp/AppState+Recording.swift`
- Modify: `Sources/WorkGraphApp/AppState.swift` (상태 값 64·76 다음, init 125 다음, `start(_:)`, `makeQuickClient` 다음, `applySettings`)
- Modify: `Sources/WorkGraphApp/SuggestionNotifier.swift:37-57` (`notify`)
- Test: `Tests/WorkGraphAppTests/RecordingFlowTests.swift` (새)

**Interfaces:**
- Consumes: `Recording`, `RecordingStore` (Task 1), `TranscriptCollector` (Task 2), `RecordingPipeline`, `Transcribing`, `TranscriptionError` (Task 5), `FolderSuggester.Context(…, contentExcerpt:, kind:)`, `FileSuggestionCopy.recordingTitle/recordingBody/transcribedTitle/transcribedBody` (Task 4).
- Produces (App, internal):
  - `struct ActiveRecording: Equatable { let id: Int64; let startedAt: Double }`
  - `enum RecordingProblem: Equatable { case notBundled, microphone, speech, dictation, failed(String) }` — `init(_ error: TranscriptionError)`, `var text: String`, `var settingsURL: URL?`, `func openSettings()`.
  - `@MainActor protocol RecordingPermissions { func check() async -> RecordingProblem? }`, `struct SystemRecordingPermissions`.
  - `@MainActor protocol AudioRecording: AnyObject { func start(to url: URL) throws; func stop() -> Double }`, `final class VoiceRecorder`, `enum AudioFileInfo { static func duration(of url: URL) -> Double? }`.
  - `struct SpeechTranscriber: Transcribing` — `enum ErrorKind { dictationOff, noSpeech, other }`, `static func kind(of error: Error) -> ErrorKind`.
  - `AppState` 상태: `@Published var activeRecording: ActiveRecording?`, `@Published var recordingWork: RecordingPipeline.Step?`, `@Published var recordingProblem: RecordingProblem?`, `@Published var recordings: [Recording]`, `var recordingPipeline: RecordingPipeline?`, `var recorder: any AudioRecording`, `var recordingPermissions: any RecordingPermissions`, `var recordingQueue: Task<Void, Never>?`, `var recordingStepToken: Int`.
  - `AppState` 동작: `refreshRecordings()`, `startRecording() async`, `stopRecording() async`, `finishRecordingOnQuit()`, `retranscribe(_:) async`, `resumeRecordings() async`, `deleteExpiredRecordingAudio()`, `enqueueRecording(_:) async`, `applyRecordingStep(_:token:)`, `recordingTextMoved(from:to:)`, `recordingTextURL(key:) -> URL?`, `openRecordingText(key:)`, `static let crashedRecordingMessage`.
  - `SuggestionNotifier.notify(_:home:recording: Bool = false)`, `notifyTranscribed(fileName:folder:home:)`.
  - `Permissions.Pane.microphone`, `.speechRecognition`, `Permissions.settingsURL(_:) -> URL?`, `Permissions.dictationSettingsURL`.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`Tests/WorkGraphAppTests/RecordingFlowTests.swift`:

```swift
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
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter RecordingFlowTests 2>&1 | tail -5`
Expected: 컴파일 실패 — `cannot find type 'AudioRecording' in scope`.

- [ ] **Step 3: 시스템 설정 주소 (Collectors)**

`Sources/WorkGraphCollectors/Permissions.swift` 의 `Pane` 과 `openSettings` 를 아래로 바꾼다:

```swift
    public enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case screenRecording = "Privacy_ScreenCapture"
        case filesAndFolders = "Privacy_FilesAndFolders"
        case microphone = "Privacy_Microphone"
        case speechRecognition = "Privacy_SpeechRecognition"
    }
```

```swift
    public static func settingsURL(_ pane: Pane) -> URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")
    }

    /// 시스템 설정 → 키보드 (받아쓰기 켜기는 이 화면 아래쪽에 있다)
    public static let dictationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")

    public static func openSettings(_ pane: Pane) {
        if let url = settingsURL(pane) { NSWorkspace.shared.open(url) }
    }
```

- [ ] **Step 4: 권한과 문제 안내**

`Sources/WorkGraphApp/Recording/RecordingPermissions.swift`:

```swift
import AVFoundation
import AppKit
import Speech
import WorkGraphCollectors
import WorkGraphCore

/// 녹음을 시작하지 못하게 하거나 받아쓰기를 막은 것. 메뉴 막대에 한 줄로 보이고, 누르면 고칠 수 있는 시스템 설정을 연다
enum RecordingProblem: Equatable {
    /// swift run 처럼 Info.plist 사용 문구가 없는 실행 (이때 권한을 물으면 시스템이 앱을 끝낸다)
    case notBundled
    case microphone
    case speech
    /// 시스템 설정 → 키보드 → 받아쓰기가 꺼짐 (기기 안 인식이 kLSRErrorDomain 201 로 실패)
    case dictation
    case failed(String)

    init(_ error: TranscriptionError) {
        switch error {
        case .dictationDisabled: self = .dictation
        case .speechDenied: self = .speech
        case .unavailable(let reason): self = .failed(reason)
        case .failed: self = .failed(error.message)
        }
    }

    var text: String {
        switch self {
        case .notBundled: "녹음은 설치한 앱에서만 쓸 수 있어요"
        case .microphone: "마이크 권한이 꺼져 있어요"
        case .speech: "음성 인식 권한이 꺼져 있어요"
        case .dictation: "받아쓰기가 꺼져 있어요"
        case .failed(let message): message
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone: Permissions.settingsURL(.microphone)
        case .speech: Permissions.settingsURL(.speechRecognition)
        case .dictation: Permissions.dictationSettingsURL
        case .notBundled, .failed: nil
        }
    }

    func openSettings() {
        if let settingsURL { NSWorkspace.shared.open(settingsURL) }
    }
}

/// 녹음 전 권한 확인 (테스트에서는 가짜로 바꾼다)
@MainActor
protocol RecordingPermissions {
    /// 녹음할 수 있으면 nil. 처음이면 시스템 권한 창이 뜬다
    func check() async -> RecordingProblem?
}

struct SystemRecordingPermissions: RecordingPermissions {
    func check() async -> RecordingProblem? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard info["NSMicrophoneUsageDescription"] != nil, info["NSSpeechRecognitionUsageDescription"] != nil else { return .notBundled }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { return .microphone }
        default: return .microphone
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return nil
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            return status == .authorized ? nil : .speech
        default: return .speech
        }
    }
}
```

- [ ] **Step 5: 녹음기**

`Sources/WorkGraphApp/Recording/VoiceRecorder.swift`:

```swift
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
```

- [ ] **Step 6: 기기 안 받아쓰기**

`Sources/WorkGraphApp/Recording/SpeechTranscriber.swift`:

```swift
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
```

- [ ] **Step 7: 알림에 녹음 문구 더하기**

`Sources/WorkGraphApp/SuggestionNotifier.swift` 의 `notify(_:home:)` 함수 전체(37-57)를 아래 세 함수로 바꾼다:

```swift
    func notify(_ suggestion: FileSuggestion, home: String, recording: Bool = false) {
        guard available, let id = suggestion.id else { return }
        let title = recording ? FileSuggestionCopy.recordingTitle : FileSuggestionCopy.title
        let body = recording
            ? FileSuggestionCopy.recordingBody(fileName: suggestion.fileName, folder: suggestion.suggestedFolder, home: home)
            : FileSuggestionCopy.body(fileName: suggestion.fileName, folder: suggestion.suggestedFolder, home: home)
        deliver(title: title, body: body, category: Self.category, suggestionId: id, identifier: "file-suggestion-\(id)")
    }

    /// 받아쓴 녹음을 저장만 했을 때 (폴더 제안 없음). 버튼 없음
    func notifyTranscribed(fileName: String, folder: String, home: String) {
        guard available else { return }
        deliver(title: FileSuggestionCopy.transcribedTitle, body: FileSuggestionCopy.transcribedBody(fileName: fileName, folder: folder, home: home),
                category: nil, suggestionId: nil, identifier: "recording-\(UUID().uuidString)")
    }

    private func deliver(title: String, body: String, category: String?, suggestionId: Int64?, identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.authorized = granted
            center.getNotificationSettings { [weak self] settings in
                AppLog.write("알림 권한: \(granted ? "허용" : "거부") 상태=\(settings.authorizationStatus.rawValue) 배너=\(settings.alertSetting.rawValue)\(error.map { " 오류=\($0.localizedDescription)" } ?? "")")
                self?.onDenied?(settings.authorizationStatus == .denied)
            }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let category { content.categoryIdentifier = category }
            if let suggestionId { content.userInfo = ["suggestionId": suggestionId] }
            content.sound = .default
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
                if let error { AppLog.write("알림 보내기 실패: \(error.localizedDescription)") }
            }
        }
    }
```

- [ ] **Step 8: AppState 에 녹음 상태와 연결 더하기**

`Sources/WorkGraphApp/AppState.swift`:

(1) `@Published var rawRecordsSince: String?` 다음 줄에 추가:

```swift
    // 녹음 (AppState+Recording)
    @Published var activeRecording: ActiveRecording?
    @Published var recordingWork: RecordingPipeline.Step?
    @Published var recordingProblem: RecordingProblem?
    @Published var recordings: [Recording] = []
```

(2) `var folderIndexTask: Task<FolderIndex, Never>?` 다음 줄에 추가:

```swift
    var recordingPipeline: RecordingPipeline?
    var recorder: any AudioRecording = VoiceRecorder()
    var recordingPermissions: any RecordingPermissions = SystemRecordingPermissions()
    var recordingQueue: Task<Void, Never>?
    var recordingStepToken = 0
```

(3) `init()` 의 `self.suggester = FolderSuggester(db: database, llm: makeQuickClient())` 다음 줄에 추가:

```swift
            self.recordingPipeline = makeRecordingPipeline(database)
            // 녹음 중에 앱을 끝내면 파일을 닫아 둔다 (다음 실행 때 받아쓰기부터 이어 간다)
            _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishRecordingOnQuit() }
            }
```

(4) `start(_ coordinator:)` 의 마지막 `tasks.append(Task { … consolidateIfDue() … })` 다음에 추가:

```swift
        tasks.append(Task { [weak self] in                 // 녹음: 꺼지기 전에 못 끝낸 것을 이어서 정리하고, 7일 지난 녹음 파일을 지운다 (켤 때와 하루 한 번)
            await self?.resumeRecordings()
            while !Task.isCancelled {
                self?.deleteExpiredRecordingAudio()
                try? await Task.sleep(nanoseconds: 86_400_000_000_000)
            }
        })
```

(5) `makeQuickClient()` 함수 다음에 추가:

```swift
    /// 녹음 정리: 기기 안 받아쓰기, 제목은 빠른 모델, 받아쓴 글은 ~/Documents/Sillog 녹음
    private func makeRecordingPipeline(_ database: WGDatabase) -> RecordingPipeline {
        RecordingPipeline(db: database, transcriber: SpeechTranscriber(), llm: makeQuickClient(),
                          textFolder: RecordingPipeline.defaultTextFolder(home: NSHomeDirectory()))
    }
```

(6) `applySettings()` 의 `if let db { suggester = FolderSuggester(db: db, llm: makeQuickClient()) }` 를 바꾼다:

```swift
        if let db {
            suggester = FolderSuggester(db: db, llm: makeQuickClient())
            recordingPipeline = makeRecordingPipeline(db)
        }
```

- [ ] **Step 9: 녹음 흐름 (AppState+Recording)**

`Sources/WorkGraphApp/AppState+Recording.swift`:

```swift
import AppKit
import Foundation
import WorkGraphCore

/// 녹음 중인 것: 메뉴 막대 빨간 점과 "녹음 중 12:31"
struct ActiveRecording: Equatable {
    let id: Int64
    let startedAt: Double
}

/// 메뉴 막대 녹음: 시작 → 끝 → 받아쓰기 → 제목·.md → 폴더 제안 → 알림.
/// 받아쓰는 동안에도 새로 녹음할 수 있고, 정리는 하나씩 차례로 한다 (기기 안 인식기를 하나만 쓴다)
extension AppState {
    static let crashedRecordingMessage = "녹음 중 앱이 꺼져 녹음 파일을 읽을 수 없어요"

    func refreshRecordings() {
        guard let db else { return }
        let fresh = (try? RecordingStore(db).all()) ?? []
        if fresh != recordings { recordings = fresh }
    }

    /// 메뉴 막대 [● 녹음 시작]. 권한이 없으면 녹음하지 않고 안내만 남긴다
    func startRecording() async {
        guard activeRecording == nil, let db else { return }
        if let problem = await recordingPermissions.check() {
            recordingProblem = problem
            AppLog.write("녹음 시작 안 함: \(problem.text)")
            return
        }
        guard activeRecording == nil else { return }                    // 권한 창을 기다리는 동안 한 번 더 눌린 경우
        recordingProblem = nil
        let store = RecordingStore(db)
        let now = Date().timeIntervalSince1970
        do {
            var recording = try store.insert(Recording(startedAt: now, audioPath: ""))
            guard let id = recording.id else { return }
            let url = db.recordingsDirectory.appendingPathComponent("\(id).m4a")
            recording.audioPath = url.path
            try store.update(recording)
            do {
                try recorder.start(to: url)
            } catch {
                try? store.delete(id: id)
                throw error
            }
            activeRecording = ActiveRecording(id: id, startedAt: now)
            AppLog.write("녹음 시작: \(url.lastPathComponent)")
        } catch {
            recordingProblem = .failed("녹음을 시작하지 못했어요. \(error.localizedDescription)")
            AppLog.write("녹음 시작 실패: \(error)")
        }
        refreshRecordings()
    }

    /// [■ 끝내기]: 파일을 닫고 받아쓰기부터 차례로 이어 간다. 이 녹음의 정리가 끝나면 돌아온다
    func stopRecording() async {
        guard let id = closeActiveRecording() else { return }
        await enqueueRecording(id)
    }

    /// 앱을 끝낼 때 녹음 중이면 파일을 닫아 둔다. 다음 실행 때 받아쓰기부터 이어 간다
    func finishRecordingOnQuit() {
        if let id = closeActiveRecording() { AppLog.write("앱 종료: 녹음 \(id) 을 닫고 다음 실행 때 받아씀") }
    }

    /// 보관함 [다시 받아쓰기] (받아쓰기에 실패한 녹음)
    func retranscribe(_ recording: Recording) async {
        guard let id = recording.id, let pipeline = recordingPipeline else { return }
        do {
            try pipeline.prepareRetry(id: id, duration: AudioFileInfo.duration(of: URL(fileURLWithPath: recording.audioPath)))
        } catch {
            recordingProblem = .failed("다시 받아쓰지 못했어요. \(error.localizedDescription)")
            return
        }
        recordingProblem = nil
        await enqueueRecording(id)
    }

    /// 앱을 켤 때: 꺼지기 전에 끝나지 않은 녹음을 이어서 정리한다. 녹음 중 꺼진 파일은 읽히면 받아쓰고, 안 읽히면 실패로 둔다
    func resumeRecordings() async {
        guard let db else { return }
        let store = RecordingStore(db)
        for var recording in (try? store.unfinished()) ?? [] {
            guard let id = recording.id, id != activeRecording?.id else { continue }
            if recording.status == .recording {
                guard let seconds = AudioFileInfo.duration(of: URL(fileURLWithPath: recording.audioPath)) else {
                    recording.status = .failed
                    recording.error = Self.crashedRecordingMessage
                    try? store.update(recording)
                    AppLog.write("녹음 \(id): \(Self.crashedRecordingMessage)")
                    continue
                }
                recording.duration = seconds
                recording.endedAt = recording.startedAt + seconds
                recording.status = .transcribing
                try? store.update(recording)
            }
            await enqueueRecording(id)
        }
        refreshRecordings()
    }

    /// 받아쓰기가 끝나고 7일 지난 녹음 파일을 지운다 (받아쓴 글은 남는다)
    func deleteExpiredRecordingAudio() {
        guard let db else { return }
        guard let count = try? RecordingStore(db).deleteExpiredAudio(now: Date().timeIntervalSince1970), count > 0 else { return }
        AppLog.write("녹음 파일 \(count)개를 지움 (받아쓰기 끝나고 7일)")
        refreshRecordings()
    }

    /// 정리를 차례로: 앞의 정리가 끝난 뒤에 시작하고, 이 녹음의 정리가 끝나면 돌아온다
    func enqueueRecording(_ id: Int64) async {
        let previous = recordingQueue
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.processRecording(id)
        }
        recordingQueue = task
        await task.value
    }

    /// 정리 단계 알림. 끝난 정리가 늦게 보낸 알림(token 이 다름)은 버린다
    func applyRecordingStep(_ step: RecordingPipeline.Step, token: Int) {
        guard token == recordingStepToken else { return }
        if case .transcribing = step, case .naming? = recordingWork { return }
        recordingWork = step
    }

    /// 파일 탭·알림에서 받아쓴 글을 옮기거나 되돌리면 녹음 기록의 경로도 따라간다
    func recordingTextMoved(from old: String?, to new: String) {
        guard let db, let old, old != new else { return }
        guard (try? RecordingStore(db).moveText(from: old, to: new)) == true else { return }
        AppLog.write("녹음 글 경로 바뀜: \(new)")
        refreshRecordings()
    }

    /// 그래프 카드의 녹음 자료(recording:<id>) → 받아쓴 글 파일. 파일이 없으면 nil
    func recordingTextURL(key: String) -> URL? {
        guard key.hasPrefix("recording:"), let id = Int64(key.dropFirst("recording:".count)), let db,
              let recording = try? RecordingStore(db).find(id: id), let path = recording.textPath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func openRecordingText(key: String) {
        guard let url = recordingTextURL(key: key) else { AppLog.write("녹음 글을 찾지 못함: \(key)"); return }
        if !NSWorkspace.shared.open(url) { AppLog.write("열기 실패: \(url.path)") }
    }

    // MARK: 안쪽

    /// 녹음기를 멈추고 기록을 '받아쓰는 중'으로 바꾼다. 닫은 녹음 id
    private func closeActiveRecording() -> Int64? {
        guard let active = activeRecording, let db else { return nil }
        let seconds = recorder.stop()
        activeRecording = nil
        let store = RecordingStore(db)
        if var recording = try? store.find(id: active.id) {
            recording.endedAt = Date().timeIntervalSince1970
            recording.duration = seconds
            recording.status = .transcribing
            try? store.update(recording)
        }
        AppLog.write("녹음 끝: \(Int(seconds))초")
        return active.id
    }

    private func processRecording(_ id: Int64) async {
        guard let pipeline = recordingPipeline else { return }
        recordingStepToken += 1
        let token = recordingStepToken
        recordingWork = .transcribing(0)
        refreshRecordings()
        do {
            let outcome = try await pipeline.process(id: id, onStep: { [weak self] step in
                Task { @MainActor in self?.applyRecordingStep(step, token: token) }
            }, suggest: { [weak self] recording, excerpt in
                await self?.suggestFolder(for: recording, excerpt: excerpt)
            })
            switch outcome {
            case .ready(let recording):
                AppLog.write("녹음 정리 끝: \(recording.textPath ?? "")")
                notifyRecordingReady(recording)
            case .empty:
                AppLog.write("녹음 \(id): 받아쓴 글 없음 (짧거나 소리가 없음)")
            case .failed(_, let error):
                AppLog.write("녹음 \(id) 받아쓰기 실패: \(error.message)")
                recordingProblem = RecordingProblem(error)
            }
        } catch {
            AppLog.write("녹음 \(id) 정리 실패: \(error)")
            recordingProblem = .failed("녹음을 정리하지 못했어요. \(error.localizedDescription)")
        }
        recordingStepToken += 1                                             // 늦게 온 단계 알림은 버린다
        recordingWork = nil
        refreshRecordings()
    }

    /// 받아쓴 글 .md 의 폴더 제안: 녹음하는 동안 본 창과 최근 업무, 내용 발췌로 판단한다
    private func suggestFolder(for recording: Recording, excerpt: String) async -> FileSuggestion? {
        guard settings.suggestFolders, let suggester, let db, let path = recording.textPath else { return nil }
        let now = Date().timeIntervalSince1970
        let index = await currentFolderIndex()
        let observations = (try? store?.recent(limit: 120)) ?? []
        let openTasks: [TaskDigest] = (try? await db.writer.read { try GraphTx($0).openTasks(limit: 6) }) ?? []
        let currentTask = openTasks.first.flatMap { $0.lastActive > now - 1_800 ? $0.id : nil }
        let context = FolderSuggester.Context(recentTitles: Self.recentContext(from: observations, since: recording.startedAt - 600),
                                              openTasks: openTasks, currentTaskKey: currentTask, now: now,
                                              contentExcerpt: excerpt, kind: .recording)
        do {
            let suggestion = try await suggester.suggest(filePath: path, originURL: nil, index: index, context: context)
            if let suggestion {
                AppLog.write("녹음 폴더 제안: \(suggestion.fileName) → \(suggestion.suggestedFolder)")
                refreshFileSuggestions()
            }
            return suggestion
        } catch {
            AppLog.write("녹음 폴더 제안 실패: \(String(describing: error).prefix(200))")
            await handleAuthLossIfNeeded()
            return nil
        }
    }

    /// 폴더 제안이 있으면 [옮기기][무시] 알림, 없으면 저장한 곳만 알린다
    private func notifyRecordingReady(_ recording: Recording) {
        guard let db, let path = recording.textPath else { return }
        let home = NSHomeDirectory()
        if let id = recording.suggestionId, let suggestion = try? FileSuggestionStore(db).suggestion(id: id), suggestion.status == "pending" {
            notifier.notify(suggestion, home: home, recording: true)
        } else {
            notifier.notifyTranscribed(fileName: (path as NSString).lastPathComponent, folder: (path as NSString).deletingLastPathComponent, home: home)
        }
    }
}
```

- [ ] **Step 10: 통과 확인**

Run: `swift test --filter RecordingFlowTests 2>&1 | tail -5`
Expected: 10 tests, 0 failures.

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 11: 커밋**

```bash
git add Sources/WorkGraphCollectors/Permissions.swift Sources/WorkGraphApp/Recording Sources/WorkGraphApp/AppState+Recording.swift Sources/WorkGraphApp/AppState.swift Sources/WorkGraphApp/SuggestionNotifier.swift Tests/WorkGraphAppTests/RecordingFlowTests.swift
git commit -m "$(cat <<'EOF'
앱 녹음 엔진: 마이크 녹음, 기기 안 받아쓰기, 권한 안내, 정리 차례, 이어 하기, 종료 때 파일 닫기

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: 받아쓴 글을 옮기면 경로 따라가기, 앱 번들 사용 문구

**Files:**
- Modify: `Sources/WorkGraphApp/AppState+Files.swift` (`acceptSuggestion` 94-105, `chooseFolderAndMove` 108-127, `undoSuggestion` 136-145)
- Modify: `scripts/make-app.sh` (Info.plist heredoc, `NSDownloadsFolderUsageDescription` 다음)
- Test: `Tests/WorkGraphAppTests/RecordingFilesTests.swift` (새)

**Interfaces:**
- Consumes: `AppState.recordingTextMoved(from:to:)` (Task 8), `RecordingStore.moveText` (Task 1), 테스트 도우미 `NamingLLM` (Task 8 `RecordingFlowTests.swift`).
- Produces: 폴더 제안을 받아들이거나(제안 폴더·직접 고른 폴더) 되돌리면 그 파일이 녹음의 `.md` 일 때 `recordings.text_path` 가 새 경로가 된다. 앱 Info.plist 에 `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSDocumentsFolderUsageDescription`.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`Tests/WorkGraphAppTests/RecordingFilesTests.swift`:

```swift
import AppKit
import XCTest
@testable import WorkGraphApp
@testable import WorkGraphCore

/// 받아쓴 글 .md 를 파일 탭·알림에서 옮기면 녹음 기록이 따라가고, 앱 번들은 권한 사용 문구를 갖는다
@MainActor
final class RecordingFilesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("wg-recording-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func testAcceptingAndUndoingTheSuggestionMovesTheRecordingText() throws {
        let db = try WGDatabase.inMemory()
        let state = AppState(preview: { $0.phase = .ready }, database: db)
        let source = folder.appendingPathComponent("Sillog 녹음"), target = folder.appendingPathComponent("학교/자료구조")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let md = source.appendingPathComponent("2026-10-10 자료구조 3주차 강의.md")
        try Data("# 자료구조 3주차 강의".utf8).write(to: md)
        let recording = try RecordingStore(db).insert(Recording(startedAt: 1_000, endedAt: 1_095, duration: 95, audioPath: "/tmp/x.m4a",
                                                                 textPath: md.path, transcript: "문장", status: .ready))
        let suggestion = try FileSuggestionStore(db).insert(FileSuggestion(ts: 1_100, path: md.path, fileName: md.lastPathComponent, originUrl: nil,
                                                                           suggestedFolder: target.path, confidence: 0.9, reason: "같은 과목", source: "llm"))
        state.suggester = FolderSuggester(db: db, llm: NamingLLM(), home: folder.path)

        state.acceptSuggestion(suggestion)
        let moved = target.appendingPathComponent(md.lastPathComponent).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved))
        XCTAssertEqual(try RecordingStore(db).find(id: recording.id!)?.textPath, moved)

        state.undoSuggestion(try XCTUnwrap(FileSuggestionStore(db).suggestion(id: suggestion.id!)))
        XCTAssertEqual(try RecordingStore(db).find(id: recording.id!)?.textPath, md.path)
    }

    func testAppBundleDeclaresMicrophoneSpeechAndDocumentsUsage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/make-app.sh"), encoding: .utf8)
        for key in ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription", "NSDocumentsFolderUsageDescription"] {
            XCTAssertTrue(script.contains("<key>\(key)</key>"), "\(key) 가 없으면 권한을 물을 때 시스템이 앱을 끝낸다")
        }
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter RecordingFilesTests 2>&1 | tail -5`
Expected: FAIL 2개 — textPath 가 옛 경로 그대로, `NSMicrophoneUsageDescription 가 없으면 …`.

- [ ] **Step 3: 옮기기·되돌리기에 경로 갱신 잇기**

`Sources/WorkGraphApp/AppState+Files.swift`:
- `acceptSuggestion` 의 `AppLog.write("파일 옮김: \(suggestion.fileName) → \(target)")` 다음 줄에 `recordingTextMoved(from: suggestion.path, to: target)` 추가.
- `chooseFolderAndMove` 의 `AppLog.write("파일 옮김(직접 선택): \(suggestion.fileName) → \(target)")` 다음 줄에 `recordingTextMoved(from: suggestion.path, to: target)` 추가.
- `undoSuggestion` 의 `AppLog.write("파일 되돌림: \(restored)")` 다음 줄에 `recordingTextMoved(from: suggestion.movedTo, to: restored)` 추가.

- [ ] **Step 4: Info.plist 사용 문구**

`scripts/make-app.sh` 의 Info.plist heredoc 에서 `<key>NSDownloadsFolderUsageDescription</key>…` 줄 다음에 추가:

```xml
  <key>NSMicrophoneUsageDescription</key><string>메뉴 막대에서 녹음할 때 마이크 소리를 녹음합니다.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>녹음한 말을 이 Mac 안에서 글로 받아씁니다.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>받아쓴 녹음을 문서 폴더의 'Sillog 녹음'에 저장합니다.</string>
```

- [ ] **Step 5: 통과 확인**

Run: `swift test --filter "RecordingFilesTests|RecordingFlowTests" 2>&1 | tail -5`
Expected: 12 tests, 0 failures.

- [ ] **Step 6: 커밋**

```bash
git add Sources/WorkGraphApp/AppState+Files.swift scripts/make-app.sh Tests/WorkGraphAppTests/RecordingFilesTests.swift
git commit -m "$(cat <<'EOF'
받아쓴 글을 옮기거나 되돌리면 녹음 기록 경로도 따라가기, 앱에 마이크·음성 인식·문서 폴더 사용 문구

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: 메뉴 막대 녹음 줄과 빨간 점

**Files:**
- Modify: `Sources/WorkGraphApp/Views/MenuBarView.swift` (`MenuBarDashboard.body` 189-196, `bottom` 284-305, 파일 끝)
- Modify: `Sources/WorkGraphApp/WorkGraphApp.swift:28`, `MenuBarLabel` 65-80
- Modify: `Sources/WorkGraphApp/Snapshots/SnapshotCatalog.swift` (`all` 8, `menus` 다음)
- Test: `Tests/WorkGraphAppTests/RecordingMenuTests.swift` (새)

**Interfaces:**
- Consumes: `AppState.activeRecording/recordingWork/recordingProblem/startRecording/stopRecording` (Task 8), `RecordingProblem.text/settingsURL/openSettings` (Task 8), `RecordingText.clock` (Task 3), `OnboardingOverlayTests.recognizedText` (기존 테스트 도우미).
- Produces: `RecordingPipeline.Step.menuText: String` (App 확장), `MenuBarLabel(paused:recording:)`, `MenuBarLabel.icon(paused:recording:) -> NSImage`, `SnapshotCatalog.recording: [Snapshot]` (REC-01~03).

- [ ] **Step 1: 실패하는 테스트 쓰기**

`Tests/WorkGraphAppTests/RecordingMenuTests.swift`:

```swift
import AppKit
import SwiftUI
import XCTest
@testable import WorkGraphApp
@testable import WorkGraphCore

/// 메뉴 막대의 녹음 줄: 평소, 녹음 중, 받아쓰는 중, 정리하는 중, 권한·받아쓰기 꺼짐. 그리고 빨간 점 아이콘
@MainActor
final class RecordingMenuTests: XCTestCase {
    private func menuText(_ configure: (AppState) -> Void) -> String {
        let state = AppState(preview: { s in s.phase = .ready; configure(s) })
        let host = NSHostingView(rootView: AnyView(MenuBarView().environmentObject(state)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return OnboardingOverlayTests.recognizedText(host).filter { !$0.isWhitespace }
    }

    func testIdleShowsTheStartButton() {
        let text = menuText { _ in }
        XCTAssertTrue(text.contains("녹음시작"), text)
    }

    func testRecordingShowsTheElapsedTimeAndStop() {
        let text = menuText { s in s.activeRecording = ActiveRecording(id: 1, startedAt: Date().timeIntervalSince1970 - 751) }
        XCTAssertTrue(text.contains("녹음중12:3"), text)                       // 12:31 (그리는 사이 1초가 지날 수 있다)
        XCTAssertTrue(text.contains("끝내기"), text)
        XCTAssertFalse(text.contains("녹음시작"), text)
    }

    func testProcessingStepsAreShownAboveTheRecordButton() {
        let transcribing = menuText { s in s.recordingWork = .transcribing(0.37) }
        XCTAssertTrue(transcribing.contains("받아쓰는중37%"), transcribing)
        XCTAssertTrue(transcribing.contains("녹음시작"), "받아쓰는 동안에도 새로 녹음할 수 있다")
        let naming = menuText { s in s.recordingWork = .naming }
        XCTAssertTrue(naming.contains("녹음을정리하는중"), naming)
    }

    func testProblemsSayWhatIsOff() {
        let microphone = menuText { s in s.recordingProblem = .microphone }
        XCTAssertTrue(microphone.contains("마이크권한이꺼져있어요"), microphone)
        let dictation = menuText { s in s.recordingProblem = .dictation }
        XCTAssertTrue(dictation.contains("받아쓰기가꺼져있어요"), dictation)
    }

    func testStepTextRoundsThePercent() {
        XCTAssertEqual(RecordingPipeline.Step.transcribing(0.37).menuText, "받아쓰는 중 37%")
        XCTAssertEqual(RecordingPipeline.Step.naming.menuText, "녹음을 정리하는 중")
    }

    func testTheMenuBarIconTurnsIntoARedDotWhileRecording() {
        XCTAssertTrue(MenuBarLabel.icon(paused: false, recording: false).isTemplate)
        XCTAssertTrue(MenuBarLabel.icon(paused: true, recording: false).isTemplate)
        let dot = MenuBarLabel.icon(paused: false, recording: true)
        XCTAssertFalse(dot.isTemplate, "빨간색을 그대로 그린다")
        XCTAssertEqual(dot.accessibilityDescription, "녹음 중")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter RecordingMenuTests 2>&1 | tail -5`
Expected: 컴파일 실패 — `value of type 'RecordingPipeline.Step' has no member 'menuText'`, `type 'MenuBarLabel' has no member 'icon'`.

- [ ] **Step 3: 메뉴에 녹음 줄 넣기**

`Sources/WorkGraphApp/Views/MenuBarView.swift` 의 `MenuBarDashboard.body` 에서 `if !state.taskList.isEmpty { recentWork }` 와 `bottom` 사이에 `recordingSection` 을 넣는다:

```swift
            if !state.taskList.isEmpty { recentWork }
            recordingSection
            bottom
```

`bottom` 끝의 `.overlay(alignment: .top) { if !state.taskList.isEmpty { hairline } }` 줄을 지운다 (녹음 줄이 늘 그 사이에 있고 아래 선을 긋는다). `bottom` 위 주석의 "최근 업무가 있을 때만 위에 선을 긋는다 (다른 줄은 아래에 선이 있다)" 는 "위의 녹음 줄이 아래 선을 긋는다" 로 바꾼다.

`recentWork` 다음(`bottom` 앞)에 추가:

```swift
    /// 녹음: 문제 안내 → 정리 단계 → 녹음 줄 ([● 녹음 시작] 또는 "● 녹음 중 12:31" [■ 끝내기]). 최근 업무가 있으면 위에 선
    private var recordingSection: some View {
        VStack(spacing: 0) {
            if let problem = state.recordingProblem { recordingProblemRow(problem) }
            if let work = state.recordingWork { recordingWorkRow(work) }
            recordingRow
        }
        .overlay(alignment: .top) { if !state.taskList.isEmpty { hairline } }
    }

    @ViewBuilder private var recordingRow: some View {
        if let active = state.activeRecording {
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("녹음 중 \(RecordingText.clock(context.date.timeIntervalSince1970 - active.startedAt))")
                        .font(Brand.suit(11)).foregroundStyle(Brand.text).monospacedDigit()
                }
                Spacer()
                Button { Task { await state.stopRecording() } } label: {
                    HStack(spacing: 6) {
                        Rectangle().fill(Brand.ink).frame(width: 7, height: 7)
                        Text("끝내기").font(Brand.suit(11, .medium)).foregroundStyle(Brand.ink)
                    }
                    .padding(.horizontal, 12).frame(height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 50)
            .overlay(alignment: .bottom) { hairline }
        } else {
            Button { Task { await state.startRecording() } } label: {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("녹음 시작").font(Brand.suit(11)).foregroundStyle(Brand.text)
                    Spacer()
                }
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) { hairline }
        }
    }

    /// 받아쓰는 중 37% / 녹음을 정리하는 중
    private func recordingWorkRow(_ work: RecordingPipeline.Step) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(work.menuText).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
            Spacer()
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) { hairline }
    }

    /// 권한·받아쓰기 설정이 꺼져 있으면: 누르면 고칠 시스템 설정을 연다
    private func recordingProblemRow(_ problem: RecordingProblem) -> some View {
        Button { problem.openSettings() } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 14)).foregroundStyle(Brand.ink)
                Text(problem.text).font(Brand.suit(11)).foregroundStyle(Brand.tabText).lineLimit(2)
                Spacer()
                if problem.settingsURL != nil {
                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Brand.tabText)
                }
            }
            .frame(minHeight: 45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { hairline }
    }
```

파일 맨 끝에 추가:

```swift
extension RecordingPipeline.Step {
    /// 메뉴 막대의 정리 단계 문구: "받아쓰는 중 37%", "녹음을 정리하는 중"
    var menuText: String {
        switch self {
        case .transcribing(let progress): "받아쓰는 중 \(Int((progress * 100).rounded()))%"
        case .naming: "녹음을 정리하는 중"
        }
    }
}
```

- [ ] **Step 4: 메뉴 막대 아이콘**

`Sources/WorkGraphApp/WorkGraphApp.swift:28` 을 바꾼다:

```swift
            MenuBarLabel(paused: state.status.paused, recording: state.activeRecording != nil).environmentObject(state)
```

`MenuBarLabel` 을 아래로 바꾼다 (`.task` 안은 그대로). 아이콘은 `Image` 하나로 그린다: 조건마다 다른 뷰를 두면 `.task` 가 다시 돌아 창이 다시 열린다.

```swift
struct MenuBarLabel: View {
    let paused: Bool
    var recording = false
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: Self.icon(paused: paused, recording: recording))
            .task {
                WindowOpener.shared.open = { openWindow(id: "main") }
                await state.bootstrap()
                // 로그인 항목으로 조용히 뜬 경우가 아니면 창을 보여준다. 로그인 전이면 항상 온보딩을 띄운다.
                guard state.phase != .ready || Launch.isFirst || !Launch.asLoginItem else { return }
                WindowOpener.shared.openMain()
            }
    }

    /// 평소·일시정지는 메뉴 막대 색을 따르는 템플릿 아이콘, 녹음 중은 빨간 점 (색을 그대로 그린다)
    static func icon(paused: Bool, recording: Bool) -> NSImage {
        if recording {
            let red = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular).applying(red)
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "녹음 중")?.withSymbolConfiguration(config) ?? NSImage()
            image.isTemplate = false
            image.accessibilityDescription = "녹음 중"
            return image
        }
        let name = paused ? "pause.fill" : "point.3.connected.trianglepath.dotted"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Sillog") ?? NSImage()
        image.isTemplate = true
        return image
    }
}
```

- [ ] **Step 5: 스냅샷 (REC-01~03)**

`Sources/WorkGraphApp/Snapshots/SnapshotCatalog.swift`:
- `static var all` 식 끝에 ` + recording` 을 더한다. 예: `menus + windows + activity + chat + storage + [mathAnswer]` → `menus + windows + activity + chat + storage + [mathAnswer] + recording` (기준 커밋에 `[mathAnswer]` 가 없으면 `menus + windows + activity + chat + storage + recording`).
- `static var menus` 다음에 추가:

```swift
    /// 녹음: 메뉴 막대(녹음 중, 받아쓰는 중, 마이크 권한 꺼짐)
    static var recording: [Snapshot] {
        [
            shot("REC-01", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(); s.todayCount = 62; s.pendingCount = 6; s.taskList = recentTasks
                s.activeRecording = ActiveRecording(id: 1, startedAt: Date().timeIntervalSince1970 - 751)
            },
            shot("REC-02", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(); s.todayCount = 62; s.pendingCount = 6; s.taskList = recentTasks
                s.recordingWork = .transcribing(0.37)
            },
            shot("REC-03", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(); s.todayCount = 62; s.pendingCount = 6
                s.recordingProblem = .microphone
            },
        ]
    }
```

- [ ] **Step 6: 통과 확인과 눈으로 보기**

Run: `swift test --filter "RecordingMenuTests|OnboardingOverlayTests" 2>&1 | tail -5`
Expected: 모두 통과.

Run: `rm -rf /tmp/wg-shots && WORKGRAPH_SNAPSHOT=/tmp/wg-shots swift run WorkGraphApp 2>&1 | tail -3 && ls /tmp/wg-shots | grep -E "REC|OUT-06"`
Expected: `REC-01.png REC-02.png REC-03.png OUT-06.png OUT-06-long.png`. Read 로 다섯 장을 연다:
- REC-01: 최근 업무 아래 빨간 점 + "녹음 중 12:31" + 오른쪽 [■ 끝내기], 그 아래 [지금 정리].
- REC-02: "받아쓰는 중 37%" 줄 아래 [● 녹음 시작].
- REC-03: "마이크 권한이 꺼져 있어요 ↗" 줄 아래 [● 녹음 시작].
- OUT-06: 녹음 줄이 생긴 것 말고 나머지 줄과 선이 전과 같다 (선이 겹치거나 빠진 곳이 없다).

- [ ] **Step 7: 커밋**

```bash
git add Sources/WorkGraphApp/Views/MenuBarView.swift Sources/WorkGraphApp/WorkGraphApp.swift Sources/WorkGraphApp/Snapshots/SnapshotCatalog.swift Tests/WorkGraphAppTests/RecordingMenuTests.swift
git commit -m "$(cat <<'EOF'
메뉴 막대 녹음 줄: 녹음 시작·끝내기, 받아쓰는 중·정리하는 중, 권한·받아쓰기 꺼짐 안내, 녹음 중 빨간 점

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: 보관함 '녹음'과 상세, 그래프 카드에서 열기

**Files:**
- Create: `Sources/WorkGraphApp/Views/RecordingDetailView.swift`
- Modify: `Sources/WorkGraphApp/Views/LibraryView.swift` (`LibraryView` 상태 43-49, `body` 57-68, `sidebar` 88-91, `content` 129-140, 줄 함수)
- Modify: `Sources/WorkGraphApp/Views/GraphWebView.swift:65-67`
- Modify: `Sources/WorkGraphApp/Resources/graph/index.html:2714`
- Modify: `Sources/WorkGraphApp/Snapshots/SnapshotCatalog.swift` (`recording` 에 REC-04·05)
- Test: `Tests/WorkGraphAppTests/RecordingLibraryTests.swift` (새)

**Interfaces:**
- Consumes: `AppState.recordings/refreshRecordings/retranscribe/recordingTextURL/openRecordingText` (Task 8), `RecordingStore.audioKeepDays` (Task 1), `RecordingText.duration` (Task 3), `FileSuggestionCopy.folderLabel` (기존), `LibrarySheetHeader`·`Eyebrow`·`ReadOnlyTextView`·`BrandButtonStyle` (기존).
- Produces: `enum RecordingDetail` — `when(_:timeZone:)`, `subtitle(_:home:timeZone:)`, `notice(_:textExists:)`, `audioNote(_:audioExists:now:)`, `transcriptText(_:)`; `final class RecordingPlayer`; `struct RecordingDetailView(recording:)`.

> index.html 을 고치기 전에 `git diff --stat -- Sources/WorkGraphApp/Resources/graph/index.html` 로 다른 사람이 고친 것이 섞여 있지 않은지 본다. 비어 있어야 한다.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`Tests/WorkGraphAppTests/RecordingLibraryTests.swift`:

```swift
import AppKit
import SwiftUI
import XCTest
@testable import WorkGraphApp
@testable import WorkGraphCore

/// 보관함의 '녹음': 목록 줄 문구, 상세, 7일 안내, 없어진 받아쓴 글 파일
@MainActor
final class RecordingLibraryTests: XCTestCase {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    private var folder: URL!

    /// 2026-10-10 15:32 (서울)
    private var start: Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 15, minute: 32))!.timeIntervalSince1970
    }

    override func setUpWithError() throws {
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("wg-recording-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func ready(textPath: String?, audioPath: String = "/없음/7.m4a", readyAt: Double = 0) -> Recording {
        Recording(id: 7, startedAt: start, endedAt: start + 3_130, duration: 3_130, audioPath: audioPath, textPath: textPath,
                  title: "자료구조 3주차 강의", summary: "연결 리스트를 설명한 강의.", transcript: "오늘은 연결 리스트를 봅니다.\n노드는 값을 가집니다.",
                  status: .ready, readyAt: readyAt)
    }

    private func render<V: View>(_ view: V, size: CGSize) -> String {
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<8 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return OnboardingOverlayTests.recognizedText(host).filter { !$0.isWhitespace }
    }

    func testListRowShowsDateLengthAndFolderOrWhatHappened() {
        let home = "/Users/me"
        XCTAssertEqual(RecordingDetail.subtitle(ready(textPath: "/Users/me/Documents/학교/자료구조/강의.md"), home: home, timeZone: seoul),
                       "10월 10일 15:32  52분 10초  문서 / 학교 / 자료구조")
        var failed = ready(textPath: nil)
        failed.status = .failed
        XCTAssertEqual(RecordingDetail.subtitle(failed, home: home, timeZone: seoul), "10월 10일 15:32  52분 10초  받아쓰기 실패")
        var silent = ready(textPath: nil)
        silent.transcript = ""
        XCTAssertEqual(RecordingDetail.subtitle(silent, home: home, timeZone: seoul), "10월 10일 15:32  52분 10초  받아쓴 내용 없음")
        XCTAssertEqual(RecordingDetail.when(silent, timeZone: seoul), "2026년 10월 10일 15:32 · 52분 10초")
    }

    func testAudioNoteCountsTheDaysLeftAndExplainsKeptOrDeletedFiles() {
        let now = start + 10 * 86_400
        XCTAssertEqual(RecordingDetail.audioNote(ready(textPath: nil, readyAt: now - 2 * 86_400), audioExists: true, now: now), "5일 뒤 지워져요")
        var deleted = ready(textPath: nil, readyAt: now - 8 * 86_400)
        deleted.audioDeletedAt = now - 86_400
        XCTAssertEqual(RecordingDetail.audioNote(deleted, audioExists: false, now: now), "녹음 파일은 7일이 지나 지웠어요")
        var failed = ready(textPath: nil)
        failed.status = .failed
        XCTAssertEqual(RecordingDetail.audioNote(failed, audioExists: true, now: now), "받아쓰기에 실패한 녹음은 지우지 않아요")
        XCTAssertEqual(RecordingDetail.transcriptText(ready(textPath: nil)), "오늘은 연결 리스트를 봅니다.\n\n노드는 값을 가집니다.")
    }

    func testMissingTextFileIsReportedAndNotOpened() throws {
        let gone = folder.appendingPathComponent("옮겨진.md").path
        let recording = ready(textPath: gone)
        XCTAssertEqual(RecordingDetail.notice(recording, textExists: false), "받아쓴 글 파일을 찾을 수 없어요. 옮기거나 지웠어도 아래 글은 앱에 남아 있어요.")
        XCTAssertNil(RecordingDetail.notice(recording, textExists: true))

        let db = try WGDatabase.inMemory()
        let state = AppState(preview: { $0.phase = .ready }, database: db)
        var stored = recording
        stored.id = nil
        let saved = try RecordingStore(db).insert(stored)
        XCTAssertNil(state.recordingTextURL(key: "recording:\(saved.id!)"), "없는 파일은 열지 않는다")
        try Data("# 강의".utf8).write(to: URL(fileURLWithPath: gone))
        XCTAssertEqual(state.recordingTextURL(key: "recording:\(saved.id!)")?.path, gone)
        XCTAssertNil(state.recordingTextURL(key: "file:///Users/me/a.md"))
    }

    func testDetailShowsTheTitleSummaryPlaybackAndFinderButton() throws {
        let audio = folder.appendingPathComponent("7.m4a")
        try Data("a".utf8).write(to: audio)
        let md = folder.appendingPathComponent("강의.md")
        try Data("# 강의".utf8).write(to: md)
        let recording = ready(textPath: md.path, audioPath: audio.path, readyAt: Date().timeIntervalSince1970 - 2 * 86_400)
        let state = AppState(preview: { $0.phase = .ready })
        let text = render(RecordingDetailView(recording: recording).environmentObject(state), size: CGSize(width: 640, height: 520))
        for expected in ["자료구조3주차강의", "연결리스트를설명한강의", "듣기", "Finder에서보기"] {
            XCTAssertTrue(text.contains(expected), "\(expected) 가 보여야 한다: \(text.prefix(400))")
        }
        XCTAssertFalse(text.contains("다시받아쓰기"), "받아쓰기에 성공한 녹음에는 다시 받아쓰기가 없다")
    }

    func testLibraryShowsRecordingsAmongItsItems() throws {
        let database = try WGDatabase.inMemory()
        var stored = ready(textPath: nil)
        stored.id = nil
        _ = try RecordingStore(database).insert(stored)
        let state = AppState(preview: { s in
            s.phase = .ready
            s.selectedTab = .library
            let offline = OpenAICompatClient(baseURL: URL(string: "http://localhost:5010/v1")!, model: "preview", apiKey: nil)
            s.chat = ChatState(db: database, makeClient: { .model(offline) }, makeProjectClient: { offline })
        }, database: database)
        let text = render(MainWindow().environmentObject(state), size: CGSize(width: 1180, height: 716))
        XCTAssertTrue(text.contains("자료구조3주차강의"), "전체 종류에 녹음이 보여야 한다: \(text.prefix(400))")
        XCTAssertTrue(text.contains("52분10초"), text)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter RecordingLibraryTests 2>&1 | tail -5`
Expected: 컴파일 실패 — `cannot find 'RecordingDetail' in scope`.

- [ ] **Step 3: 상세 화면과 문구**

`Sources/WorkGraphApp/Views/RecordingDetailView.swift`:

```swift
import AVFoundation
import AppKit
import SwiftUI
import WorkGraphCore

/// 녹음 상세·목록 줄에 쓰는 문구 (화면 없이 시험한다)
enum RecordingDetail {
    /// "2026년 10월 10일 15:32 · 52분 10초"
    static func when(_ recording: Recording, timeZone: TimeZone = .current) -> String {
        "\(format(recording.startedAt, "yyyy년 M월 d일 HH:mm", timeZone)) · \(RecordingText.duration(recording.duration))"
    }

    /// 목록 줄 둘째 줄: 날짜, 길이, 폴더 (또는 상태)
    static func subtitle(_ recording: Recording, home: String, timeZone: TimeZone = .current) -> String {
        let date = format(recording.startedAt, "M월 d일 HH:mm", timeZone)
        let length = RecordingText.duration(recording.duration)
        let parts: [String]
        switch recording.status {
        case .recording: parts = [date, "녹음 중"]
        case .transcribing: parts = [date, "받아쓰는 중"]
        case .failed: parts = [date, length, "받아쓰기 실패"]
        case .ready:
            if !recording.hasTranscript {
                parts = [date, length, "받아쓴 내용 없음"]
            } else {
                let folder = recording.textPath.map { FileSuggestionCopy.folderLabel(($0 as NSString).deletingLastPathComponent, home: home) } ?? ""
                parts = [date, length, folder]
            }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "  ")
    }

    /// 상세 위쪽 안내: 받아쓰기 실패 이유, 받아쓴 글 파일이 없어진 것
    static func notice(_ recording: Recording, textExists: Bool) -> String? {
        if recording.status == .failed { return recording.error ?? "받아쓰지 못했어요." }
        if recording.textPath != nil, !textExists { return "받아쓴 글 파일을 찾을 수 없어요. 옮기거나 지웠어도 아래 글은 앱에 남아 있어요." }
        return nil
    }

    /// 녹음 파일 안내: "5일 뒤 지워져요", 지운 뒤, 실패해서 남겨 둔 것
    static func audioNote(_ recording: Recording, audioExists: Bool, now: Double) -> String? {
        if recording.audioDeletedAt != nil { return "녹음 파일은 7일이 지나 지웠어요" }
        guard audioExists else { return nil }
        if recording.status == .failed { return "받아쓰기에 실패한 녹음은 지우지 않아요" }
        guard recording.status == .ready, let readyAt = recording.readyAt else { return nil }
        let left = readyAt + RecordingStore.audioKeepDays * 86_400 - now
        return "\(max(1, Int((left / 86_400).rounded(.up))))일 뒤 지워져요"
    }

    /// 상세에 보이는 받아쓴 글: 발화마다 한 문단
    static func transcriptText(_ recording: Recording) -> String {
        recording.hasTranscript ? recording.utterances.joined(separator: "\n\n") : "받아쓴 내용이 없어요."
    }

    private static func format(_ time: Double, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: Date(timeIntervalSince1970: time))
    }
}

/// 녹음 파일 듣기 (녹음 파일이 남아 있는 7일 동안만)
@MainActor
final class RecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playing { stop(); return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.play()
        self.player = player
        playing = true
    }

    func stop() {
        player?.stop()
        player = nil
        playing = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

/// 보관함의 녹음 상세: 요약, 받아쓴 글, 7일 동안 듣기, 받아쓴 글 파일, 실패했으면 다시 받아쓰기
struct RecordingDetailView: View {
    let recording: Recording
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = RecordingPlayer()

    private var textExists: Bool { recording.textPath.map { FileManager.default.fileExists(atPath: $0) } ?? false }
    private var audioExists: Bool { recording.audioDeletedAt == nil && FileManager.default.fileExists(atPath: recording.audioPath) }

    var body: some View {
        VStack(spacing: 0) {
            LibrarySheetHeader(eyebrow: "RECORDING", title: recording.displayTitle, detail: RecordingDetail.when(recording)) { dismiss() }
            VStack(alignment: .leading, spacing: 8) {
                if let notice = RecordingDetail.notice(recording, textExists: textExists) {
                    Text(notice).font(Brand.suit(12)).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                }
                if let summary = recording.summary, !summary.isEmpty {
                    Eyebrow("SUMMARY")
                    Text(summary).font(Brand.suit(12)).foregroundStyle(Brand.tabText).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Eyebrow("TRANSCRIPT").padding(.top, 6)
            }
            .padding(.horizontal, 27).padding(.top, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            ReadOnlyTextView(text: RecordingDetail.transcriptText(recording))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 15).padding(.bottom, 8)
            footer
        }
        .frame(width: 640, height: 520)
        .background(.white)
        .onDisappear { player.stop() }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if audioExists {
                Button { player.toggle(URL(fileURLWithPath: recording.audioPath)) } label: {
                    Label(player.playing ? "멈추기" : "듣기", systemImage: player.playing ? "stop.fill" : "play.fill")
                }
                .buttonStyle(BrandButtonStyle())
            }
            if let note = RecordingDetail.audioNote(recording, audioExists: audioExists, now: Date().timeIntervalSince1970) {
                Text(note).font(Brand.suit(11)).foregroundStyle(Brand.gray)
            }
            Spacer()
            if recording.status == .failed, audioExists {
                Button("다시 받아쓰기") {
                    Task { await state.retranscribe(recording) }
                    dismiss()
                }
                .buttonStyle(BrandButtonStyle(kind: .primary))
            }
            if let path = recording.textPath, textExists {
                Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                    .buttonStyle(BrandButtonStyle())
            }
            Button("닫기") { dismiss() }.buttonStyle(BrandButtonStyle())
        }
        .padding(.horizontal, 24).frame(height: 63)
        .brandGlass()
        .overlay(alignment: .top) { Rectangle().fill(Brand.hairline).frame(height: 1) }
    }
}
```

- [ ] **Step 4: 보관함에 '녹음' 종류와 줄 넣기**

`Sources/WorkGraphApp/Views/LibraryView.swift`:

(1) `LibraryTile` 아래(파일 위쪽, `struct LibraryView` 앞)에 추가:

```swift
/// 보관함 목록 한 줄: 보관한 자료 또는 녹음
private enum LibraryEntry: Identifiable {
    case item(ChatLibraryItem)
    case recording(Recording)

    var id: String {
        switch self {
        case .item(let item): "item:\(item.id)"
        case .recording(let recording): "recording:\(recording.id ?? 0)"
        }
    }

    var date: Double {
        switch self {
        case .item(let item): item.createdAt
        case .recording(let recording): recording.startedAt
        }
    }
}
```

(2) `LibraryView` 의 `@State private var deleting: ChatLibraryItem?` 다음에 추가:

```swift
    @EnvironmentObject private var state: AppState
    @State private var recordingPreview: Recording?
```

(3) `filtered` 다음에 추가:

```swift
    /// 보관한 자료와 녹음을 날짜순으로. 녹음은 프로젝트에 연결하지 않으므로 프로젝트를 고르면 빠진다
    private var entries: [LibraryEntry] {
        let items: [LibraryEntry] = kind == "recording" ? [] : filtered.map { LibraryEntry.item($0) }
        let showRecordings = (kind.isEmpty || kind == "recording") && projectID.isEmpty
        let recordings: [LibraryEntry] = showRecordings
            ? state.recordings.filter { query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query) }.map { LibraryEntry.recording($0) }
            : []
        return (items + recordings).sorted { $0.date > $1.date }
    }

    private var emptyTitle: String {
        if kind == "recording" { return state.recordings.isEmpty ? "녹음이 없습니다" : "검색 결과가 없습니다" }
        return library.items.isEmpty && state.recordings.isEmpty ? "보관한 자료가 없습니다" : "검색 결과가 없습니다"
    }
```

(4) `body` 의 `.sheet(item: $preview) { LibraryPreview(library: library, item: $0) }` 다음 줄에 추가:

```swift
        .sheet(item: $recordingPreview) { RecordingDetailView(recording: $0).environmentObject(state) }
        .onAppear { state.refreshRecordings() }
```

(5) `sidebar` 의 `filterRow("저장한 답변", kind == "note") { kind = "note" }` 다음 줄에 추가:

```swift
                filterRow("녹음", kind == "recording") { kind = "recording" }
```

(6) `content` 의 `if filtered.isEmpty { … } else { ScrollView { … } }` 블록을 아래로 바꾼다:

```swift
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: kind == "recording" ? "waveform" : "tray").font(.system(size: 26, weight: .light)).foregroundStyle(Brand.sub)
                    Text(emptyTitle).font(Brand.suit(14, .medium)).foregroundStyle(Brand.ink)
                    Text(kind == "recording" ? "메뉴 막대에서 녹음 시작을 누르면 받아쓴 글이 여기에 모여요." : "파일을 업로드하거나 채팅에서 결과물을 만들어보세요.")
                        .font(Brand.suit(12)).foregroundStyle(Brand.gray)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            switch entry {
                            case .item(let item): row(item)
                            case .recording(let recording): recordingRow(recording)
                            }
                        }
                    }.padding(.horizontal, 34).padding(.top, 6)
                }
            }
```

(7) `row(_:)` 함수 다음에 추가:

```swift
    private func recordingRow(_ recording: Recording) -> some View {
        Button { recordingPreview = recording } label: {
            HStack(spacing: 12) {
                LibraryTile(symbol: "waveform")
                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.displayTitle).font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText).lineLimit(1)
                    Text(RecordingDetail.subtitle(recording, home: NSHomeDirectory())).font(Brand.suit(10)).foregroundStyle(Brand.gray).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
```

- [ ] **Step 5: 그래프 카드에서 녹음 열기**

`Sources/WorkGraphApp/Resources/graph/index.html:2714`:

```js
    const OPENABLE = /^(file:.|https?:\/\/|local:\d|arxiv:.|doi:.|recording:\d)/;
```

`Sources/WorkGraphApp/Views/GraphWebView.swift` 의 `case "open":` 두 줄을 아래로 바꾼다:

```swift
            case "open":                                                    // 카드에서 자료 누르기: 자료 키(file:·웹 주소·arxiv:·doi:·local:·recording:)
                guard let uri = body["uri"] as? String else { return }
                if uri.hasPrefix("recording:") {                            // 녹음은 받아쓴 글 .md 를 연다
                    Task { @MainActor in self.state.openRecordingText(key: uri) }
                    return
                }
                guard let url = URINormalizer.openableURL(forKey: uri, home: NSHomeDirectory()) else { return }
                if !NSWorkspace.shared.open(url) { AppLog.write("열기 실패: \(uri)") }
```

- [ ] **Step 6: 스냅샷 (REC-04·05)**

`Sources/WorkGraphApp/Snapshots/SnapshotCatalog.swift` 의 `static var recording` 을 아래로 바꾸고, 도우미 세 개를 `// MARK: 예시 상태` 위에 추가한다:

```swift
    /// 녹음: 메뉴 막대(녹음 중, 받아쓰는 중, 마이크 권한 꺼짐), 보관함 녹음 상세, 보관함 목록
    static var recording: [Snapshot] {
        let menuShots = [
            shot("REC-01", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(); s.todayCount = 62; s.pendingCount = 6; s.taskList = recentTasks
                s.activeRecording = ActiveRecording(id: 1, startedAt: Date().timeIntervalSince1970 - 751)
            },
            shot("REC-02", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(); s.todayCount = 62; s.pendingCount = 6; s.taskList = recentTasks
                s.recordingWork = .transcribing(0.37)
            },
            shot("REC-03", MenuBarView()) { s in
                s.phase = .ready; s.status = collector(); s.todayCount = 62; s.pendingCount = 6
                s.recordingProblem = .microphone
            },
        ]
        return menuShots + [recordingDetailShot()] + [recordingLibraryShot()].compactMap { $0 }
    }
```

```swift
    /// 보관함 녹음 상세: 녹음 파일과 받아쓴 글이 있는 상태 (임시 폴더에 두 파일을 만든다)
    private static func recordingDetailShot() -> Snapshot {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sillog-snapshot-recording", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appendingPathComponent("7.m4a")
        let text = folder.appendingPathComponent("2026-10-10 자료구조 3주차 강의.md")
        try? Data("a".utf8).write(to: audio)
        try? Data("# 자료구조 3주차 강의".utf8).write(to: text)
        let state = AppState(preview: { s in s.phase = .ready })
        let view = RecordingDetailView(recording: sampleRecording(audioPath: audio.path, textPath: text.path)).environmentObject(state)
        return Snapshot(name: "REC-04", size: CGSize(width: 640, height: 520), view: AnyView(view))
    }

    /// 보관함 '전체 종류'에 섞인 녹음
    private static func recordingLibraryShot() -> Snapshot? {
        guard let database = try? WGDatabase.inMemory() else { return nil }
        var recording = sampleRecording(audioPath: "/tmp/7.m4a", textPath: NSHomeDirectory() + "/Documents/학교/자료구조/2026-10-10 자료구조 3주차 강의.md")
        recording.id = nil
        _ = try? RecordingStore(database).insert(recording)
        let state = AppState(preview: { s in
            s.phase = .ready; s.status = collector(); s.selectedTab = .library
            s.recordings = (try? RecordingStore(database).all()) ?? []
            let offline = OpenAICompatClient(baseURL: URL(string: "http://localhost:5010/v1")!, model: "preview", apiKey: nil)   // 그리기만 하고 부르지 않는다
            s.chat = ChatState(db: database, makeClient: { .model(offline) }, makeProjectClient: { offline })
        }, database: database)
        return Snapshot(name: "REC-05", size: window, view: AnyView(MainWindow().environmentObject(state)))
    }

    private static func sampleRecording(audioPath: String, textPath: String) -> Recording {
        Recording(id: 7, startedAt: todayAt(15, 32), endedAt: todayAt(15, 32) + 3_130, duration: 3_130, audioPath: audioPath, textPath: textPath,
                  title: "자료구조 3주차 강의", summary: "연결 리스트와 스택의 구현을 예제로 설명한 강의.",
                  transcript: "오늘은 연결 리스트를 봅니다.\n노드는 값과 다음 노드를 가리키는 포인터를 가집니다.\n스택은 리스트 앞쪽에서 넣고 뺍니다.",
                  status: .ready, readyAt: Date().timeIntervalSince1970 - 2 * 86_400)
    }
```

- [ ] **Step 7: 통과 확인과 눈으로 보기**

Run: `swift test --filter "RecordingLibraryTests|LibraryTests|ChatModelMenuTests" 2>&1 | tail -5`
Expected: 모두 통과.

Run: `rm -rf /tmp/wg-shots && WORKGRAPH_SNAPSHOT=/tmp/wg-shots swift run WorkGraphApp 2>&1 | tail -3 && ls /tmp/wg-shots | grep REC`
Expected: `REC-01.png` ~ `REC-05.png`. Read 로 REC-04·05 를 연다:
- REC-04: 제목 22pt, 날짜·길이 줄, 요약, 받아쓴 글(문단마다 빈 줄), 아래에 [듣기] "5일 뒤 지워져요" … [Finder에서 보기] [닫기].
- REC-05: 왼쪽 KIND 에 '녹음', 목록에 물결 아이콘 + "자료구조 3주차 강의" + "10월 10일 15:32  52분 10초  문서 / 학교 / 자료구조".

- [ ] **Step 8: 커밋**

```bash
git add Sources/WorkGraphApp/Views/RecordingDetailView.swift Sources/WorkGraphApp/Views/LibraryView.swift Sources/WorkGraphApp/Views/GraphWebView.swift Sources/WorkGraphApp/Resources/graph/index.html Sources/WorkGraphApp/Snapshots/SnapshotCatalog.swift Tests/WorkGraphAppTests/RecordingLibraryTests.swift
git commit -m "$(cat <<'EOF'
보관함 '녹음': 목록·상세(요약, 받아쓴 글, 7일 동안 듣기, 다시 받아쓰기), 그래프 카드에서 받아쓴 글 열기

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: 전체 확인 (테스트·스냅샷·release 빌드)

설치(`scripts/make-app.sh`)는 하지 않는다. 이 스크립트는 `~/Applications/Sillog.app` 을 덮어쓰므로 사용자가 직접 실행한다.

**Files:** 없음 (확인만. 고칠 것이 나오면 그 태스크의 파일을 고치고 그 태스크의 테스트를 다시 돌린다)

**Interfaces:** Consumes: Task 1~11 전부. Produces: 없음.

- [ ] **Step 1: 전체 테스트**

Run: `swift test 2>&1 | tail -15`
Expected: `Executed N tests, with 0 failures` (N 은 녹음 테스트를 더한 전체 수). 실패가 있으면 이름과 출력을 그대로 남긴다.

- [ ] **Step 2: 스냅샷 전체를 다시 그려 보기**

Run: `rm -rf /tmp/wg-shots && WORKGRAPH_SNAPSHOT=/tmp/wg-shots swift run WorkGraphApp 2>&1 | tail -3 && ls /tmp/wg-shots | wc -l`
Expected: 오류 없이 끝나고 PNG 가 전보다 5장 많다. Read 로 `REC-01`~`REC-05`, `OUT-06`, `OUT-06-long` 을 다시 본다 (Task 10·11 의 기준 그대로).

- [ ] **Step 3: release 빌드**

Run: `swift build -c release --product WorkGraphApp 2>&1 | tail -3`
Expected: `Build complete!` (최적화 빌드에서만 나는 오류가 없는지 본다. 설치는 하지 않는다)

- [ ] **Step 4: 남은 변경 확인**

Run: `git status --short`
Expected: 비어 있다 (모든 태스크가 커밋됐다).

---

### Task 13: 1시간 넘는 녹음을 한 번에 받아쓰는지 확인 (시험 앱)

스펙 4번: "1시간 넘는 녹음도 한 번에 되는지는 구현 때 확인하고, 안 되면 30분 안팎에서 가장 조용한 곳을 찾아 나눠 받아쓴다." 10/10 측정(8분 17초)과 같은 방법으로, 사용 중인 Sillog 이 아닌 시험 앱에서 한다.

- 음성 인식 권한 창이 뜰 수 있다(시험 앱은 처음 묻는다). 창이 뜨면 사용자에게 [허용]을 부탁한다. 사용자가 없으면 이 태스크는 사용자가 있을 때 한다.
- 시스템 설정 → 키보드 → 받아쓰기가 켜져 있어야 한다(10/10 에 켰다).

**Files:**
- Create (저장소 밖, 작업용 임시 폴더): `<scratch>/speech-probe/main.swift`, `<scratch>/speech-probe/Probe.app`
- Modify: `docs/superpowers/specs/2026-10-10-voice-recording-design.md` ("확인한 사실" 에 결과 한 줄)

**Interfaces:** Consumes: 없음. Produces: 1시간 넘는 파일의 한 번 받아쓰기 결과 (통과/실패, 걸린 시간, 발화 수).

- [ ] **Step 1: 시험 앱 만들기**

`P` 는 작업용 임시 폴더의 절대 경로다 (예: 세션 scratchpad 아래 `speech-probe`). `$P/main.swift`:

```swift
import Foundation
import Speech

// 녹음 받아쓰기 시험 앱: Probe <오디오 파일> <결과 파일>
// Sillog 과 같은 방식(기기 안, ko-KR, 문장부호, 중간 결과, 발화 끝 표시로 모으기)으로 파일 하나를 한 번에 받아쓴다
let arguments = CommandLine.arguments
let audio = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let started = Date()
var utterances: [String] = []
var pending = ""
var finished = false
var recognizer: SFSpeechRecognizer?
var task: SFSpeechRecognitionTask?

func finish(_ reason: String) {
    guard !finished else { return }
    finished = true
    if !pending.isEmpty, utterances.last != pending { utterances.append(pending) }
    let text = utterances.joined(separator: "\n")
    let seconds = Int(Date().timeIntervalSince(started))
    let report = "\(reason)\nseconds=\(seconds)\nutterances=\(utterances.count)\nchars=\(text.count)\n---\n\(text)\n"
    try? report.write(to: output, atomically: true, encoding: .utf8)
    exit(0)
}

func run() {
    guard let found = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")), found.supportsOnDeviceRecognition else { finish("NO-ON-DEVICE"); return }
    recognizer = found
    let request = SFSpeechURLRecognitionRequest(url: audio)
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    request.addsPunctuation = true
    task = found.recognitionTask(with: request) { result, error in
        if let result {
            let text = result.bestTranscription.formattedString
            if result.isFinal {
                if utterances.last != text { utterances.append(text) }
                pending = ""
                finish("FINAL")
            } else if result.speechRecognitionMetadata != nil {
                utterances.append(text)
                pending = ""
            } else {
                pending = text
            }
        }
        if let error {
            let nsError = error as NSError
            finish("ERROR \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
        }
    }
}

SFSpeechRecognizer.requestAuthorization { status in
    DispatchQueue.main.async { status == .authorized ? run() : finish("AUTH \(status.rawValue)") }
}
RunLoop.main.run()
```

빌드와 서명:

```bash
mkdir -p "$P/Probe.app/Contents/MacOS"
swiftc -O -o "$P/Probe.app/Contents/MacOS/Probe" "$P/main.swift"
cat > "$P/Probe.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.capstone.sillog.speechprobe</string>
  <key>CFBundleExecutable</key><string>Probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>녹음 받아쓰기 시험</string>
</dict></plist>
PLIST
codesign --force --sign - "$P/Probe.app"
```

Expected: 오류 없음.

- [ ] **Step 2: 짧은 파일로 권한 확인**

```bash
say -v Yuna "권한 확인용 짧은 문장입니다." -o "$P/short.aiff"
rm -f "$P/short.txt"
timeout 120 open -W -n "$P/Probe.app" --args "$P/short.aiff" "$P/short.txt"; echo "exit=$?"
head -3 "$P/short.txt"
```

Expected: 첫 줄 `FINAL`. `AUTH …` 이거나 파일이 없으면(권한 창이 떠 있음) 사용자에게 [허용]을 부탁하고 이 단계를 다시 한다.

- [ ] **Step 3: 1시간 넘는 시험 음성 만들기**

```bash
python3 - "$P/long.txt" <<'PY'
import sys
words = ["사과", "바나나", "포도", "딸기", "참외", "복숭아", "자두", "키위", "망고", "귤"]
lines = []
for i in range(1, 1301):
    word = "시작표지" if i == 1 else "중간표지" if i == 650 else "마지막표지" if i == 1300 else words[i % 10]
    lines.append(f"{i}번째 문장입니다. 오늘 고른 단어는 {word}입니다. 잠시 쉬고 다음 문장으로 넘어갑니다.")
open(sys.argv[1], "w", encoding="utf-8").write("\n".join(lines))
PY
timeout 1800 say -v Yuna -f "$P/long.txt" -o "$P/long.aiff"
afconvert -f m4af -d aac@44100 -b 64000 -c 1 "$P/long.aiff" "$P/long.m4a"
afinfo "$P/long.m4a" | grep -i "estimated duration"
```

Expected: `estimated duration` 이 3600 초보다 길다. 짧으면 `range(1, 1301)` 을 `range(1, 1601)` 로, 마지막 표지 번호를 1600 으로 바꿔 다시 만든다.

- [ ] **Step 4: 한 번에 받아쓰기**

```bash
rm -f "$P/long-result.txt"
timeout 2400 open -W -n "$P/Probe.app" --args "$P/long.m4a" "$P/long-result.txt"; echo "exit=$?"
head -4 "$P/long-result.txt"
tr -d ' \n' < "$P/long-result.txt" | grep -o "시작표지\|중간표지\|마지막표지" | sort | uniq -c
```

Expected (통과): 첫 줄 `FINAL`, 표지 세 개가 모두 나온다(적어도 `마지막표지` — 파일 끝까지 받아썼다는 뜻), `seconds=` 는 음성 길이의 1/5 보다 짧다.
실패(`ERROR …`, 시간 초과, `마지막표지` 없음)면 여기서 멈추고 결과 앞부분을 사용자에게 보인다. 나눠 받아쓰기는 사용자와 정한 뒤 따로 계획한다.

- [ ] **Step 5: 결과를 스펙에 남기고 커밋**

`docs/superpowers/specs/2026-10-10-voice-recording-design.md` 의 "## 확인한 사실" 목록 끝(음질 표 아래)에 결과를 한 줄로 더한다. 예 (숫자는 실제 값):

```text
- **1시간 넘는 파일도 한 번에** (구현 때 확인): 65분 파일을 요청 한 번에 끝까지 받아썼다(약 7분, 발화 1,300개). 나눠 받아쓰기는 넣지 않는다.
```

```bash
git add docs/superpowers/specs/2026-10-10-voice-recording-design.md
git commit -m "$(cat <<'EOF'
스펙: 1시간 넘는 녹음 한 번 받아쓰기 확인 결과

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## 설치 뒤 사용자 확인 (자동으로 하지 않는다)

사용자가 `scripts/make-app.sh` 로 설치하고 Sillog 을 다시 켠 뒤 직접 해 본다.

1. 메뉴 막대 [● 녹음 시작] → 마이크·음성 인식 권한 창에서 허용 → 아이콘이 빨간 점, 메뉴에 "녹음 중 0:05".
2. 30초쯤 말하고 [■ 끝내기] → "받아쓰는 중 N%" → "녹음을 정리하는 중" → 알림("받아쓴 녹음을 정리할까요?" 또는 "녹음을 받아썼어요").
3. `~/Documents/Sillog 녹음/` 에 `날짜 제목.md` 가 있다. 알림 [옮기기] → 파일이 옮겨지고 보관함 녹음 줄의 폴더도 바뀐다.
4. 보관함 → 녹음 → 상세: 요약, 받아쓴 글, [듣기], "7일 뒤 지워져요", [Finder에서 보기].
5. 채팅에서 "방금 녹음에서 뭐라고 했지?" → 답에 녹음 근거 칩.
6. 시스템 설정에서 받아쓰기를 끄고 녹음 → "받아쓰기가 꺼져 있어요 ↗" → 켜고 보관함 [다시 받아쓰기].
7. 녹음 중에 메뉴 [종료] → 다시 켜면 그 녹음을 이어서 받아쓴다.
