import AppKit
import ServiceManagement
import SwiftUI
import WorkGraphCollectors
import WorkGraphCore

/// 설정 탭: 위쪽 글자 탭(일반, AI 연결, 활동 로그)과 그 아래 한 쪽. 일반은 권한, 수집, 개인정보와 저장 공간, 앱 실행을 한 쪽에 잇는다. Figma ST-01~06, ST-W1~W8.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = false
    @State private var launchStatusLoaded = false
    @State private var launchError: String?

    enum Section: String, CaseIterable, Identifiable {
        case general = "일반"                            // 권한, 수집, 개인정보와 저장 공간, 앱 실행
        case ai = "AI 연결"
        case activity = "활동 로그"                       // 무엇을 기록하고 언제 정리했는지 (수집 설정 가까이)
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextTabs(selection: $state.settingsSection)
            if state.settingsSection == .activity {
                ActivityLogView().frame(maxWidth: .infinity, maxHeight: .infinity)   // 자기 표와 스크롤이 있다
            } else {
                ScrollView {
                    content
                        .padding(.horizontal, state.settingsSection == .ai ? 64 : 34)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.white)
            }
        }
        .onChange(of: state.settings) { _, _ in state.applySettings() }
        .onChange(of: state.settings.llmProvider) { _, _ in state.updateCodexModelProviders() }
        .onChange(of: state.settings.chatProvider) { _, _ in state.updateCodexModelProviders() }
        .onAppear { state.refreshCodexStatus() }
        .task {
            // 로그인 항목 상태 조회는 수 초 걸릴 수 있는 동기 XPC 호출이라 메인 스레드 밖에서 읽는다.
            let enabled = await Task.detached(priority: .utility) { SMAppService.mainApp.status == .enabled }.value
            launchAtLogin = enabled
            try? await Task.sleep(nanoseconds: 100_000_000)
            launchStatusLoaded = true
        }
    }

    @ViewBuilder private var content: some View {
        switch state.settingsSection {
        case .general: general
        case .ai: aiConnection
        case .activity: EmptyView()                      // 위에서 따로 그린다
        }
    }

    // MARK: 일반

    /// 일반: 예전 권한, 수집, 개인정보와 저장 공간, 일반 네 구역을 한 쪽에 잇는다
    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("권한"); permissions
            SectionLabel("수집"); collection
            privacy
            SectionLabel("앱 실행"); appLaunch
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
            permissionTile("손쉬운 사용", icon: "hand.raised",
                           detail: state.status.accessibility ? "창 제목, 주소, 문서 경로, 화면 텍스트를 읽어요." : "꺼져 있어 지금은 앱 이름만 기록하고 있어요.",
                           granted: state.status.accessibility) {
                _ = Permissions.accessibility(prompt: true)
                Permissions.openSettings(.accessibility)
            }
            permissionTile("화면 기록", icon: "camera.viewfinder",
                           detail: state.status.screenRecording ? "스크린샷을 남기고, 글자를 읽을 수 없는 화면은 OCR로 읽어요." : "꺼져 있어 스크린샷과 화면 카드를 만들지 못해요.",
                           granted: state.status.screenRecording) {
                Permissions.requestScreenRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Permissions.openSettings(.screenRecording) }
            }
            permissionTile("알림", icon: "bell", detail: "파일 정리 제안을 알려요. 꺼져 있어도 파일 구역에서 볼 수 있어요.", granted: !state.notificationsDenied) {
                SuggestionNotifier.openSystemSettings()
            }
            }
            .padding(.top, 4)
            InfoLine("화면 기록은 허용한 뒤 앱을 다시 실행해 주세요.")
        }
    }

    /// 권한 하나를 한눈에: 이름, 허용 상태(아이콘과 글), 하는 일 또는 꺼졌을 때 못 하는 일, 허용 단추
    private func permissionTile(_ title: String, icon: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        let color = granted ? ActivityLogView.okColor : ActivityLogView.failColor
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Brand.ink).frame(width: 18)
                Text(title).font(Brand.suit(13, .medium)).foregroundStyle(Brand.ink)
                Spacer(minLength: 4)
                Label(granted ? "허용됨" : "꺼짐", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(Brand.suit(11, .semibold)).foregroundStyle(color)
            }
            Text(detail).font(Brand.suit(11)).foregroundStyle(Brand.tabText).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            Spacer(minLength: 12)
            if !granted { Button("허용하기", action: request).buttonStyle(BrandButtonStyle()) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(granted ? Brand.paper : ActivityLogView.failColor.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(granted ? Brand.line : ActivityLogView.failColor.opacity(0.25)))
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingCard {
            SettingRow("화면 텍스트 읽기", detail: "텍스트가 부족하면 OCR로 보충해요.") {
                Toggle("", isOn: $state.settings.captureText).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("스크린샷 저장", detail: "활성 창만 저장해요. 끄면 화면 내용 기록도 꺼져요.") {
                Toggle("", isOn: $state.settings.captureScreenshots).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("화면 내용 기록", detail: "대표 화면 이미지를 AI로 보내 화면 기억 카드를 만들어요.") {
                Toggle("", isOn: $state.settings.screenCards).toggleStyle(BrandSwitchStyle())
                    .disabled(!state.settings.captureScreenshots)
            }
            SettingRow("다운로드 폴더 새 파일 기록", detail: "다운로드 파일과 출처 URL을 기록해요.") {
                Toggle("", isOn: $state.settings.watchDownloads).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("AI 코딩 도구 대화 읽기", detail: "Claude Code와 Codex CLI에 입력한 메시지를 읽어요.") {
                Toggle("", isOn: $state.settings.readChatLogs).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("5분마다 자동으로 정리", detail: "쌓인 기록을 연결한 AI 계정으로 보내 업무를 정리해요.") {
                Toggle("", isOn: $state.settings.batchEnabled).toggleStyle(BrandSwitchStyle())
            }
            }
            InfoLine("자동 정리를 꺼도 ‘지금 정리’를 누르면 기록이 전송돼요.")
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExcludedAppsView()
            StorageSettingsView()
            SectionLabel("저장 위치")
            SettingCard {
                SettingRow("기록 폴더", detail: state.databasePath) {
                    Button("Finder에서 보기") { state.revealDataFolder() }.buttonStyle(BrandButtonStyle())
                }
            }
        }
    }

    private var appLaunch: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingCard {
            SettingRow("Dock 아이콘 표시", detail: "Dock에 SILLOG를 표시해요.") {
                Toggle("", isOn: $state.settings.showDockIcon).toggleStyle(BrandSwitchStyle())
            }
            SettingRow("로그인 시 자동 실행", detail: "Mac에 로그인하면 메뉴 막대에서 시작해요.") {
                Toggle("", isOn: $launchAtLogin).toggleStyle(BrandSwitchStyle())
                    .disabled(!launchStatusLoaded)
                    .onChange(of: launchAtLogin) { _, enabled in if launchStatusLoaded { setLaunchAtLogin(enabled) } }
            }
            }
            if let launchError {
                Text(launchError).font(Brand.suit(11)).foregroundStyle(Brand.text).padding(.vertical, 12)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = "자동 실행을 바꾸지 못했어요. build/Sillog.app으로 실행했는지 확인해 주세요. (\(error.localizedDescription))"
        }
    }

    // MARK: AI 연결

    /// 연결 구역 하나: 채팅도 같은 연결 방식, 주소, 키를 쓴다. 저장 키는 그대로 두고, 값을 바꿀 때 채팅 쪽에도 같이 적는다.
    private func chatBinding(_ main: WritableKeyPath<AppSettings, String>, _ chat: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(get: { state.settings[keyPath: main] },
                set: { state.settings[keyPath: main] = $0; state.settings[keyPath: chat] = $0 })
    }

    private var aiConnection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConnectionSection(
                provider: chatBinding(\.llmProvider, \.chatProvider),
                openAIModel: $state.settings.llmModel, chatOpenAIModel: $state.settings.chatModel,
                baseURL: chatBinding(\.llmBaseURL, \.chatBaseURL), apiKey: chatBinding(\.llmAPIKey, \.chatAPIKey),
                ajouModel: $state.settings.ajouModel, chatAjouModel: $state.settings.chatAjouModel, ajouKey: $state.settings.ajouAPIKey,
                codexModel: $state.settings.codexModel, chatCodexModel: $state.settings.chatCodexModel,
                test: { Task { await state.testLLM(); await state.testChatLLM() } })
            Text("기록은 Mac에 저장되고, 정리와 채팅을 쓸 때 창 제목, 주소, 화면 텍스트 일부, 질문, 새 파일 정보가 연결한 AI 계정으로 전송돼요. 연결 확인은 개인 자료 없이 시험 호출만 하고, 모델 사용량이 소량 발생해요.")
                .font(Brand.suit(10)).foregroundStyle(Brand.gray).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14).padding(.horizontal, 4)
        }
        .onAppear { unifyChat() }
    }

    /// 예전에 채팅만 다른 연결을 쓰던 저장값은 연결 구역 하나에 맞춘다 (모델과 저장된 다른 값은 그대로)
    private func unifyChat() {
        let c = state.settings
        if c.chatProvider != c.llmProvider { state.settings.chatProvider = c.llmProvider }
        if c.chatBaseURL != c.llmBaseURL { state.settings.chatBaseURL = c.llmBaseURL }
        if c.chatAPIKey != c.llmAPIKey { state.settings.chatAPIKey = c.llmAPIKey }
    }
}

