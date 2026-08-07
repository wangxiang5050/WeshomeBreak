import Foundation

enum AppPaths {
    /// On-disk root for the Melody Library (shared by Staff Melody Scene and,
    /// later, the settings import UI in ticket 07).
    static var melodyLibraryRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = support.appendingPathComponent("WeshomeBreak/MelodyLibrary", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
