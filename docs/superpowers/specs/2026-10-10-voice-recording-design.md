# 녹음: 메뉴 막대 녹음, 기기 안 받아쓰기, 폴더 추천, 채팅·업무 연결 설계

## 배경

- 사용자 요청: "언제든 녹음을 할 수 있게 버튼 만들어주고, 녹음을 완료하면 STT해서 어떤 내용인지 확인해서 저장 위치 추천해주고, 이 파일도 언제든 참고할 수 있게".
- 사용자 결정 (10/8)
  - 녹음 대상: 마이크만.
  - 받아쓰기: 이 Mac 안에서 (Apple 음성 인식).
  - 버튼: 메뉴 막대.
  - 참고: 채팅 검색과 보관함, 그리고 업무 기록(정리)에도 연결.
  - 구조: 녹음 전용 기록. DB 에 녹음 표를 둔다.
- 사용자 결정 (10/10)
  - 받아쓴 글을 `.md` 파일로 저장하고, 그 파일의 폴더를 추천한다. 앱 안(채팅 검색, 보관함, 업무 연결)에도 들어간다.
  - 녹음 파일은 받아쓰기가 끝나면 앱 안에 7일 두었다가 자동으로 지운다. 받아쓰기가 실패한 녹음은 다시 받아쓸 수 있게 지우지 않는다.
- 지금 앱
  - 녹음·음성 인식 코드는 없다.
  - 폴더 제안(`FolderSuggester.suggest`)은 아무 경로나 받는다. 다만 파일 이름·출처·화면 맥락만 보고 내용은 읽지 않는다.
  - 채팅의 활동 기록 검색(`ContextSearch`)은 출처마다 FTS(trigram) 색인을 두고 `search_context`·`read_context` 로 찾는다.
  - 정리(`OntologyBatcher`)는 관측 행과 AI 도구 대화(`chat_messages`, `EventCompressor.merge`)를 행으로 합쳐 판정한다.
- 확인: macOS 15.7 에서 `SFSpeechRecognizer(ko-KR)` 가 기기 안 인식을 지원한다(`supportsOnDeviceRecognition == true`).

## 확인한 사실 (10/10, 시험 앱으로 이 Mac 에서 측정)

시험 음성은 macOS 음성 합성(Yuna)으로 만든 한국어 낭독이다. 길이는 1분 39초와 8분 17초이고, 문장마다 다른 단어를 하나씩 넣어(사과, 바나나, …) 받아쓴 단어 수를 셌다.

- **받아쓰기 설정이 꺼져 있으면 실패한다**: "Siri and Dictation are disabled"(`kLSRErrorDomain` 201). 기기 안 인식은 시스템 설정 → 키보드 → 받아쓰기가 켜져 있어야 동작한다.
- **1분 제한이 없다**: 8분 17초 파일 하나를 요청 한 번에 처음부터 끝까지 받아썼다(약 40~50초, 실제 길이의 약 10배 속도). 1분 제한은 서버 인식 이야기다.
- **결과는 발화마다 나뉜다**: 말이 쉬는 틈마다 결과가 새로 시작되고, 마지막(`isFinal`) 결과에는 마지막 발화만 남는다. 중간 결과를 켜고(`shouldReportPartialResults`), 발화가 끝났다는 표시(`speechRecognitionMetadata`)가 붙은 결과를 차례로 모아야 전체 글이 된다.
- **음질과 정확도** (8분 17초, 단어 90개 중 받아쓴 수)

  | 형식 | 1시간당 크기 | 받아쓴 단어 |
  |---|---|---|
  | 16kHz 무압축 | 110MB | 81 |
  | 44.1kHz AAC 64kbps | 28MB | 82 |
  | 22.05kHz AAC 48kbps | 21MB | 80 |
  | 16kHz AAC 40kbps | 18MB | 70 |
  | 16kHz AAC 32kbps | 14MB | 57 |
  | 16kHz AAC 16kbps | 7MB | 40 |

  샘플레이트를 낮춘 것 자체는 괜찮지만(16kHz 무압축 81), 16kHz 에서 비트레이트를 낮게 압축하면 정확도가 떨어진다. 22.05kHz 48kbps 가 크기 대비 가장 낫다.

## 목표

- 메뉴 막대에서 한 번 눌러 녹음을 시작하고 끝낸다. 녹음 중인 것은 메뉴 막대 아이콘으로 알 수 있다.
- 끝내면 손대지 않아도 받아쓰기, 제목 붙이기, 폴더 추천까지 이어진다.
- 받아쓴 글은 `.md` 파일로 내용에 맞는 폴더에 놓이고, 어느 채팅에서든 찾아 인용할 수 있다. 보관함에서 읽을 수 있고(7일 안에는 들을 수도 있다), 다음 정리에서 업무에 붙는다.
- 녹음 파일은 Mac 밖으로 나가지 않고 7일 뒤 지워진다. 받아쓴 글은 다른 기록처럼 정리·채팅 때 연결한 AI 로 간다.