// MARK: AI 연결 한 구역 (Figma ST-03~14, 27~36)

/// 회사별 모델 알약: 고른 것만 #6E5A4D 바탕에 흰 글씨. 목록에 없는 고른 값도 알약으로 보인다.
private struct ModelPills: View {
    let groups: [(String, [(slug: String, label: String)])]
    @Binding var selection: String

    private var listed: Bool { groups.contains { $0.1.contains { $0.slug == selection } } }
    /// 목록에 없는 모델은 직접 입력칸에 보인다 (비우면 목록 첫 모델로 돌아간다)
    private var custom: Binding<String> {
        Binding(get: { listed ? "" : selection },
                set: { selection = $0.isEmpty ? (groups.first?.1.first?.slug ?? "") : $0 })
    }

    private var shown: [(String, [(slug: String, label: String)])] {
        groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("직접 입력").font(Brand.suit(10)).foregroundStyle(Brand.gray).frame(width: 62, alignment: .leading)
                BrandInput(text: custom, placeholder: "목록에 없는 모델 이름", width: 260)
            }
            ForEach(shown.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(shown[i].0).font(Brand.suit(10)).foregroundStyle(Brand.gray).frame(width: 62, alignment: .leading)
                    ForEach(shown[i].1, id: \.slug) { model in
                        let on = model.slug == selection
                        Button { selection = model.slug } label: {
                            Text(model.label).font(Brand.suit(11, on ? .medium : .regular)).foregroundStyle(on ? .white : Brand.tabText)
                                .padding(.horizontal, 14).frame(height: 28)
                                .background(on ? Brand.accentDark : Color(hex: 0xF3F1EF), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct ConnectionSection: View {
    @EnvironmentObject private var state: AppState
    @Binding var provider: String
    @Binding var openAIModel: String
    @Binding var chatOpenAIModel: String
    @Binding var baseURL: String
    @Binding var apiKey: String
    @Binding var ajouModel: String
    @Binding var chatAjouModel: String
    @Binding var ajouKey: String
    @Binding var codexModel: String
    @Binding var chatCodexModel: String
    let test: () -> Void

    private static let ajouGroups: [(String, [(slug: String, label: String)])] = [
        ("GPT", ["gpt-6-luna", "gpt-6.1-sol", "gpt-6-sol"].map { ($0, $0) }),
        ("Claude", ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-1"].map { ($0, $0) }),
        ("Gemini", ["gemini-4-argon", "gemini-3.8-flash"].map { ($0, $0) }),
    ]

    private var testing: Bool { state.llmTestResult == "확인 중…" || state.chatTesting }

    /// 연결 상태 글: 정리 확인이 실패면 그것, 성공이면 채팅 확인이 실패인지 본다
    private var result: String? {
        guard let llm = state.llmTestResult else { return nil }
        if testing { return "확인 중…" }
        if !llm.hasPrefix("연결됨") { return llm }
        if let chat = state.chatTestResult, !chat.hasPrefix("연결됨") { return chat }
        return llm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("연결").padding(.top, 18)
            SettingCard {
                SettingRow("연결 방식") {
                    BrandMenu(selection: $provider, options: [("codex", "ChatGPT 로그인"), ("ajou", "아주대 LLM API"), ("openai", "OpenAI 호환 서버")], width: 190)
                }
                switch provider {
                case "ajou": ajouRows
                case "openai": openAIRows
                default: codexRows
                }
            }
            if provider == "codex" { codexExtras }
        }
    }

    /// 모델 한 줄: 제목은 왼쪽, 알약이나 입력칸은 오른쪽
    private func modelRow<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title).font(Brand.suit(13)).foregroundStyle(Brand.ink).padding(.top, 4)
            Spacer(minLength: 16)
            content()
        }
        .padding(.vertical, 16).frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    /// 연결 상태 줄: 성공은 파랑 체크와 글, 실패는 붉은 글
    private var statusRow: some View {
        SettingRow("연결 상태") {
            HStack(spacing: 10) {
                if let result {
                    let ok = result.hasPrefix("연결됨")
                    let tint = ok ? Color(hex: 0x4A86C5) : result == "확인 중…" ? Brand.gray : Color(hex: 0xC9452E)
                    HStack(spacing: 6) {
                        if ok { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)) }
                        Text(result).font(Brand.suit(11)).lineLimit(3).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }.foregroundStyle(tint)
                } else {
                    Text("확인 전").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                }
                if testing { ProgressView().controlSize(.small) }
                Button("연결 확인", action: test).buttonStyle(BrandButtonStyle()).disabled(testing)
            }
        }
    }

    /// 아주대 LLM API: 주소는 정해져 있어 키와 모델만 보인다 (키는 아주대 LLM 사이트 개발자 메뉴에서 받는다)
    @ViewBuilder private var ajouRows: some View {
        SettingRow("API 키") {
            HStack(spacing: 4) {
                Button { NSWorkspace.shared.open(AppSettings.ajouSite) } label: {
                    HStack(spacing: 3) { Text("키 받기"); Image(systemName: "arrow.up.right").font(.system(size: 8)) }
                }.buttonStyle(BrandButtonStyle()).help("아주대 LLM 개발자 메뉴에서 키를 만들어요").fixedSize()
                BrandInput(text: $ajouKey, placeholder: "아주대 LLM에서 받은 키", width: 460, secure: true)
            }
        }
        modelRow("정리 모델") { ModelPills(groups: Self.ajouGroups, selection: $ajouModel) }
        modelRow("채팅 모델") { ModelPills(groups: Self.ajouGroups, selection: $chatAjouModel) }
        statusRow
    }

    @ViewBuilder private var openAIRows: some View {
        SettingRow("서버 주소") { BrandInput(text: $baseURL, placeholder: "http://localhost:5010/v1", width: 460) }
        SettingRow("API 키", detail: "없으면 비워 둬요.") { BrandInput(text: $apiKey, placeholder: "", width: 460, secure: true) }
        SettingRow("정리 모델") { BrandInput(text: $openAIModel, placeholder: "gpt-5.4-mini", width: 460) }
        SettingRow("채팅 모델") { BrandInput(text: $chatOpenAIModel, placeholder: "gpt-5.4-mini", width: 460) }
        statusRow
    }

    /// ChatGPT 로그인: 로그인했으면 계정, 모델 알약, 사용량. 로그인 전이면 로그인 단추 한 줄
    @ViewBuilder private var codexRows: some View {
        switch state.codexStatus {
        case .loggedIn(let email, let plan, _):
            SettingRow(email ?? "ChatGPT 계정", detail: plan.map { "\($0) 요금제로 연결됨" } ?? "연결됨") {
                HStack(spacing: 8) {
                    if testing || state.codexModelsLoading { ProgressView().controlSize(.small) }
                    Button("연결 확인", action: test).buttonStyle(BrandButtonStyle()).disabled(testing)
                    Menu {
                        if state.codexModelsLoading { Button("모델 검사 중단") { state.cancelCodexModelLoading() } }
                        else { Button("모델 다시 확인") { Task { await state.loadCodexModels(force: true) } } }
                        Button("사용량 자세히 보기") { NSWorkspace.shared.open(CodexResponsesClient.usagePage) }
                        Divider()
                        Button("로그아웃") { state.logoutCodex() }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Brand.tabText).frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("더 보기")
                }
            }
            modelRow("정리 모델") { codexModelField($codexModel, state.codexModels) }
            modelRow("채팅 모델") { codexModelField($chatCodexModel, state.chatCodexModels.isEmpty ? state.codexModels : state.chatCodexModels) }
            if let usage = state.codexUsage {
                SettingRow("사용량") {
                    HStack(spacing: 18) {
                        ForEach([usage.primary, usage.secondary].compactMap { $0 }, id: \.windowSeconds) { window in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(window.label).font(Brand.suit(10)).foregroundStyle(Brand.gray)
                                    Spacer(minLength: 6)
                                    Text("\(Int(window.usedPercent.rounded()))%").font(Brand.jost(11)).foregroundStyle(Brand.text)
                                }
                                Capsule().fill(Brand.line).frame(height: 3)
                                    .overlay(alignment: .leading) {
                                        GeometryReader { g in Capsule().fill(Brand.ink.opacity(0.8)).frame(width: g.size.width * min(1, window.usedPercent / 100)) }
                                    }
                            }
                            .frame(width: 110)
                        }
                    }
                }
            }
        case .loggedOut:
            if state.deviceCode == nil {
                SettingRow("로그인 안 됨", detail: "ChatGPT 계정으로 로그인하면 정리와 채팅을 쓸 수 있어요.") {
                    Button("ChatGPT 로그인") { state.startCodexLogin() }.buttonStyle(BrandButtonStyle(kind: .primary))
                }
            }
        }
    }

    /// ChatGPT 모델 칸: 불러오는 중이면 안내, 목록이 있으면 알약, 없으면 직접 입력
    @ViewBuilder private func codexModelField(_ selection: Binding<String>, _ models: [CodexModel]) -> some View {
        if state.codexModelsLoading {
            HStack(spacing: 8) {
                Text("불러오는 중…").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                ProgressView().controlSize(.mini)
            }.frame(maxWidth: .infinity, minHeight: 26, alignment: .trailing)
        } else if models.isEmpty {
            BrandInput(text: selection, placeholder: "gpt-5.6-luna", width: 190)
        } else {
            ModelPills(groups: [("GPT", models.map { ($0.slug, $0.displayName) })], selection: selection)
        }
    }

    /// 카드 아래: 기기 코드, 확인 결과, 오류
    @ViewBuilder private var codexExtras: some View {
        if case .loggedOut = state.codexStatus, let code = state.deviceCode { deviceCodeRows(code) }
        if let result = state.llmTestResult { resultLine(result) }
        if case .loggedIn = state.codexStatus, let modelsError = state.codexModelsError { resultLine(modelsError) }
        if let message = state.codexMessage { resultLine(message) }
    }

    private func deviceCodeRows(_ code: DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("열린 브라우저에 이 코드를 입력해 주세요").font(Brand.suit(12, .medium)).foregroundStyle(Brand.text)
                .padding(.vertical, 16)
            VStack(alignment: .leading, spacing: 8) {
                Text("기기 코드").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                Text(code.userCode).font(Brand.jost(28)).tracking(1.4).foregroundStyle(Brand.ink).textSelection(.enabled)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            HStack(spacing: 10) {
                Button("코드 복사") { state.copyDeviceCode() }.buttonStyle(BrandButtonStyle())
                Button("브라우저 다시 열기") { NSWorkspace.shared.open(code.verificationURL) }.buttonStyle(BrandButtonStyle())
                Button("취소") { state.cancelCodexLogin() }.buttonStyle(BrandButtonStyle())
                ProgressView().controlSize(.small)
            }
            .padding(.top, 14)
            Text("코드는 복사돼 있어요. 브라우저에 붙여 넣으세요.").font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 10).padding(.bottom, 14)
        }
    }

    private func resultLine(_ text: String) -> some View {
        Text(text).font(Brand.suit(11)).foregroundStyle(Brand.text).textSelection(.enabled).padding(.top, 10).padding(.horizontal, 4)
    }
}

