import Foundation
import Testing
@testable import GrillBreakCore

@Suite("StaffMelodyResolver")
struct StaffMelodyResolverTests {

    @Test
    func emptyWhenNoCurrentMelody() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("staff-melody-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = MelodyLibrary(rootDirectory: root)
        let content = StaffMelodyResolver().resolve(library: library)

        #expect(content == .empty)
    }

    @Test
    func scoreWhenCurrentMelodyExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("staff-melody-ok-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = MelodyLibrary(rootDirectory: root)
        let outcome = library.importMusicXML(MusicXMLFixtures.simpleFourMeasures)
        guard case .imported = outcome else {
            Issue.record("expected import to succeed, got \(outcome)")
            return
        }

        let content = StaffMelodyResolver().resolve(library: library)

        guard case .score(let musicXML) = content else {
            Issue.record("expected score content, got \(content)")
            return
        }
        #expect(musicXML.contains("<score-partwise"))
        #expect(musicXML == MusicXMLFixtures.simpleFourMeasures)
    }

    @Test
    func failedWhenScoreFileMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("staff-melody-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = MelodyLibrary(rootDirectory: root)
        let outcome = library.importMusicXML(MusicXMLFixtures.simpleFourMeasures)
        guard case .imported(let melody, _) = outcome else {
            Issue.record("expected import to succeed, got \(outcome)")
            return
        }

        let scoreURL = root.appendingPathComponent("scores/\(melody.id.uuidString).musicxml")
        try FileManager.default.removeItem(at: scoreURL)

        let content = StaffMelodyResolver().resolve(library: library)

        guard case .failed(let message) = content else {
            Issue.record("expected failed content, got \(content)")
            return
        }
        #expect(!message.isEmpty)
    }
}
