import AppKit
import Testing
@testable import VoicedKit

/// Uses private pasteboards, so the tests never touch the real clipboard or post keystrokes.
@MainActor
@Suite struct PasteboardTextInserterTests {
    private struct PasteFailed: Error {}

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard.withUniqueName()
    }

    @Test func pastesTheTextThenRestoresThePreviousContents() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("what the user had copied", forType: .string)

        var seenAtPaste: String?
        let inserter = PasteboardTextInserter(pasteboard: pasteboard, restoreDelay: .milliseconds(30)) {
            seenAtPaste = pasteboard.string(forType: .string)
        }

        try await inserter.insert("Dictated text.")

        #expect(seenAtPaste == "Dictated text.")
        try await waitUntil { pasteboard.string(forType: .string) == "what the user had copied" }
    }

    @Test func marksTheDictatedTextAsTransient() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        var typesAtPaste: [NSPasteboard.PasteboardType] = []
        let inserter = PasteboardTextInserter(pasteboard: pasteboard, restoreDelay: .seconds(60)) {
            typesAtPaste = pasteboard.types ?? []
        }

        try await inserter.insert("Dictated text.")

        #expect(typesAtPaste.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")))
        #expect(typesAtPaste.contains(.string))
    }

    @Test func restoresEveryTypeOfThePreviousContents() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let html = NSPasteboard.PasteboardType.html
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setString("<b>rich</b>", forType: html)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let inserter = PasteboardTextInserter(pasteboard: pasteboard, restoreDelay: .milliseconds(30)) {}
        try await inserter.insert("Dictated text.")

        try await waitUntil { pasteboard.string(forType: html) == "<b>rich</b>" }
        #expect(pasteboard.string(forType: .string) == "plain")
    }

    @Test func anEmptyPasteboardIsEmptyAgainAfterwards() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()

        let inserter = PasteboardTextInserter(pasteboard: pasteboard, restoreDelay: .milliseconds(30)) {}
        try await inserter.insert("Dictated text.")

        try await waitUntil { pasteboard.string(forType: .string) == nil }
    }

    @Test func leavesANewerCopyAlone() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)

        let inserter = PasteboardTextInserter(pasteboard: pasteboard, restoreDelay: .milliseconds(30)) {}
        try await inserter.insert("Dictated text.")
        pasteboard.clearContents()
        pasteboard.setString("copied right after dictating", forType: .string)

        try await Task.sleep(for: .milliseconds(120))
        #expect(pasteboard.string(forType: .string) == "copied right after dictating")
    }

    @Test func keepsTheTextOnThePasteboardWhenPastingFails() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)

        let inserter = PasteboardTextInserter(pasteboard: pasteboard, restoreDelay: .milliseconds(30)) {
            throw PasteFailed()
        }

        await #expect(throws: PasteFailed.self) {
            try await inserter.insert("Dictated text.")
        }
        try await Task.sleep(for: .milliseconds(120))
        #expect(pasteboard.string(forType: .string) == "Dictated text.")
    }

    @Test func backToBackInsertionsRestoreTheOriginalContents() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        var pasted: [String] = []
        let inserter = PasteboardTextInserter(pasteboard: pasteboard, restoreDelay: .milliseconds(60)) {
            pasted.append(pasteboard.string(forType: .string) ?? "")
        }

        try await inserter.insert("First.")
        try await inserter.insert("Second.")

        #expect(pasted == ["First.", "Second."])
        try await waitUntil { pasteboard.string(forType: .string) == "original" }
    }
}
