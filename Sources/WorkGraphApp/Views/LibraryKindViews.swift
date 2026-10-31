import SwiftUI
import WorkGraphCore

/// 보관함 종류별 화면과 홈 (Figma LB-25, LB-04, LB-06, LB-16, LB-17, LB-18). 수치는 모두 앱 데이터로 계산한다.
enum LibraryLook {
    static let recording = Color(hex: 0x6E5A4D)
    static let upload = Color(hex: 0xA38E7F)
    static let generated = Color(hex: 0xC4B5A8)
    static let note = Color(hex: 0xE1D8D0)
    static let noContent = Color(hex: 0xB8ABA0)
    static let failed = Color(hex: 0xB5503F)
    /// 막대와 범례에 나오는 순서
    static let order = ["recording", "upload", "generated", "note"]

    static func color(_ kind: String) -> Color {
        switch kind {
        case "recording": recording
        case "upload": upload
        case "generated": generated
        default: note
        }
    }
    static func name(_ kind: String) -> String {
        switch kind {
        case "recording": "녹음"
        case "upload": "업로드"
        case "generated": "생성한 결과물"
        default: "저장한 답변"
        }
    }
    static func when(_ time: Double) -> String { RecordingText.date(time, "M월 d일 HH:mm", timeZone: .current) }
    static func day(_ time: Double) -> String { RecordingText.date(time, "M월 d일", timeZone: .current) }
    static func ext(_ item: ChatLibraryItem) -> String { URL(fileURLWithPath: item.filename).pathExtension.lowercased() }
    /// 형식 열에 쓰는 이름
    static func format(_ ext: String) -> String {
        switch ext {
        case "pdf": "PDF"
        case "doc", "docx": "Word 문서"
        case "html", "htm": "HTML 문서"
        case "md", "markdown": "Markdown 문서"
        case "txt": "텍스트"
        case "ppt", "pptx": "PowerPoint"
        case "xls", "xlsx": "Excel"
        case "hwp", "hwpx": "한글 문서"
        case "png", "jpg", "jpeg", "gif", "heic": "이미지"
        case "": "파일"
        default: ext.uppercased()
        }
    }
    static func count(_ n: Int) -> String { "\(n.formatted())" }
}

extension LibraryEntry {
    var kind: String {
        switch self {
        case .item(let item): item.kind
        case .recording: "recording"
        }
    }
    var title: String {
        switch self {
        case .item(let item): item.title
        case .recording(let recording): recording.displayTitle
        }
    }
}

extension Recording {
    /// 목록과 막대에 쓰는 받아쓰기 상태
    var libraryStatus: (text: String, color: Color) {
        switch status {
        case .recording: ("녹음 중", Brand.gray)
        case .transcribing: ("받아쓰는 중", Brand.gray)
        case .failed: ("실패", LibraryLook.failed)
        case .ready: hasTranscript ? ("완료", Brand.tabText) : ("내용 없음", Brand.gray)
        }
    }
}

struct LibraryActions {
    var open: (LibraryEntry) -> Void
    var export: (ChatLibraryItem) -> Void
    var delete: (ChatLibraryItem) -> Void
    var projectCount: (ChatLibraryItem) -> Int
}

/// 파일에서 읽은 첫 줄, 글자 수, 표 여부 (저장한 답변과 결과물 카드용)
struct LibraryTextInfo {
    var first = ""
    var count = 0
    var hasTable = false

    static func read(_ url: URL) -> LibraryTextInfo {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .init() }
        let line = text.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#>*- \t")) }.first { !$0.isEmpty } ?? ""
        return .init(first: line, count: text.count, hasTable: text.localizedCaseInsensitiveContains("<table") || text.contains("|---"))
    }
}

/// 머리: 종류 이름과 개수(16), 한 줄 요약(11)
private struct KindHeader: View {
    let title: String
    let summary: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Brand.suit(16, .medium)).foregroundStyle(Brand.ink)
            Text(summary).font(Brand.suit(11)).foregroundStyle(Brand.gray)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 목록 줄: 누르면 열고, 보관한 자료는 오른쪽 클릭 메뉴로 내보내거나 지운다
private struct KindRow<Content: View>: View {
    let entry: LibraryEntry
    let actions: LibraryActions
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        Button { actions.open(entry) } label: {
            content.padding(.vertical, spacing).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            .contextMenu {
                if case .item(let item) = entry {
                    Button("파일 내보내기") { actions.export(item) }
                    Button("보관함에서 삭제", role: .destructive) { actions.delete(item) }
                }
            }
    }
}

