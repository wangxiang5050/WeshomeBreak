import Foundation

/// Result of evaluating a MusicXML document against the Staff Melody v1 subset.
public enum MusicXMLImportResult: Equatable, Sendable {
    /// Document is within the subset (optionally with non-fatal warnings).
    case accepted(ImportedMelodyDraft)
    /// Document is outside the subset; the whole file is rejected.
    case rejected(reason: String)
}

/// A melody that passed the import gate and is ready to enter the Melody Library.
public struct ImportedMelodyDraft: Equatable, Sendable {
    public let musicXML: String
    public let measureCount: Int
    public let warnings: [String]

    public init(musicXML: String, measureCount: Int, warnings: [String] = []) {
        self.musicXML = musicXML
        self.measureCount = measureCount
        self.warnings = warnings
    }
}

/// Enforces the Staff Melody v1 MusicXML subset: accept monophonic excerpts,
/// reject out-of-scope content entirely (never silently drop elements).
public struct MusicXMLImportGate: Sendable {
    public init() {}

    public func evaluate(_ musicXML: String) -> MusicXMLImportResult {
        let document: XMLDocument
        do {
            document = try XMLDocument(xmlString: musicXML, options: [])
        } catch {
            return .rejected(reason: "无效的 MusicXML：\(error.localizedDescription)")
        }

        guard let root = document.rootElement() else {
            return .rejected(reason: "无效的 MusicXML：缺少根元素")
        }

        let rootName = root.name ?? ""
        guard rootName == "score-partwise" || rootName == "score-timewise" else {
            return .rejected(reason: "无效的 MusicXML：根元素应为 score-partwise 或 score-timewise")
        }

        if let rejection = rejectMultipleParts(in: root) {
            return .rejected(reason: rejection)
        }
        if let rejection = rejectForbiddenElements(in: root) {
            return .rejected(reason: rejection)
        }
        if let rejection = rejectMultipleVoices(in: root) {
            return .rejected(reason: rejection)
        }
        if let rejection = rejectInvalidTuplets(in: root) {
            return .rejected(reason: rejection)
        }

        let measureCount = countMeasures(in: root)
        var warnings: [String] = []
        if measureCount > 8 {
            warnings.append("小节数为 \(measureCount)，超过目标 8 小节；仍允许导入。")
        }

        return .accepted(
            ImportedMelodyDraft(
                musicXML: musicXML,
                measureCount: measureCount,
                warnings: warnings
            )
        )
    }

    // MARK: - Checks

    private func rejectMultipleParts(in root: XMLElement) -> String? {
        let scoreParts = elements(matching: ".//score-part", in: root)
        if scoreParts.count > 1 {
            return "不支持多个 Part，仅接受单声部谱。"
        }

        let parts = elements(matching: "./part", in: root)
        if parts.count > 1 {
            return "不支持多个 Part，仅接受单声部谱。"
        }
        return nil
    }

    private func rejectForbiddenElements(in root: XMLElement) -> String? {
        // Musical content outside the Staff Melody v1 subset — reject the
        // whole file rather than silently dropping meaning.
        let forbidden: [(element: String, reason: String)] = [
            ("chord", "Staff Melody v1 不支持和弦（chord）。"),
            ("lyric", "Staff Melody v1 不支持歌词（lyric）。"),
            ("slur", "Staff Melody v1 不支持圆滑线（slur）。"),
            ("backup", "不支持多声部 / 层（backup），仅接受单 voice。"),
            ("forward", "不支持多声部 / 层（forward），仅接受单 voice。"),
            ("ornaments", "Staff Melody v1 不支持装饰音（ornaments）。"),
            ("harmony", "Staff Melody v1 不支持和声标记（harmony）。"),
            ("figured-bass", "Staff Melody v1 不支持数字低音。"),
            ("glissando", "Staff Melody v1 不支持滑音（glissando）。"),
            ("slide", "Staff Melody v1 不支持 slide。"),
            ("tremolo", "Staff Melody v1 不支持震音（tremolo）。"),
            ("technical", "Staff Melody v1 不支持演奏技法记号。"),
            ("grace", "Staff Melody v1 不支持倚音（grace）。"),
            ("unpitched", "Staff Melody v1 不支持无音高音符。"),
            ("frame", "Staff Melody v1 不支持和弦框。")
        ]
        for item in forbidden where elementExists(named: item.element, in: root) {
            return item.reason
        }
        return nil
    }

    private func rejectMultipleVoices(in root: XMLElement) -> String? {
        let voiceNodes = elements(matching: ".//voice", in: root)
        let voices = Set(voiceNodes.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        if voices.count > 1 {
            return "不支持多个 voice，仅接受单声部。"
        }
        return nil
    }

    private func rejectInvalidTuplets(in root: XMLElement) -> String? {
        // Non-triplet time-modification ratios
        let modifications = elements(matching: ".//time-modification", in: root)
        for mod in modifications {
            let actual = intValue(ofChild: "actual-notes", in: mod) ?? 0
            let normal = intValue(ofChild: "normal-notes", in: mod) ?? 0
            if !(actual == 3 && normal == 2) {
                return "仅支持常见三连音；非三连音的 tuplet 会被拒绝。"
            }
        }

        // Nested tuplets: a start while another tuplet number is already open
        let tupletMarks = elements(matching: ".//tuplet", in: root)
        var openNumbers = Set<String>()
        for mark in tupletMarks {
            let type = mark.attribute(forName: "type")?.stringValue ?? ""
            let number = mark.attribute(forName: "number")?.stringValue ?? "1"
            if type == "start" {
                if !openNumbers.isEmpty {
                    return "Staff Melody v1 不支持嵌套 tuplet。"
                }
                openNumbers.insert(number)
            } else if type == "stop" {
                openNumbers.remove(number)
            }
        }
        return nil
    }

    private func countMeasures(in root: XMLElement) -> Int {
        elements(matching: ".//measure", in: root).count
    }

    private func elementExists(named name: String, in root: XMLElement) -> Bool {
        !elements(matching: ".//\(name)", in: root).isEmpty
    }

    private func intValue(ofChild name: String, in element: XMLElement) -> Int? {
        guard let child = elements(matching: "./\(name)", in: element).first,
              let text = child.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return Int(text)
    }

    private func elements(matching xpath: String, in element: XMLElement) -> [XMLElement] {
        (try? element.nodes(forXPath: xpath) as? [XMLElement]) ?? []
    }
}
