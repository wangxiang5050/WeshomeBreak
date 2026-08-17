import Foundation
import GrillBreakCore

/// UI-facing wrapper around `MelodyLibrary`: republishes the melody list and
/// current selection so Settings can refresh after import / select / delete / rename,
/// while the same underlying library instance feeds Staff Melody Scene.
@MainActor
final class MelodyLibraryStore: ObservableObject {
    private let library: MelodyLibrary

    @Published private(set) var melodies: [UserMelody] = []
    @Published private(set) var selectedMelodyID: UUID?
    @Published private(set) var feedback: Feedback = .none

    enum Feedback: Equatable {
        case none
        case info(String)
        case error(String)

        var message: String? {
            switch self {
            case .none: return nil
            case .info(let text), .error(let text): return text
            }
        }

        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    init(library: MelodyLibrary) {
        self.library = library
        refresh()
    }

    func refresh() {
        melodies = library.melodies()
        selectedMelodyID = library.selectedMelodyID
    }

    func importFile(at url: URL) {
        let outcome = library.importFile(at: url)
        refresh()
        switch outcome {
        case .imported(let melody, let warnings):
            if warnings.isEmpty {
                feedback = .info("已导入「\(melody.title)」")
            } else {
                feedback = .info("已导入「\(melody.title)」。" + warnings.joined(separator: " "))
            }
        case .rejected(let reason):
            feedback = .error("导入失败：\(reason)")
        }
    }

    func select(id: UUID) {
        applyMutation {
            try library.select(id: id)
            feedback = .none
        }
    }

    func delete(id: UUID) {
        applyMutation {
            try library.delete(id: id)
            feedback = .none
        }
    }

    func rename(id: UUID, to title: String) {
        applyMutation {
            try library.rename(id: id, to: title)
            feedback = .none
        }
    }

    func reportFailure(_ message: String) {
        feedback = .error(message)
    }

    private func applyMutation(_ body: () throws -> Void) {
        do {
            try body()
            refresh()
        } catch {
            feedback = .error(error.localizedDescription)
        }
    }
}