/// 열 제목 줄 (10, 회색) 과 아래 선
private struct ColumnHeads: View {
    let heads: [(String, CGFloat)]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 28, height: 1)
                ForEach(heads.indices, id: \.self) { i in
                    Text(heads[i].0).font(Brand.suit(10)).foregroundStyle(Brand.gray)
                        .frame(width: heads[i].1 > 0 ? heads[i].1 : nil, alignment: .leading)
                        .frame(maxWidth: heads[i].1 > 0 ? nil : .infinity, alignment: .leading)
                }
            }.padding(.top, 30).padding(.bottom, 8)
            Rectangle().fill(Brand.line).frame(height: 1)
        }
    }
}

private func cell(_ text: String, _ width: CGFloat, gray: Bool = false) -> some View {
    Text(text).font(Brand.suit(11)).foregroundStyle(gray ? Brand.gray : Brand.tabText).lineLimit(1)
        .frame(width: width > 0 ? width : nil, alignment: .leading).frame(maxWidth: width > 0 ? nil : .infinity, alignment: .leading)
}

private func lead(_ symbol: String) -> some View {
    Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Brand.tabText).frame(width: 28, alignment: .leading)
}

private func title(_ text: String, _ width: CGFloat) -> some View {
    Text(text).font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText).lineLimit(1)
        .frame(width: width, alignment: .leading)
}

/// LB-04: 전체, 종류 색 표시와 추가한 때 열, 최근순
struct LibraryAllList: View {
    let entries: [LibraryEntry]
    let actions: LibraryActions
    var body: some View {
        let counts = LibraryLook.order.map { kind in (kind, entries.filter { $0.kind == kind }.count) }
        VStack(spacing: 0) {
            KindHeader(title: "전체 \(entries.count)개",
                       summary: counts.filter { $0.1 > 0 }.map { "\(LibraryLook.name($0.0)) \($0.1)" }.joined(separator: "     ") + "     최근 추가한 순서예요")
            ColumnHeads(heads: [("제목", 442), ("종류", 150), ("추가한 때", 0)])
            ForEach(entries) { entry in
                KindRow(entry: entry, actions: actions) {
                    HStack(spacing: 0) {
                        lead(entry.kind == "recording" ? "waveform" : "doc.text")
                        title(entry.title, 442)
                        HStack(spacing: 6) {
                            Circle().fill(LibraryLook.color(entry.kind)).frame(width: 6, height: 6)
                            Text(LibraryLook.name(entry.kind)).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
                        }.frame(width: 150, alignment: .leading)
                        cell(LibraryLook.when(entry.date), 0, gray: true)
                    }
                }
            }
        }
    }
}

