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
