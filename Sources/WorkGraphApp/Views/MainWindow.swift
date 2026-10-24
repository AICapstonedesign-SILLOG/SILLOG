import SwiftUI
import WorkGraphCore

/// 창 맨 왼쪽 세로 막대: 그래프, 채팅, 기록 자료, 설정 아이콘과 맨 아래 계정 동그라미
struct NavRail: View {
    static let width: CGFloat = 48
    @EnvironmentObject private var state: AppState

    private func icon(_ tab: MainWindow.Tab) -> String {
        switch tab {
        case .graph: "point.3.connected.trianglepath.dotted"
        case .chat: "bubble.left"
        case .records: "tray.full"
        case .settings: "gearshape"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(MainWindow.Tab.allCases) { tab in
                let on = state.selectedTab == tab
                Button { state.selectedTab = tab } label: {
                    Image(systemName: icon(tab)).font(.system(size: 15, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Brand.ink : Brand.tabText)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color(hex: 0xF7F5F2) : .clear))   // 고른 탭 알약, 흰색보다 한 단계 어둡게
                        .hoverHighlight(cornerRadius: 10, active: !on)
                        .overlay(alignment: .topTrailing) {
                            if tab == .records, state.pendingFileSuggestions > 0 { Circle().fill(Brand.sky).frame(width: 7, height: 7).offset(x: -3, y: 4) }   // 아이콘만이라 숫자 대신 점
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .railLabel(tab.rawValue)
                .accessibilityLabel(tab.rawValue)
            }
            Spacer(minLength: 0)
            AccountDot()
        }
        .padding(.top, 10).padding(.bottom, 12).padding(.horizontal, 6)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Color(hex: 0xEFECE9))                    // 창 머리와 같은 톤, 흰색보다 한 단계 낮춤
        .overlay(alignment: .trailing) { Rectangle().fill(Brand.hairline).frame(width: 1) }
    }
}

/// 아이콘 줄 맨 아래 계정 동그라미: 로그인한 이메일 앞 두 글자. 누르면 설정의 AI 연결
private struct AccountDot: View {
    @EnvironmentObject private var state: AppState
    private var email: String? { if case .loggedIn(let email, _, _) = state.codexStatus { return email }; return nil }
    var body: some View {
        let initials = String((email ?? "?").prefix(2)).uppercased()
        Button { state.settingsSection = .ai; state.selectedTab = .settings } label: {   // 계정 연결은 AI 연결 구역
            Text(initials).font(Brand.suit(11, .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Circle().fill(Brand.ink))
                .frame(width: 36, height: 36).contentShape(Circle())
        }
        .buttonStyle(.plain).railLabel(email ?? "계정").accessibilityLabel("계정 \(email ?? "")")
    }
}

/// 아이콘 줄 이름표: 커서를 대면 오른쪽에 작은 이름표가 바로 뜬다 (기본 도움말은 늦게 떠서)
private struct RailLabel: ViewModifier {
    let text: String
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .onHover { hover = $0 }
            .overlay(alignment: .leading) {
                if hover {
                    Text(text).font(Brand.suit(11, .medium)).foregroundStyle(.white).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Brand.ink.opacity(0.88)))
                        .offset(x: 44).allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}
private extension View { func railLabel(_ text: String) -> some View { modifier(RailLabel(text: text)) } }

/// 창 머리 오른쪽 위: 녹음과 지금 정리. 메뉴 막대 아이콘이 노치 뒤로 가려져도 창에서 녹음할 수 있다
struct TitleBarControls: View {
    var body: some View {
        HStack(spacing: 16) {
            RecordingTitleControl()
            TitleRefresh()
        }
        .padding(.trailing, 14)                                   // 아래 본문 오른쪽 끝과 맞춘다
    }
}

/// 창 머리의 녹음: 메뉴 막대 녹음 줄과 같은 상태를 보인다. 평소 [● 녹음 시작], 녹음 중 "● 녹음 중 12:31" [■ 끝내기], 정리 중 "받아쓰는 중 37%".
/// 새 녹음은 로그인을 마친 뒤에만, 끝내기는 언제나
private struct RecordingTitleControl: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            if let problem = state.recordingProblem { problemButton(problem) }
            if let active = state.activeRecording {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("녹음 중 \(RecordingText.clock(context.date.timeIntervalSince1970 - active.startedAt))")
                            .font(Brand.suit(11)).foregroundStyle(Brand.tabText).monospacedDigit()
                    }
                }
                Button { Task { await state.stopRecording() } } label: {
                    HStack(spacing: 5) {
                        Rectangle().fill(Brand.ink).frame(width: 7, height: 7)
                        Text("끝내기").font(Brand.suit(11, .medium)).foregroundStyle(Brand.ink)
                    }
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xF3F1EF)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if state.phase == .ready {
                if let work = state.recordingWork {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(work.menuText).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
                    }
                }
                Button { Task { await state.startRecording() } } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text("녹음 시작").font(Brand.suit(11))
                    }
                    .foregroundStyle(Brand.tabText)
                    .padding(.horizontal, 8).frame(height: 26)
                    .hoverHighlight(cornerRadius: 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("마이크로 녹음하고, 끝내면 이 Mac 안에서 받아씁니다")
            }
        }
    }

    /// 권한·받아쓰기 설정이 꺼져 있으면: 넓으면 문구, 좁으면 아이콘. 누르면 고칠 시스템 설정을 연다
    private func problemButton(_ problem: RecordingProblem) -> some View {
        Button { problem.openSettings() } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 11))
                    Text(problem.text).font(Brand.suit(11)).lineLimit(1)
                }
                Image(systemName: "exclamationmark.circle").font(.system(size: 12))
            }
            .foregroundStyle(Brand.tabText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(problem.text)
    }
}