/// LB-06: 제목, 녹음한 때, 길이와 비례 막대, 받아쓰기 상태 (실패는 붉게)
struct LibraryRecordingList: View {
    let recordings: [Recording]
    let actions: LibraryActions
    var body: some View {
        let longest = max(recordings.map(\.duration).max() ?? 0, 1)
        let total = recordings.reduce(0) { $0 + $1.duration }
        let ready = recordings.filter { $0.status == .ready && $0.hasTranscript }.count
        let empty = recordings.filter { $0.status == .ready && !$0.hasTranscript }.count
        let failed = recordings.filter { $0.status == .failed }.count
        VStack(spacing: 0) {
            KindHeader(title: "녹음 \(recordings.count)개",
                       summary: "총 길이 \(RecordingText.duration(total))     받아쓰기 완료 \(ready)     내용 없음 \(empty)     실패 \(failed)")
            ColumnHeads(heads: [("제목", 372), ("녹음한 때", 120), ("길이", 170), ("받아쓰기", 0)])
            ForEach(recordings) { recording in
                let status = recording.libraryStatus
                KindRow(entry: .recording(recording), actions: actions) {
                    HStack(spacing: 0) {
                        lead("waveform")
                        title(recording.displayTitle, 372)
                        cell(LibraryLook.when(recording.startedAt), 120, gray: true)
                        HStack(spacing: 8) {
                            Text(RecordingText.duration(recording.duration)).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
                                .frame(width: 64, alignment: .leading)
                            if recording.duration > 0 {
                                RoundedRectangle(cornerRadius: 2).fill(LibraryLook.recording)
                                    .frame(width: max(4, 80 * recording.duration / longest), height: 4)
                            }
                        }.frame(width: 170, alignment: .leading)
                        Text(status.text).font(Brand.suit(11, recording.status == .failed ? .medium : .regular)).foregroundStyle(status.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// LB-16: 이름, 형식, 올린 때, 연결한 프로젝트
struct LibraryUploadList: View {
    let items: [ChatLibraryItem]
    let actions: LibraryActions
    var body: some View {
        VStack(spacing: 0) {
            KindHeader(title: "업로드 \(items.count)개", summary: "내가 올린 파일의 복사본이에요")
            ColumnHeads(heads: [("이름", 372), ("형식", 100), ("올린 때", 150), ("연결한 프로젝트", 0)])
            ForEach(items) { item in
                let projects = actions.projectCount(item)
                KindRow(entry: .item(item), actions: actions, spacing: 16) {
                    HStack(spacing: 0) {
                        lead("doc.text")
                        title(item.title, 372)
                        cell(LibraryLook.format(LibraryLook.ext(item)), 100)
                        cell(LibraryLook.when(item.createdAt), 150, gray: true)
                        cell(projects > 0 ? "프로젝트 \(projects)개" : "연결 없음", 0)
                    }
                }
            }
            Text("올린 파일은 연결한 대화와 프로젝트에서 답변 근거로 써요.").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 18)
        }
    }
}

/// LB-17: 문서 모양 미리보기 그림 2열 카드, 형식과 날짜
struct LibraryGeneratedGrid: View {
    let items: [ChatLibraryItem]
    let actions: LibraryActions
    let infos: [String: LibraryTextInfo]

    private var formatText: String {
        var formats: [String: Int] = [:]
        for item in items { formats[LibraryLook.ext(item).uppercased(), default: 0] += 1 }
        return formats.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key.isEmpty ? "파일" : $0.key) \($0.value)개" }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KindHeader(title: "생성한 결과물 \(items.count)개", summary: "채팅에서 만든 결과물이에요     형식은 \(formatText)")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())], alignment: .leading, spacing: 28) {
                ForEach(items) { item in
                    Button { actions.open(.item(item)) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            DocumentPreview(hasTable: infos[item.id]?.hasTable ?? false)
                            Text(item.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText).lineLimit(1).padding(.top, 14)
                            Text("\(LibraryLook.format(LibraryLook.ext(item)))     \(LibraryLook.when(item.createdAt))")
                                .font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 6)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .contextMenu {
                            Button("파일 내보내기") { actions.export(item) }
                            Button("보관함에서 삭제", role: .destructive) { actions.delete(item) }
                        }
                }
            }.padding(.top, 26)
        }
    }
}

/// 흰 쪽 하나가 있는 문서 모양 그림 (바탕 385x200, 쪽 160x164)
private struct DocumentPreview: View {
    let hasTable: Bool
    var body: some View {
        ZStack {
            Rectangle().fill(Brand.paper)
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(LibraryLook.recording).frame(width: 70, height: 8)
                VStack(alignment: .leading, spacing: 6) {
                    line(132); line(120)
                    if hasTable {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xEFE9E4)).frame(width: 64, height: 40)
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xEFE9E4)).frame(width: 64, height: 40)
                        }.padding(.vertical, 6)
                        line(132); line(110)
                    } else {
                        line(132).padding(.top, 8); line(100); line(126); line(90)
                    }
                }.padding(.top, 14)
                Spacer(minLength: 0)
            }.padding(14).frame(width: 160, height: 164, alignment: .topLeading).background(.white)
        }.frame(maxWidth: .infinity).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private func line(_ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Brand.line).frame(width: width, height: 4)
    }
}

