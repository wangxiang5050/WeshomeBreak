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
                throw MelodyLibraryError.ioFailure(
                    Self.fallbackMessage(Self.unreadableFileMessage, diagnostic: error.localizedDescription)
                )
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

    static let mxlNotAZipMessage = """
        该文件不是有效的 MXL 压缩包。
        建议用 MuseScore 或 Audiveris 重新导出 .musicxml / .mxl。
        """

    static let mxlMissingScoreMessage = """
        该 MXL 压缩包内没有可用的 MusicXML 谱面。
        建议用 MuseScore 打开后重新导出为 .musicxml 或 .mxl。
        """

    private func loadFromMXL(_ url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MelodyLibraryError.ioFailure(
                Self.fallbackMessage(Self.unreadableFileMessage, diagnostic: error.localizedDescription)
            )
        }
        let names = try zipEntryNames(in: data)
        if let rejection = Self.nonASCIINameRejection(names) {
            throw MelodyLibraryError.ioFailure(rejection)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxl-extract-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        } catch {
            throw MelodyLibraryError.ioFailure(
                Self.fallbackMessage(Self.mxlUnzipFailedMessage, diagnostic: error.localizedDescription)
            )
        }
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stderr = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", tempRoot.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw MelodyLibraryError.ioFailure(
                Self.fallbackMessage(Self.mxlUnzipFailedMessage, diagnostic: error.localizedDescription)
            )
        }
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            if Self.looksLikeCorruptZip(stderrText) {
                throw MelodyLibraryError.ioFailure(Self.mxlNotAZipMessage)
            }
            throw MelodyLibraryError.ioFailure(
                Self.fallbackMessage(Self.mxlUnzipFailedMessage, diagnostic: stderrText)
            )
        }

        let scoreRelativePath = try resolveRootfilePath(in: tempRoot)
        let scoreURL = tempRoot.appendingPathComponent(scoreRelativePath)
        do {
            return try String(contentsOf: scoreURL, encoding: .utf8)
        } catch {
            throw MelodyLibraryError.ioFailure(
                Self.fallbackMessage(Self.unreadableFileMessage, diagnostic: error.localizedDescription)
            )
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

    /// Central-directory entry names. Throws `mxlNotAZipMessage` when the file is not a zip.
    private func zipEntryNames(in data: Data) throws -> [String] {
        guard let eocdOffset = Self.endOfCentralDirectoryOffset(in: data) else {
            throw MelodyLibraryError.ioFailure(Self.mxlNotAZipMessage)
        }
        let entryCount = Int(Self.u16(data, eocdOffset + 10))
        var offset = Int(Self.u32(data, eocdOffset + 16))
        var names: [String] = []
        names.reserveCapacity(entryCount)
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, Self.u32(data, offset) == 0x02014b50 else {
                throw MelodyLibraryError.ioFailure(Self.mxlNotAZipMessage)
            }
            let flags = Self.u16(data, offset + 8)
            let nameLength = Int(Self.u16(data, offset + 28))
            let extraLength = Int(Self.u16(data, offset + 30))
            let commentLength = Int(Self.u16(data, offset + 32))
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else {
                throw MelodyLibraryError.ioFailure(Self.mxlNotAZipMessage)
            }
            let nameBytes = data[nameStart..<nameEnd]
            names.append(Self.decodeZipName(nameBytes, utf8Flag: (flags & 0x0800) != 0))
            offset = nameEnd + extraLength + commentLength
        }
        return names
    }

    private static func nonASCIINameRejection(_ names: [String]) -> String? {
        let offending = names.filter { $0.unicodeScalars.contains { $0.value > 127 } }
        guard let first = offending.first else { return nil }
        let display = truncatedDisplayName(first)
        let quoted = offending.count > 1 ? "「\(display)」等" : "「\(display)」"
        return """
            压缩包内文件名为\(quoted)，含非英文字符，当前无法解压。
            请在 Audiveris 把工程名改成英文后重新导出，或导出为 .musicxml 再导入。
            """
    }

    private static func truncatedDisplayName(_ name: String) -> String {
        if name.count <= 60 { return name }
        return String(name.prefix(60)) + "…"
    }

    static func fallbackMessage(_ chinese: String, diagnostic: String) -> String {
        let detail = sanitizedDiagnostic(diagnostic)
        if detail.isEmpty { return chinese }
        return chinese + "\n详情：" + detail
    }

    private static func sanitizedDiagnostic(_ raw: String) -> String {
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                let lower = line.lowercased()
                return !lower.hasPrefix("archive:")
                    && !lower.hasPrefix("inflating:")
                    && !lower.hasPrefix("extracting:")
                    && !lower.hasPrefix("creating:")
            }
        let preferred = lines.first { line in
            let lower = line.lowercased()
            return lower.contains("error")
                || lower.contains("cannot")
                || lower.contains("illegal")
                || lower.contains("password")
                || lower.contains("couldn't")
                || lower.contains("could not")
                || lower.contains("无法")
        }
        var text = String(preferred ?? lines.first ?? "")
        text = text.replacingOccurrences(
            of: #"(/var/folders|/private/tmp|/tmp)/\S+"#,
            with: "…",
            options: .regularExpression
        )
        if text.count > 80 {
            text = String(text.prefix(80))
        }
        return text
    }

    private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        let minimumEOCD = 22
        guard data.count >= minimumEOCD else { return nil }
        let maxComment = min(65535, data.count - minimumEOCD)
        for commentLength in 0...maxComment {
            let offset = data.count - minimumEOCD - commentLength
            if Self.u32(data, offset) == 0x06054b50,
               Int(Self.u16(data, offset + 20)) == commentLength {
                return offset
            }
        }
        return nil
    }

    private static func decodeZipName(_ bytes: Data, utf8Flag: Bool) -> String {
        if utf8Flag, let utf8 = String(data: bytes, encoding: .utf8) {
            return utf8
        }
        if let utf8 = String(data: bytes, encoding: .utf8) {
            return utf8
        }
        return String(data: bytes, encoding: .isoLatin1) ?? ""
    }

    private static func looksLikeCorruptZip(_ stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("end-of-central-directory")
            || lower.contains("not a zip")
            || lower.contains("invalid compressed data")
            || (lower.contains("zipfile") && lower.contains("cannot"))
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