## 흐름

1. **시작**
   - 메뉴 막대 [● 녹음 시작]을 누른다.
   - 마이크와 음성 인식 권한을 확인한다. 처음 한 번은 시스템 창이 뜬다.
   - 앱 데이터 폴더 `~/Library/Application Support/WorkGraph/recordings/<id>.m4a` 에 녹음한다(AAC, 44.1kHz, 모노, 64kbps — 1시간에 약 28MB). 7일 뒤 지울 임시 파일이라 위 측정에서 가장 정확했던 형식을 쓴다.
   - `recordings` 행을 만든다(`status = recording`).
2. **녹음 중**
   - 메뉴 막대 아이콘이 빨간 점으로 바뀐다.
   - 메뉴를 열면 "녹음 중 12:31"과 [■ 끝내기]가 보인다. 일시정지는 없다.
3. **끝내기**: 파일을 닫고 `status = transcribing` 으로 바꾼 뒤 받아쓰기를 시작한다. 메뉴 막대에 "받아쓰는 중 37%"를 보인다. DB 상태는 받아쓰기부터 폴더 추천까지 `transcribing` 이다.
4. **받아쓰기**
   - 파일 하나를 `SFSpeechURLRecognitionRequest`(기기 안, ko-KR, 문장부호 넣기, 중간 결과 켬) 한 번으로 받아쓴다. 조각으로 자르지 않는다(위 측정: 1분 제한 없음).
   - 발화가 끝났다는 표시가 붙은 결과를 차례로 모아 `transcript` 에 저장한다. 진행률은 마지막 단어의 시각 ÷ 녹음 길이다.
   - 받아쓰기 설정이 꺼져 있으면(201) 녹음은 두고 "받아쓰기가 꺼져 있어요"를 안내한다. 켜면 보관함에서 [다시 받아쓰기].
   - 8분 17초까지 확인했다. 1시간 넘는 녹음도 한 번에 되는지는 구현 때 확인하고, 안 되면 30분 안팎에서 가장 조용한 곳을 찾아 나눠 받아쓴다.
5. **제목과 받아쓴 글 파일**
   - 빠른 모델(`makeQuickClient`)에 받아쓴 글 앞부분(최대 4,000자)을 보내 제목(20자 안팎)과 한 줄 요약을 받는다. 모델이 실패하면 제목은 "녹음 2026-10-10 15-32"로 한다.
   - `~/Documents/Sillog 녹음/2026-10-10 자료구조 3주차 강의.md` 를 만든다. 같은 이름이 있으면 " (2)"를 붙인다.
   - 내용: 제목(`#`), 녹음 시각과 길이, 요약, 받아쓴 글(발화마다 한 문단).
6. **폴더 추천**
   - 기존 `FolderSuggester.suggest` 를 `.md` 파일에 부른다. 녹음 종류임을 알리고, 내용 발췌(요약과 받아쓴 글 앞 800자)를 넘긴다.
   - 추천이 있으면 파일 탭 카드와 알림이 생긴다: "받아쓴 녹음을 정리할까요? '2026-10-10 자료구조 3주차 강의.md'를 '학교/자료구조'로 옮겨 보세요." [옮기기] [무시]. 되돌리기도 기존대로 된다.
   - 옮기면 `recordings.text_path` 를 새 경로로 바꾼다.
   - 추천이 없으면 "녹음을 받아썼어요" 알림만 띄운다.
   - 끝나면 `status = ready`.
7. **녹음 파일 지우기**
   - 앱이 켜질 때와 하루 한 번, `ready` 가 된 지 7일 지난 녹음 파일을 지우고 `audio_deleted_at` 을 남긴다.
   - 받아쓰기가 실패한 녹음(`failed`)은 지우지 않는다.
8. **참고**
   - 채팅: `recording:<id>` 출처로 찾고 읽는다.
   - 보관함: '녹음' 묶음에 보인다.
   - 정리: 다음 배치에 한 행으로 들어간다.

## 구성 요소

### Core (`Sources/WorkGraphCore`)

- `Recording/Recording.swift`
  - 모델: `id, startedAt, endedAt, duration, audioPath, audioDeletedAt, textPath, title, summary, transcript, status(recording|transcribing|ready|failed), error, batchId, taskId, suggestionId`.
- `Recording/RecordingStore.swift`
  - 마이그레이션 `v16-recordings`: 표 `recordings`, 색인 `recordings_fts`(trigram; 제목+요약+받아쓴 글), 넣기·바꾸기·지우기 트리거.
  - API: `insert`, `update`, `find(id)`, `find(textPath:)`, `all()`, `unfinished()`(앱이 꺼진 동안 남은 recording·transcribing), `unprocessed(upTo:notOlderThan:)`(ready 이고 아직 어느 배치에도 안 들어간 것), `mark(ids:batchId:)`, `assign(ids:taskId:)`, `expiredAudio(now:)`(ready 된 지 7일 지났고 아직 안 지운 녹음).