// MARK: 설정 전용 부품 (공용 부품으로 옮기면 좋음)

/// 설정 묶음: 바탕 상자 없이 줄과 선만 (미니멀)
struct SettingCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
    }
}

/// 설정 한 줄: 왼쪽 아이콘(있으면)과 제목, 오른쪽 조작 요소, 아래 구분선 (설명은 말풍선으로만)
struct SettingRow<Trailing: View>: View {
    let title: String
    let detail: String?
    var icon: String? = nil                      // SF 기호 이름, 또는 앱 아이콘 같은 이미지(iconImage)
    var iconImage: NSImage? = nil
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, detail: String? = nil, icon: String? = nil, iconImage: NSImage? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.detail = detail; self.icon = icon; self.iconImage = iconImage; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 16) {
            if let iconImage {
                Image(nsImage: iconImage).resizable().frame(width: 18, height: 18)
            } else if let icon {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Brand.tabText).frame(width: 18)
            }
            // Figma 설정 줄에는 설명이 없다: 회색 설명 글은 그리지 않고 마우스를 올리면 말풍선으로만 보인다
            Text(title).font(Brand.suit(13)).foregroundStyle(Brand.ink)
                .help(detail ?? "")
            Spacer(minLength: 16)
            trailing()
        }
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
}

/// 묶음 위 구역 제목: 작은 회색 글씨
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Brand.suit(11, .medium)).foregroundStyle(Brand.gray).padding(.horizontal, 4).padding(.top, 26).padding(.bottom, 8)
    }
}

