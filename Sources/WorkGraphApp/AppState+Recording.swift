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
