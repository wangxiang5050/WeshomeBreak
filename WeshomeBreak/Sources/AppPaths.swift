import Foundation

enum AppPaths {
    /// This Mac's private Melody Library, used only while iCloud Drive is unreachable.
    static var privateMelodyLibraryRoot: URL {
        libraryDirectory("WeshomeBreak/MelodyLibrary")
    }

    /// Device id and manual Melody Selection. Never placed in iCloud Drive.
    static var melodyLibraryLocalStateRoot: URL {
        libraryDirectory("WeshomeBreak/MelodyLibraryLocal")
    }

    /// iCloud Drive folder shown in Finder as "Weshome Break".
    static var sharedMelodyLibraryDirectory: URL {
        iCloudDriveContainer.appendingPathComponent("Weshome Break", isDirectory: true)
    }

    static var iCloudDriveContainer: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    static func iCloudDriveIsReachable() -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: iCloudDriveContainer.path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    private static func libraryDirectory(_ relativePath: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = support.appendingPathComponent(relativePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
