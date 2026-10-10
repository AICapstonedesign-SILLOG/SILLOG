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