/// 창 머리의 지금 정리: [↻ 지금 정리 14] (아이콘만으로는 알아보기 어려워 글자와 대기 수). 정리하는 동안에는 "정리하는 중…" (OUT-W5)
private struct TitleRefresh: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        if state.batchRunning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("정리하는 중…").font(Brand.suit(11)).foregroundStyle(Brand.tabText)
            }
        } else {
            Button { Task { await state.runBatch(force: true) } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                    Text("지금 정리").font(Brand.suit(11))
                    if state.pendingCount > 0 { Text("\(state.pendingCount)").font(Brand.jost(12)).foregroundStyle(Brand.gray) }
                }
                .foregroundStyle(Brand.tabText)
                .padding(.horizontal, 8).frame(height: 26)
                .hoverHighlight(cornerRadius: 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("아직 정리되지 않은 활동을 지금 바로 그래프에 반영합니다")
        }
    }
}

/// 업무 패널(업무 드로어): 그래프 탭에서 아이콘 줄 오른쪽에 열려 있는 업무 목록. 업무를 누르면 상세가 오른쪽으로 펼쳐지며 그래프를 덮지 않고 밀어낸다(그래프 폭이 줄어든다).
/// ×나 Esc 로 접는다. 업무 상세는 이 드로어 하나다: 그래프에서 업무를 눌러도(AppState.openTaskDetail) 같은 드로어가 그 업무로 열린다. 다른 탭으로 가면 접힌다
struct TasksPanel: View {
    static let listWidth: CGFloat = 277                         // 업무 목록 276 + 구분선 1
    static let maxDetail: CGFloat = 460
    static let minDetail: CGFloat = 340
    static let contentKeeps: CGFloat = 480                      // 드로어를 열어도 본문(그래프, 채팅)에 남기는 폭

    /// 상세 폭: 넓은 창에서는 460, 좁으면 본문에 480을 남기고 줄인다. 340 아래로는 안 줄인다. available = 창 폭 - 아이콘 줄 - 업무 목록
    static func detailWidth(available: CGFloat) -> CGFloat {
        max(minDetail, min(maxDetail, available - contentKeeps))
    }

    @EnvironmentObject private var state: AppState
    /// 펼쳤을 때 상세 폭 (창 폭에 맞춰 MainWindow 가 정한다)
    var detailWidth: CGFloat = TasksPanel.maxDetail

    private var expanded: Bool { state.taskDetailOpen }

    var body: some View {
        TasksView(selectedTask: state.selectedTaskId, showsDetail: expanded, onSelect: { state.openTaskDetail(id: $0) })   // 접히면 상세를 아예 안 그린다 (가려진 상세가 본문 클릭을 가로채지 않게)
            .frame(width: expanded ? Self.listWidth + detailWidth : Self.listWidth, alignment: .leading)
            .clipped()
            .overlay(alignment: .trailing) { if expanded { Rectangle().fill(Brand.hairline).frame(width: 1) } }   // 밀려난 본문과 나누는 선
            .overlay(alignment: .topTrailing) {
                if expanded {
                    Button { state.taskDetailOpen = false } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.tabText)
                            .frame(width: 26, height: 26).background(Circle().fill(Color.black.opacity(0.05))).contentShape(Circle())
                    }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).help("업무 상세 닫기 (Esc)")
                    .padding(10)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.22), value: expanded)
    }
}

