import SwiftUI
import WorkGraphCore

/// 대화 머리(제목 아래, 모델 칩 옆)의 범위 표시: 지금 채팅이 보는 기록 (모든 기록 · 고른 업무·분야 · 기록 안 씀). 누르면 분야→업무 나무로 바꾼다
struct ChatFocusButton: View {
    @ObservedObject var chat: ChatState
    @State private var picking = false

    var body: some View {
        let scope = chat.current.scope
        Button { picking = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "scope").font(.system(size: 9))
                Text(Self.label(scope, choices: chat.focusChoices)).font(Brand.suit(10)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(Brand.gray)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(scope.focus.isEmpty ? "답변에 쓸 내 기록의 범위 바꾸기" : "범위: " + scope.focus.map(\.title).joined(separator: ", "))
        .popover(isPresented: $picking, arrowEdge: .bottom) { ChatFocusPicker(chat: chat) }
    }

    /// 단추 글자: 모든 기록 / Flask 웹앱 개발 / 학업 · 업무 6 / Flask 웹앱 개발 외 2 / 기록 안 씀
    static func label(_ scope: ChatScope, choices: ChatFocusChoices) -> String {
        guard scope.useActivity else { return "기록 안 씀" }
        guard let first = scope.focus.first else { return "모든 기록" }
        guard scope.focus.count == 1, first.kind == .theme else { return summary(scope.focus) }
        if let count = choices.themes.first(where: { $0.focus.key == first.key })?.taskCount { return "\(short(first.title)) · 업무 \(count)" }
        return "\(short(first.title)) 분야"
    }

    /// 고른 것을 짧게: 하나면 그 이름, 여럿이면 '첫 이름 외 n' (대화 목록·입력칸 안내도 같은 말)
    static func summary(_ focus: [ChatFocus]) -> String {
        guard let first = focus.first else { return "" }
        return focus.count == 1 ? short(first.title) : "\(short(first.title)) 외 \(focus.count - 1)"
    }

    /// 긴 업무 이름은 열여덟 자에서 줄인다 (단추·입력칸 안내가 한 줄에 들어가게)
    static func short(_ title: String) -> String {
        title.count > 18 ? String(title.prefix(17)) + "…" : title
    }
}

/// 범위 고르기 창 (◎ 단추): 분야→업무 나무. 닫히면 입력칸으로 커서를 옮긴다
struct ChatFocusPicker: View {
    @ObservedObject var chat: ChatState

    var body: some View {
        ChatFocusTree(chat: chat, movesCursor: false, maxHeight: 400)
            .padding(.vertical, 8)
            .frame(width: 320)
            .onDisappear { chat.inputFocusRequest += 1 }
    }
}

/// 새 대화 첫 화면: 무엇에 대해 이야기할지 분야→업무 나무로 바로 고른다. 고를 때마다 커서가 입력칸으로 간다
struct ChatStartChoices: View {
    @ObservedObject var chat: ChatState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if chat.focusChoices.tasks.isEmpty {
                Text("업무를 찾고, 정리하고, 결과물로 이어 보세요.").font(Brand.suit(12)).foregroundStyle(Brand.gray)
            } else {
                Text("무엇에 대해 이야기할까요? 여러 개를 골라도 돼요.").font(Brand.suit(12)).foregroundStyle(Brand.gray)
                ChatFocusTree(chat: chat, movesCursor: true, maxHeight: 300)
                    .padding(.vertical, 6)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.line))
            }
        }
        .onAppear { chat.refreshFocusChoices() }
    }
}

/// 범위 나무: 왼쪽 업무 목록처럼 분야 폴더 아래 업무. 체크로 여러 개를 고른다.
/// 폴더를 체크하면 분야 전체(나중에 늘어난 업무 포함), 업무 몇 개만 체크하면 그 업무들만 (폴더는 '일부'). 아무것도 안 고르면 모든 기록
struct ChatFocusTree: View {
    @ObservedObject var chat: ChatState
    /// 고를 때마다 입력칸으로 커서를 옮길지 (첫 화면은 옮기고, 고르기 창은 닫힐 때 옮긴다)
    var movesCursor: Bool
    var maxHeight: CGFloat
    @State private var query = ""
    @State private var collapsed: Set<String> = []

    /// 분야 폴더: key 가 없으면 '분야 없음' (분야로 고를 수 없어 안의 업무를 하나씩 고른다)
    struct Folder: Identifiable, Equatable {
        let key: String?
        let title: String
        let tasks: [ChatFocus]
        var id: String { key ?? "" }
        var theme: ChatFocus? { key.map { ChatFocus(kind: .theme, key: $0, title: title) } }
    }

    enum Mark { case none, some, all }

