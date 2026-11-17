import XCTest
@testable import Whisper

final class WhisperKnotClarificationTests: XCTestCase {
    @MainActor func testTaskPlanIsOnePerOwnedTurnAndStopClearsCreativeState() {
        let progress = WhisperKnotTurnProgress()
        progress.plan("Not admitted", creative: true)
        XCTAssertNil(progress.taskPlan)
        progress.begin(sourceID: UUID())
        progress.plan("I’ll create the requested result.", creative: true)
        progress.plan("A repeated update", creative: true)
        XCTAssertEqual(progress.taskPlan, "I’ll create the requested result.")
        XCTAssertFalse(progress.creativeWork)
        progress.working(creative: true)
        XCTAssertTrue(progress.creativeWork)
        progress.working(creative: false)
        XCTAssertFalse(progress.creativeWork)
        progress.end()
        XCTAssertNil(progress.taskPlan)
        XCTAssertNil(progress.label)
        progress.working(creative: true)
        XCTAssertFalse(progress.creativeWork)
        progress.begin(sourceID: UUID())
        XCTAssertNil(progress.taskPlan)
    }
    func testDecodingAndDisplayBinding() throws {
        let data = Data("""
        {"id":"00000000-0000-4000-8000-000000000001","sourceMessageID":"00000000-0000-4000-8000-000000000002","conversationID":"00000000-0000-4000-8000-000000000003","bot":"main","question":"Who is this for?","options":["Beginners","Experienced readers"]}
        """.utf8)
        let card = try JSONDecoder().decode(WhisperKnotClarification.self, from: data)
        XCTAssertTrue(card.valid)
        XCTAssertTrue(card.belongs(to: card.conversationID, bot: "main", text: card.question))
        XCTAssertFalse(card.belongs(to: UUID(), bot: "main", text: card.question))
        XCTAssertFalse(card.belongs(to: card.conversationID, bot: "other", text: card.question))
        XCTAssertFalse(card.belongs(to: card.conversationID, bot: "main", text: "An edited question"))
        XCTAssertEqual(try JSONDecoder().decode(WhisperKnotClarification.self, from: JSONEncoder().encode(card)), card)
    }
    func testRejectsBadChoicesAndOversizedOrEmptyAnswers() {
        let card = WhisperKnotClarification(id: UUID(), sourceMessageID: UUID(), conversationID: UUID(), bot: "main", question: "Who is this for?", options: ["Beginners", "Experienced readers"])
        XCTAssertEqual(card.composedAnswer(source: "Create a guide", answer: "Beginners"), "Original request: Create a guide\nClarifying question: Who is this for?\nMy answer: Beginners")
        XCTAssertNil(card.composedAnswer(source: String(repeating: "x", count: 16000), answer: "Beginners"))
        XCTAssertNil(card.composedAnswer(source: "Create a guide", answer: " "))
        XCTAssertNil(card.composedAnswer(source: "Create a guide", answer: String(repeating: "a", count: 501)))
        let duplicate = WhisperKnotClarification(id: UUID(), sourceMessageID: UUID(), conversationID: UUID(), bot: "main", question: "Who?", options: ["Same", "same"])
        XCTAssertFalse(duplicate.valid)
        XCTAssertNil(duplicate.composedAnswer(source: "Create a guide", answer: "Same"))
    }
    func testNaturalProseAndSingleNextReplyRemainSourceBoundDisplayData() throws {
        for options in [[], ["Add a packing list"]] as [[String]] {
            let card = WhisperKnotClarification(id: UUID(), sourceMessageID: UUID(), conversationID: UUID(), bot: "main", question: "The guide covers the route.\n\nWould you like a packing list?", options: options)
            XCTAssertTrue(card.valid)
            XCTAssertEqual(try JSONDecoder().decode(WhisperKnotClarification.self, from: JSONEncoder().encode(card)), card)
            XCTAssertFalse(card.belongs(to: UUID(), bot: "main", text: card.question))
            XCTAssertEqual(card.composedAnswer(source: "Create a guide", answer: "Add a packing list"), "Original request: Create a guide\nClarifying question: The guide covers the route.\n\nWould you like a packing list?\nMy answer: Add a packing list")
        }
    }
    func testHistoryPreservesSameTextMetadataButNotAcrossEditsOrIdentities() throws {
        let card = WhisperKnotClarification(id: UUID(), sourceMessageID: UUID(), conversationID: UUID(), bot: "main", question: "Who is this for?", options: ["Beginners", "Experienced readers"])
        let id = UUID()
        let local = WhisperEmberConversation.Message(role: "ember", text: card.question, clarification: card, id: id)
        let server = WhisperEmberConversation.Message(role: "ember", text: card.question, id: id)
        XCTAssertEqual(server.reconcilingReaction(local).clarification, card)
        let edited = WhisperEmberConversation.Message(role: "ember", text: "A different question", id: id)
        XCTAssertNil(edited.reconcilingReaction(local).clarification)
        let other = WhisperEmberConversation.Message(role: "ember", text: card.question, id: UUID())
        XCTAssertNil(other.reconcilingReaction(local).clarification)
        let answer = WhisperEmberConversation.Message(role: "user", text: "Original request: Create a guide\nClarifying question: Who is this for?\nMy answer: Beginners", clarificationAnswer: "Beginners", id: UUID())
        let decoded = try JSONDecoder().decode(WhisperEmberConversation.Message.self, from: JSONEncoder().encode(answer))
        XCTAssertEqual(decoded.clarificationAnswer, "Beginners")
        var omitted = answer; omitted.clarificationAnswer = nil
        XCTAssertEqual(omitted.reconcilingReaction(answer).clarificationAnswer, "Beginners")
    }
}