/// 회색 안내 줄
struct InfoLine: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.horizontal, 4).padding(.vertical, 10)
    }
}

/// 회색 안내 글 (Codex 필요 안내)
struct NoteBox: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Brand.suit(11)).foregroundStyle(Brand.gray).padding(.vertical, 6)
    }
}

/// 회색 상태 배지 (허용 안 됨, 예정)
struct GrayBadge: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Brand.suit(10, .medium)).foregroundStyle(Brand.gray)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Brand.paper))
    }
}

/// 켜고 끄기: 스위치 대신 체크 표시. 켜짐 = 하늘색 체크, 꺼짐 = 옅은 빈 동그라미
struct BrandSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(configuration.isOn ? Brand.blue : Color(hex: 0xC9C4BF))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .hoverHighlight(cornerRadius: 15)
                .opacity(enabled ? 1 : 0.4)
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

/// 연결 방식, 모델 선택 상자: 밑줄 위에 고른 값과 아래 화살표
struct BrandMenu: View {
    @Binding var selection: String
    let options: [(String, String)]
    let width: CGFloat

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { option in
                Button(option.1) { selection = option.0 }
            }
        } label: {
            HStack {
                Text(options.first { $0.0 == selection }?.1 ?? selection).font(Brand.suit(11)).foregroundStyle(Brand.text).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium)).foregroundStyle(Brand.tabText)
            }
            .brandField()
            .frame(width: width)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// 한 줄 입력칸
struct BrandInput: View {
    @Binding var text: String
    let placeholder: String
    let width: CGFloat
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Brand.sub))
            } else {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Brand.sub))
            }
        }
        .textFieldStyle(.plain).font(Brand.suit(12)).foregroundStyle(Brand.text)
        .brandField(height: 38)
        .frame(width: width)
    }
}