/// LB-18: 제목, 첫 줄, 날짜, 글자 수, 연결 프로젝트
struct LibraryNoteList: View {
    let items: [ChatLibraryItem]
    let actions: LibraryActions
    let infos: [String: LibraryTextInfo]
    var body: some View {
        VStack(spacing: 0) {
            KindHeader(title: "저장한 답변 \(items.count)개", summary: "채팅 답변을 저장해 둔 글이에요").padding(.bottom, 18)
            ForEach(items) { item in
                let projects = actions.projectCount(item)
                let info = infos[item.id]
                KindRow(entry: .item(item), actions: actions, spacing: 18) {
                    VStack(spacing: 8) {
                        HStack {
                            Text(item.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText).lineLimit(1)
                            Spacer(minLength: 16)
                            Text(LibraryLook.when(item.createdAt)).font(Brand.suit(11)).foregroundStyle(Brand.tabText)
                        }
                        HStack {
                            Text(info?.first ?? "").font(Brand.suit(11)).foregroundStyle(Brand.gray).lineLimit(1)
                            Spacer(minLength: 16)
                            Text("\(info.map { "\($0.count.formatted())자" } ?? "")     \(projects > 0 ? "프로젝트 \(projects)개" : "연결 없음")")
                                .font(Brand.suit(10)).foregroundStyle(Brand.gray).lineLimit(1).fixedSize()
                        }
                    }
                }
            }
        }
    }
}

/// LB-25: 보관함 홈. 전체 개수, 종류 비율, 최근 7일 추가, 받아쓰기 상태, 최근 추가 5건
struct LibraryHome: View {
    let items: [ChatLibraryItem]
    let recordings: [Recording]
    let actions: LibraryActions

    private var entries: [LibraryEntry] {
        (items.map { LibraryEntry.item($0) } + recordings.map { LibraryEntry.recording($0) }).sorted { $0.date > $1.date }
    }

    var body: some View {
        let all = entries
        let counts = Dictionary(grouping: all, by: \.kind).mapValues(\.count)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 36) {
                Donut(parts: LibraryLook.order.map { (LibraryLook.color($0), Double(counts[$0] ?? 0)) }, size: 132, line: 16) {
                    VStack(spacing: 2) {
                        Text("보관함 전체").font(Brand.suit(10)).foregroundStyle(Brand.gray)
                        Text("\(all.count)개").font(Brand.suit(22, .medium)).foregroundStyle(Brand.ink)
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    if let last = all.first {
                        Text("마지막으로 쌓인 때  \(LibraryLook.when(last.date))").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                    }
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(LibraryLook.order, id: \.self) { kind in legend(kind, counts[kind] ?? 0).frame(width: 150, alignment: .leading) }
                    }
                }
            }
            Rectangle().fill(Brand.line).frame(height: 1).padding(.top, 24)
            HStack(alignment: .top, spacing: 50) {
                VStack(alignment: .leading, spacing: 0) {
                    chart(all)
                    if !recordings.isEmpty { status.padding(.top, 36) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                recent(all).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.top, 24)
        }
    }