/// 기록 자료 탭: 위쪽 글자 탭(파일 · 보관함)과 고른 구역. 활동 로그는 설정의 세 번째 탭
struct RecordsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case files = "파일", library = "보관함"
        var id: String { rawValue }
    }

    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            TextTabs(selection: $state.recordsSection) { $0 == .files ? state.pendingFileSuggestions : 0 }
            Group {
                switch state.recordsSection {
                case .files: FilesView()
                case .library: if let chat = state.chat { LibraryView(library: chat.library) } else { Color.white }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 창 바탕을 유리로: 흰색을 직접 칠하지 않은 사이드바와 탭 막대 뒤로 바탕화면이 흐리게 비친다(마누스 시제품과 같은 구조).
/// 창을 투명하게 하고 창 뒤를 흐린 뒤(WindowBlur) 흰 막을 얹는다. macOS 기본 유리는 흐림·흰 막을 정할 수 없어 하얗게 막혀 보인다
private struct WindowGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        let glass = content
            .background(Group {
                if WindowBlur.available { Color.white.opacity(Brand.glassWhite) } else { BehindWindowGlass() }
            }.ignoresSafeArea())
            .background(ClearWindow())
        if #available(macOS 15.0, *) { glass.containerBackground(.clear, for: .window) } else { glass }
    }
}

/// 이 뷰가 들어간 창을 투명하게 하고 창 뒤를 흐린다 (불투명한 창은 유리를 칠해도 뒤가 아니라 창 바탕이 보인다)
private struct ClearWindow: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            WindowBlur.apply(Brand.glassBlur, to: window)
            DispatchQueue.main.async { [weak window] in            // 창이 화면에 올라간 뒤 한 번 더 (창 번호가 그때 정해지는 경우)
                if let window { WindowBlur.apply(Brand.glassBlur, to: window) }
            }
        }
    }
    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ nsView: View, context: Context) {}
}

/// 창 뒤 흐림 반경을 정하는 macOS 비공개 함수 (iTerm2 의 '흐림' 설정이 쓰는 것).
/// 없는 macOS 에서는 available 이 false 이고, 창 바탕은 기본 유리(BehindWindowGlass)로 그린다
enum WindowBlur {
    private typealias SetRadius = @convention(c) (UInt32, UInt32, UInt32) -> Int32
    private typealias Connection = @convention(c) () -> UInt32
    private static let functions: (set: SetRadius, connection: Connection)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let set = dlsym(handle, "CGSSetWindowBackgroundBlurRadius"),
              let connection = dlsym(handle, "CGSDefaultConnectionForThread") else { return nil }
        return (unsafeBitCast(set, to: SetRadius.self), unsafeBitCast(connection, to: Connection.self))
    }()

    static var available: Bool { functions != nil }

    /// 창 뒤를 radius 만큼 흐린다. 창 번호가 아직 없거나 함수가 없으면 false
    @discardableResult
    static func apply(_ radius: Int, to window: NSWindow) -> Bool {
        guard let functions, window.windowNumber > 0 else { return false }
        return functions.set(functions.connection(), UInt32(window.windowNumber), UInt32(radius)) == 0
    }
}

/// macOS 15부터 창 제목 글자를 숨긴다 (창 머리에는 오른쪽 위 녹음·지금 정리만)
private struct HideWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.toolbar(removing: .title) } else { content }
    }
}

struct MainWindow: View {
    enum Tab: String, CaseIterable, Identifiable {
        case graph = "그래프", chat = "채팅", records = "기록 자료", settings = "설정"   // 업무는 그래프 옆 패널(TasksPanel), 파일·보관함·활동 로그는 기록 자료 안 구역
        var id: String { rawValue }
    }

    @EnvironmentObject private var state: AppState
    /// WORKGRAPH_TAB=chat|records|files|library|settings|activity 로 시작 탭을 고를 수 있다 (개발·스크린샷용).
    static let initialTab: Tab = {
        switch ProcessInfo.processInfo.environment["WORKGRAPH_TAB"] {
        case "settings", "activity": return .settings
        case "chat": return .chat
        case "records", "files", "library": return .records
        default: return .graph                                   // 권한·로그인 안내는 온보딩이 맡는다
        }
    }()
    /// WORKGRAPH_TAB=library 면 기록 자료의 보관함으로 시작한다
    static let initialRecordsSection: RecordsView.Section = ProcessInfo.processInfo.environment["WORKGRAPH_TAB"] == "library" ? .library : .files
    /// WORKGRAPH_TAB=activity 면 설정의 활동 로그로 시작한다
    static let initialSettingsSection: SettingsView.Section = ProcessInfo.processInfo.environment["WORKGRAPH_TAB"] == "activity" ? .activity : .general

