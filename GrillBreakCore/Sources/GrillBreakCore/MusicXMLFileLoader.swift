import Foundation

/// Loads MusicXML text from `.musicxml` / `.xml` files or compressed `.mxl` archives.
public struct MusicXMLFileLoader: Sendable {
    public init() {}

    public func loadString(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "musicxml", "xml":
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw MelodyLibraryError.ioFailure(Self.unreadableFileMessage)
            }
        case "mxl":
            return try loadFromMXL(url)
        default:
            throw MelodyLibraryError.unsupportedFileExtension(ext.isEmpty ? "(none)" : ext)
        }
    }

    /// User-facing copy: reason + next step (import IO failures only).
    static let unreadableFileMessage = """
        无法读取该文件。
        请确认文件未损坏，或用 MuseScore 导出 .musicxml 后再试。
        """

    static let mxlUnzipFailedMessage = """
        无法解压该 MXL 文件。
        建议用 MuseScore 打开后导出为 .musicxml 再导入。
        """

    static let mxlMissingScoreMessage = """
        该 MXL 压缩包内没有可用的 MusicXML 谱面。
        建议用 MuseScore 打开后重新导出为 .musicxml 或 .mxl。
        """

    private func loadFromMXL(_ url: URL) throws -> String {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-extract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", tempRoot.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw MelodyLibraryError.ioFailure(Self.mxlUnzipFailedMessage)
        }
        guard process.terminationStatus == 0 else {
            throw MelodyLibraryError.ioFailure(Self.mxlUnzipFailedMessage)
        }

        let scoreRelativePath = try resolveRootfilePath(in: tempRoot)
        let scoreURL = tempRoot.appendingPathComponent(scoreRelativePath)
        do {
            return try String(contentsOf: scoreURL, encoding: .utf8)
        } catch {
            throw MelodyLibraryError.ioFailure(Self.unreadableFileMessage)
        }
    }

    private func resolveRootfilePath(in extractedRoot: URL) throws -> String {
        let containerURL = extractedRoot
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")
        if FileManager.default.fileExists(atPath: containerURL.path),
           let xml = try? String(contentsOf: containerURL, encoding: .utf8),
           let document = try? XMLDocument(xmlString: xml, options: []),
           let root = document.rootElement(),
           let fullPath = (try? root.nodes(forXPath: ".//rootfile") as? [XMLElement])?
            .first?
            .attribute(forName: "full-path")?
            .stringValue,
           !fullPath.isEmpty {
            return fullPath
        }

        // Fallback: first .musicxml / .xml under the extract root
        let enumerator = FileManager.default.enumerator(
            at: extractedRoot,
            includingPropertiesForKeys: nil
        )
        while let item = enumerator?.nextObject() as? URL {
            let ext = item.pathExtension.lowercased()
            if ext == "musicxml" || ext == "xml" {
                let rootPath = extractedRoot.standardizedFileURL.path
                let itemPath = item.standardizedFileURL.path
                if itemPath.hasPrefix(rootPath) {
                    let relative = String(itemPath.dropFirst(rootPath.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    return relative
                }
                return item.lastPathComponent
            }
        }
        throw MelodyLibraryError.ioFailure(Self.mxlMissingScoreMessage)
    }
}