    private func legend(_ kind: String, _ count: Int) -> some View {
        let mine = entries.filter { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(LibraryLook.color(kind)).frame(width: 8, height: 8)
                Text(LibraryLook.name(kind)).font(Brand.suit(11)).foregroundStyle(Brand.gray)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(count)").font(Brand.suit(22, .medium)).foregroundStyle(Brand.ink)
                Text("개").font(Brand.suit(11)).foregroundStyle(Brand.gray)
            }.padding(.top, 8)
            Text(sub(kind, mine)).font(Brand.suit(10)).foregroundStyle(Brand.gray).padding(.top, 8)
        }
    }

    private func sub(_ kind: String, _ mine: [LibraryEntry]) -> String {
        guard let last = mine.first else { return "아직 없어요" }
        switch kind {
        case "recording": return "총 길이 \(RecordingText.duration(recordings.reduce(0) { $0 + $1.duration }))"
        case "generated":
            var formats: [String: Int] = [:]
            for item in items where item.kind == kind { formats[LibraryLook.ext(item).uppercased(), default: 0] += 1 }
            return "형식 " + formats.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { "\($0.key) \($0.value)개" }.joined(separator: ", ")
        default: return "마지막 \(LibraryLook.day(last.date))"
        }
    }

    /// 오늘까지 7일, 날마다 종류별로 쌓은 막대
    private func chart(_ all: [LibraryEntry]) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).map { calendar.date(byAdding: .day, value: $0 - 6, to: today)! }
        let perDay: [[String: Int]] = days.map { day in
            var counts: [String: Int] = [:]
            for entry in all where calendar.isDate(Date(timeIntervalSince1970: entry.date), inSameDayAs: day) { counts[entry.kind, default: 0] += 1 }
            return counts
        }
        let peak = max(perDay.map { $0.values.reduce(0, +) }.max() ?? 0, 1)
        let unit = min(17.8, 90 / CGFloat(peak))
        let label = DateFormatter()
        label.dateFormat = "M/d"
        return VStack(alignment: .leading, spacing: 0) {
            Text("최근 7일 추가").font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(days.indices, id: \.self) { i in
                    let total = perDay[i].values.reduce(0, +)
                    VStack(spacing: 4) {
                        if total > 0 { Text("\(total)").font(Brand.suit(10)).foregroundStyle(Brand.gray) }
                        VStack(spacing: 0) {
                            ForEach(LibraryLook.order.reversed(), id: \.self) { kind in
                                if let n = perDay[i][kind], n > 0 {
                                    RoundedRectangle(cornerRadius: 2).fill(LibraryLook.color(kind)).frame(width: 28, height: unit * CGFloat(n))
                                }
                            }
                        }
                    }.frame(width: 53)
                }
            }.frame(height: 116, alignment: .bottom).padding(.top, 14)
            Rectangle().fill(Brand.line).frame(height: 1).frame(width: 371)
            HStack(spacing: 0) {
                ForEach(days.indices, id: \.self) { i in
                    Text(label.string(from: days[i])).font(Brand.suit(10)).foregroundStyle(Brand.gray).frame(width: 53)
                }
            }.padding(.top, 8)
        }
    }

    /// 녹음 받아쓰기 상태 막대와 범례
    private var status: some View {
        let ready = recordings.filter { $0.status == .ready && $0.hasTranscript }.count
        let empty = recordings.filter { $0.status == .ready && !$0.hasTranscript }.count
        let failed = recordings.filter { $0.status == .failed }.count
        let parts: [(String, Int, Color)] = [("완료", ready, LibraryLook.recording), ("내용 없음", empty, LibraryLook.noContent), ("실패", failed, LibraryLook.failed)]
        return VStack(alignment: .leading, spacing: 0) {
            Text("녹음 받아쓰기 상태").font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText)
            HStack(spacing: 24) {
                Donut(parts: parts.map { ($0.2, Double($0.1)) }, size: 84, line: 10) {
                    Text("\(recordings.count)").font(Brand.suit(16, .medium)).foregroundStyle(Brand.ink)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(parts.indices, id: \.self) { i in
                        HStack(spacing: 6) {
                            Circle().fill(parts[i].2).frame(width: 8, height: 8)
                            Text("\(parts[i].0) \(parts[i].1)").font(Brand.suit(11)).foregroundStyle(Brand.gray)
                        }
                    }
                }
            }.padding(.top, 14)
        }
    }

    private func recent(_ all: [LibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("최근 추가").font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText).padding(.bottom, 10)
            ForEach(Array(all.prefix(5))) { entry in
                KindRow(entry: entry, actions: actions, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title).font(Brand.suit(12, .medium)).foregroundStyle(Brand.tabText).lineLimit(1)
                        Text(subtitle(entry)).font(Brand.suit(10)).foregroundStyle(Brand.gray).lineLimit(1)
                    }
                }
            }
        }
    }

    private func subtitle(_ entry: LibraryEntry) -> String {
        var text = "\(LibraryLook.name(entry.kind))  \(LibraryLook.when(entry.date))"
        if case .recording(let recording) = entry { text += "  \(RecordingText.duration(recording.duration))" }
        return text
    }
}


/// 도넛 차트: 조각 사이에 작은 틈을 두고, 가운데에 내용을 얹는다. 값이 모두 0이면 옅은 고리만 그린다.
struct Donut<Center: View>: View {
    let parts: [(Color, Double)]
    let size: CGFloat
    let line: CGFloat
    @ViewBuilder var center: Center

    var body: some View {
        let total = parts.reduce(0) { $0 + $1.1 }
        let used = parts.filter { $0.1 > 0 }
        let gap = used.count > 1 ? 0.012 : 0
        var start = 0.0
        let arcs: [(Color, Double, Double)] = used.map { part in
            let from = start; start += part.1 / max(total, 1)
            return (part.0, from + gap / 2, start - gap / 2)
        }
        return ZStack {
            Circle().stroke(Brand.line, lineWidth: line)
            ForEach(arcs.indices, id: \.self) { i in
                Circle().trim(from: arcs[i].1, to: arcs[i].2).stroke(arcs[i].0, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            center
        }.padding(line / 2).frame(width: size, height: size)
    }
}