    private var ready: Bool { state.startupError == nil && state.bootstrapped && state.phase == .ready }
    /// 기기 코드 로그인이 꺼진 계정: 탭 대신 OUT-W1 카드
    private var loginBlocked: Bool { state.loginBlocked && state.phase == .login }
    /// 시작 실패·불러오는 중·로그인 오류가 아니면 탭이 보이고, 온보딩은 그 위에 시트로 뜬다
    private var showsTabs: Bool { state.startupError == nil && state.bootstrapped && !loginBlocked }
    /// 온보딩 시트가 떠 있으면 시트 뒤 탭은 눌리지도(Return 같은 키보드 단축키 포함) 읽히지도 않는다
    private var sheetShown: Bool { showsTabs && state.onboardingStep != nil }

    var body: some View {
        // 왼쪽부터 아이콘 줄, 업무 드로어(목록, 펼치면 상세), 본문. 상세가 펼쳐지면 본문을 덮지 않고 오른쪽으로 밀어 본문 폭이 줄어든다
        GeometryReader { geo in
            let available = geo.size.width - (showsTabs ? NavRail.width : 0) - TasksPanel.listWidth
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if showsTabs { Color.clear.frame(width: NavRail.width) }
                    if ready && state.selectedTab == .graph { TasksPanel(detailWidth: TasksPanel.detailWidth(available: available)) }   // 업무 목록은 그래프 옆에만 (채팅·기록 자료·설정은 본문만)
                    Group {
                        if let error = state.startupError {
                            BrandStartupErrorView(message: error)
                        } else if !state.bootstrapped {
                            BrandLoadingView()
                        } else if loginBlocked {
                            LoginBlockedView()
                        } else {
                            switch state.selectedTab {
                            case .graph: GraphWebView(version: state.graphVersion).ignoresSafeArea(edges: .bottom)   // 웹 페이지의 빈 곳으로 창 바탕 유리가 보인다
                            case .chat: if let chat = state.chat {
                                ChatView(chat: chat, library: chat.library, modelName: state.settings.chatModelName,
                                         openSettings: { state.settingsSection = .ai; state.selectedTab = .settings },   // 모델 메뉴의 설정 → AI 연결
                                         pendingRecords: state.pendingCount, tidyNow: { Task { await state.runBatch(force: true) } })
                            }
                            case .records: RecordsView()
                            case .settings: SettingsView()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if showsTabs { NavRail() }                          // 맨 위: 이름표가 업무 목록 위로 나오게
            }
        }
        .onChange(of: state.selectedTab) { _, _ in state.taskDetailOpen = false }   // 탭을 바꾸면 드로어를 접는다 (채팅 탭에는 업무 패널이 없다)
        .disabled(sheetShown)
        .accessibilityHidden(sheetShown)
        .overlay {
            if showsTabs, let step = state.onboardingStep { OnboardingOverlay(step: step) }
        }
        .frame(minWidth: 1040, minHeight: 560)                  // 아이콘 줄 48 + 업무 목록 277 + 채팅 최소 700(대화 목록 200 + 본문 500)
        .sheet(item: $state.resumeRequest) { request in ResumeSheet(request: request).environmentObject(state) }
        .toolbar {
            if showsTabs {                                       // 녹음, 지금 정리: 창 머리 오른쪽 위
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.flexible)
                    ToolbarItem { TitleBarControls() }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem { Spacer() }                     // macOS 15 는 항목을 왼쪽부터 놓는다(primaryAction 도 왼쪽). 빈 칸으로 오른쪽 끝에 민다
                    ToolbarItem { TitleBarControls() }
                }
            }
        }
        .toolbarBackground(Color(hex: 0xEFECE9), for: .windowToolbar)
        .modifier(HideWindowTitle())
        .modifier(WindowGlassBackground())
        .task { await state.bootstrap() }
        .onChange(of: state.phase) { old, phase in
            // 온보딩을 막 끝냈을 때만 그래프 탭으로. 앱 시작 시의 login → ready 전환은 탭을 건드리지 않는다.
            if phase == .ready { state.refresh() }
            if phase == .ready, old == .permissions { state.selectedTab = .graph }
        }
        .onAppear { state.refresh() }
    }
}