    var body: some View {
        let scope = chat.current.scope
        let selection = scope.useActivity ? scope.focus : []
        let needle = query.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Brand.gray)
                TextField("업무·분야 검색", text: $query).textFieldStyle(.plain).font(Brand.suit(12))
            }
            .brandField(height: 30).padding(.horizontal, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if needle.isEmpty {
                        row(title: "모든 기록", detail: "기본", symbol: scope.useActivity && scope.focus.isEmpty ? "largecircle.fill.circle" : "circle", indent: 0) {
                            chat.setFocus([], movesCursor: movesCursor)
                        }
                    }
                    ForEach(Self.filtered(Self.folders(chat.focusChoices), query: needle)) { folder in
                        let open = !needle.isEmpty || !collapsed.contains(folder.id)
                        folderRow(folder, open: open, selection: selection)
                        if open {
                            ForEach(folder.tasks, id: \.key) { task in
                                let on = Self.isOn(task, in: folder, selection: selection)
                                row(title: task.title, detail: "", symbol: on ? "checkmark.square.fill" : "square", indent: 36) {
                                    chat.setFocus(Self.toggle(task, in: folder, selection: selection), movesCursor: movesCursor)
                                }
                            }
                        }
                    }
                    if needle.isEmpty {
                        Rectangle().fill(Brand.line).frame(height: 1).padding(.vertical, 6).padding(.horizontal, 6)
                        row(title: "기록 안 씀", detail: "웹·파일·보관함만", symbol: scope.useActivity ? "circle" : "largecircle.fill.circle", indent: 0) {
                            chat.useNoRecords()
                        }
                    }
                }
                .padding(.horizontal, 6).padding(.top, 6)
            }
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func folderRow(_ folder: Folder, open: Bool, selection: [ChatFocus]) -> some View {
        let mark = Self.mark(folder, in: selection)
        return HStack(spacing: 0) {
            Button {
                if collapsed.contains(folder.id) { collapsed.remove(folder.id) } else { collapsed.insert(folder.id) }
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Brand.gray)
                    .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 22, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(folder.title) \(open ? "접기" : "펼치기")")
            Button { chat.setFocus(Self.toggle(folder, in: selection), movesCursor: movesCursor) } label: {
                HStack(spacing: 7) {
                    Image(systemName: mark == .all ? "checkmark.square.fill" : mark == .some ? "minus.square.fill" : "square")
                        .font(.system(size: 13)).foregroundStyle(mark == .none ? Brand.gray : Brand.ink)
                    Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(Brand.tabText)
                    Text(folder.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.ink).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(folder.tasks.count)").font(.custom("Jost-Light", size: 12)).foregroundStyle(Brand.gray)
                }
                .padding(.trailing, 8).frame(height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(folder.title) 분야 \(mark == .all ? "고름" : mark == .some ? "일부 고름" : "안 고름")")
        }
        .hoverHighlight(cornerRadius: 5)
    }

    private func row(title: String, detail: String, symbol: String, indent: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 13))
                    .foregroundStyle(symbol == "square" || symbol == "circle" ? Brand.gray : Brand.ink)
                Text(title).font(Brand.suit(12)).foregroundStyle(Brand.ink).lineLimit(1)
                Spacer(minLength: 8)
                if !detail.isEmpty { Text(detail).font(Brand.suit(10)).foregroundStyle(Brand.gray).lineLimit(1) }
            }
            .padding(.leading, 8 + indent).padding(.trailing, 8).frame(height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverHighlight(cornerRadius: 5)
    }

    // MARK: 고르기 규칙 (화면 없이 시험한다)

    /// 같은 업무·분야인지 (이름은 바뀌었을 수 있어 종류와 key 로 본다)
    static func same(_ a: ChatFocus, _ b: ChatFocus) -> Bool { a.kind == b.kind && a.key == b.key }

    /// 최근에 일한 분야 순 폴더, 분야가 없는 업무는 맨 아래 '분야 없음'
    static func folders(_ choices: ChatFocusChoices) -> [Folder] {
        var result = choices.themes.map { theme in
            Folder(key: theme.focus.key, title: theme.focus.title, tasks: choices.tasks.filter { $0.themeKey == theme.focus.key }.map(\.focus))
        }
        let loose = choices.tasks.filter { $0.themeKey == nil }.map(\.focus)
        if !loose.isEmpty { result.append(Folder(key: nil, title: "분야 없음", tasks: loose)) }
        return result
    }

    /// 검색: 분야 이름이 맞으면 그 분야 업무 전체, 아니면 이름이 맞는 업무만
    static func filtered(_ folders: [Folder], query: String) -> [Folder] {
        guard !query.isEmpty else { return folders }
        return folders.compactMap { folder in
            if folder.title.localizedCaseInsensitiveContains(query) { return folder }
            let tasks = folder.tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
            return tasks.isEmpty ? nil : Folder(key: folder.key, title: folder.title, tasks: tasks)
        }
    }

    static func mark(_ folder: Folder, in selection: [ChatFocus]) -> Mark {
        if let theme = folder.theme, selection.contains(where: { same($0, theme) }) { return .all }
        let picked = folder.tasks.filter { task in selection.contains { same($0, task) } }.count
        return picked == 0 ? .none : picked == folder.tasks.count ? .all : .some
    }

    static func isOn(_ task: ChatFocus, in folder: Folder, selection: [ChatFocus]) -> Bool {
        selection.contains { same($0, task) } || folder.theme.map { theme in selection.contains { same($0, theme) } } == true
    }

    /// 폴더 체크: 다 골라져 있으면 빼고, 아니면 분야 전체로 (분야 없음은 안의 업무를 하나씩)
    static func toggle(_ folder: Folder, in selection: [ChatFocus]) -> [ChatFocus] {
        let rest = selection.filter { item in
            !folder.tasks.contains { same($0, item) } && !(folder.theme.map { same($0, item) } ?? false)
        }
        if mark(folder, in: selection) == .all { return rest }
        return rest + (folder.theme.map { [$0] } ?? folder.tasks)
    }

    /// 업무 체크: 분야 전체가 골라져 있으면 이 업무만 뺀 나머지 업무들로 풀고, 아니면 이 업무를 넣고 뺀다
    static func toggle(_ task: ChatFocus, in folder: Folder, selection: [ChatFocus]) -> [ChatFocus] {
        if let theme = folder.theme, selection.contains(where: { same($0, theme) }) {
            return selection.filter { !same($0, theme) } + folder.tasks.filter { !same($0, task) }
        }
        if selection.contains(where: { same($0, task) }) { return selection.filter { !same($0, task) } }
        return selection + [task]
    }
}