- `Recording/TranscriptCollector.swift`: 인식 결과(글, 발화 끝 여부, 마지막 여부, 마지막 단어 시각)를 차례로 받아 발화별 완성 문장을 모으고 진행률을 낸다. 같은 문장이 마지막 결과로 한 번 더 오면 빼고 붙인다.
- `Recording/RecordingTitler.swift`
  - LLM 호출(도구 `name_recording` → `{title, summary}`). 받아쓴 글이 비면 부르지 않는다.
  - 파일 이름 만들기: 날짜 + 제목 + `.md`. `/ : \` 같은 쓸 수 없는 글자는 뺀다.
  - `.md` 본문 만들기: 제목, 녹음 시각과 길이, 요약, 발화별 문단.
- `Files/FolderSuggester.swift`
  - `Context` 에 `contentExcerpt: String?` 와 `kind: .download | .recording` 를 더한다.
  - 프롬프트에 `CONTENT (transcript excerpt):` 줄을 넣고, 녹음이면 "downloaded document" 대신 "voice recording" 문구를 쓴다.
  - 후보 순위에도 내용 발췌를 쓴다.
- `Ontology/EventCompressor.swift`
  - `merge(_:chats:recordings:…)` 가 녹음을 행으로 만든다.
  - 행 값: app "녹음", appBundle `sillog.recording`, type `Recording`, uri `recording:<id>`, title = 제목, snippet = 요약 + 받아쓴 글 발췌(snippetChars × 2), dwell 0(창 기록과 겹치므로 작업 시간에 더하지 않음), `recordingIds`.
- `Ontology/OntologyBatcher.swift`
  - 창 끝까지 끝난 미처리 녹음(24시간 이내, 받아쓴 글이 있는 것)을 합친다.
  - 판정 뒤에는 대화처럼 `mark`·`assign` 한다.
- `Ontology/Staged/StagePrompts.swift`: `rowsGuide` 에 녹음 행 설명을 한 줄 넣는다. app 이 "녹음"인 행은 사용자가 직접 녹음한 것이고, `text:` 에 받아쓴 글 발췌가 있다.
- `Ontology/AssignmentApplier.swift`·`TBox.resourceTypes`: `Recording` 종류를 더하고, 기본으로 자료로 본다.
- `Chat/ContextSearch.swift`
  - `recording` 출처를 검색·읽기에 넣는다.
  - 프로젝트 전용 기억이면 `recordings.task_id` 로 제한한다.

### App (`Sources/WorkGraphApp`)

- `Recording/VoiceRecorder.swift`: `AVAudioRecorder` 를 감싼다(시작, 끝, 지난 시간). 테스트용 프로토콜 `AudioRecording` 을 둔다(Core 모델 `Recording` 과 이름이 겹치지 않게).
- `Recording/SpeechTranscriber.swift`
  - `SFSpeechRecognizer`(기기 안)를 쓴다. 파일 하나를 한 번에 받아쓰고, 결과를 `TranscriptCollector` 에 넘겨 진행 콜백을 준다.
  - 받아쓰기 설정이 꺼진 오류(`kLSRErrorDomain` 201)는 따로 알린다.
  - 테스트용 프로토콜 `Transcribing` 을 둔다.
- `AppState+Recording.swift`
  - 상태 `recording: RecordingPhase`: `idle | recording(startedAt) | transcribing(progress) | naming | failed(message)`.
  - `startRecording()`, `stopRecording()`.
  - 파이프라인: 받아쓰기 → 제목 → 이름 바꾸기 → 폴더 추천 → 알림.
  - `retranscribe(id)`.
  - 앱을 시작할 때 `unfinished()` 를 이어서 처리한다.
- `Views/MenuBarView.swift`
  - 정상 화면 아래쪽, [지금 정리] 위에 녹음 줄을 둔다.
    - 평소: [● 녹음 시작].
    - 녹음 중: "● 녹음 중 12:31" [■ 끝내기].
    - 받아쓰는 중: "받아쓰는 중 37%".
    - 제목·폴더 고르는 중: "녹음을 정리하는 중".
  - 권한이 꺼져 있으면 "마이크 권한이 꺼져 있어요 ↗" 를, 받아쓰기 설정이 꺼져 있으면 "받아쓰기가 꺼져 있어요 ↗" 를 보인다. 누르면 해당 시스템 설정(개인정보 보호의 마이크 / 키보드의 받아쓰기)을 연다.
  - `MenuBarLabel` 은 녹음 중일 때 빨간 점 아이콘이다.
- `Views/LibraryView.swift`
  - 종류에 '녹음'을 더한다. 목록 줄은 제목, 날짜, 길이, 폴더다.
  - 상세: 요약, 받아쓴 글, [Finder에서 보기](`.md`), 재생(`AVAudioPlayer`, 녹음 파일이 남아 있는 7일 동안만, "N일 뒤 지워져요"), [다시 받아쓰기](실패했을 때).
- `SuggestionNotifier`·`FileSuggestionCopy`: 녹음용 문구를 더한다.
- `GraphWebView`: 카드에서 `recording:<id>` 를 열면 받아쓴 글 `.md` 파일을 연다.
- `AppState+Files.swift`: 폴더 제안을 받아들이거나 되돌릴 때, 그 파일이 녹음의 `.md` 면 `recordings.text_path` 도 바꾼다.
- `ChatMessageText`: 인용 패턴에 `recording` 을 더한다(근거 칩).
- `scripts/make-app.sh`: Info.plist 에 `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` 을 더한다.
- `WorkGraphCollectors/Permissions.swift`: `Pane` 에 마이크와 음성 인식을 더한다(시스템 설정 열기).

## 오류와 경계

- **권한 거절**: 녹음을 시작하지 않고 메뉴 막대에 안내를 보인다.
- **녹음 중 앱이 꺼짐**: 다음 실행 때 `status = recording` 인 행을 본다. 파일이 읽히면 받아쓰기부터 이어 가고, 안 읽히면 `failed`.
- **받아쓰기 설정 꺼짐**: 녹음 시작 전에 확인할 방법이 없으므로(권한은 따로), 받아쓰기 때 201 오류로 알게 된다. `failed`(이유: 받아쓰기 꺼짐)로 두고 메뉴 막대와 보관함에서 켜는 방법을 안내한다.
- **받아쓰기 실패**(인식기를 쓸 수 없음 등): `failed` 와 이유를 남긴다. 파일은 그대로 두고, 보관함에서 [다시 받아쓰기].
- **짧거나 소리가 없는 녹음**(1초 미만, 또는 받아쓴 글이 빔): 이름과 폴더 추천을 생략하고 정리 행에도 넣지 않는다. 보관함에는 보인다.
- **파일이 옮겨지거나 지워짐**(앱 밖에서): 보관함에 "파일을 찾을 수 없어요"를 보인다. 받아쓴 글은 남는다.
- 한 번에 하나만 녹음한다. 녹음 중에는 시작 버튼 대신 끝내기가 보인다.
- 수집 일시정지와는 따로 동작한다. 녹음은 사용자가 직접 누른 것이기 때문이다.
- 녹음 파일은 7일 규칙으로만 지운다. 받아쓴 글 `.md` 는 사용자 파일이라 앱이 지우지 않는다.
- 저장 공간 화면(`StorageUsage`)에 앱 안 녹음 폴더 크기를 더한다.
- `.md` 를 사용자가 고쳐도 앱 안의 받아쓴 글에는 반영하지 않는다.

## 하지 않는 것

- 컴퓨터 소리 녹음, 화자 구분, 실시간 자막, 녹음 일시정지, 전역 단축키, 클라우드 받아쓰기, 녹음 편집, 고친 `.md` 다시 읽기.

## 테스트

- **Core 단위**
  - `RecordingStore`: 마이그레이션, FTS 검색, 미처리·표시·배정, 남은 녹음, 7일 지난 녹음 고르기(실패한 것은 빼기).
  - `TranscriptCollector`: 발화별 결과 모으기, 마지막 결과 중복 빼기, 진행률.
  - 제목 응답 해석, `.md` 파일 이름과 본문 만들기(가짜 LLM).
  - `FolderSuggester` 프롬프트의 내용 줄과 녹음 문구.
  - `EventCompressor.merge` 의 녹음 행.
  - `OntologyBatcher` 가 녹음을 행에 넣고 배정을 반영하는지(메모리 DB + 가짜 LLM).
  - `ContextSearch` 의 recording 검색·읽기와 프로젝트 전용 제한.
- **App**
  - 가짜 녹음기·가짜 받아쓰기·가짜 LLM 으로 상태가 바뀌는 순서, `.md` 만들기, 제안 만들기, 제안을 받아들이면 `text_path` 가 바뀌는지, 남은 녹음 이어 처리, 7일 지난 녹음 파일 지우기.
  - 스냅샷: 메뉴 막대(녹음 중, 받아쓰는 중, 권한 꺼짐), 보관함 녹음 상세.
- **실제 마이크·음성 인식**: 시스템 권한 창이 떠서, 설치 뒤 사용자가 직접 한 번 녹음해 확인한다. 사용 중인 앱은 자동으로 조작하지 않는다.
