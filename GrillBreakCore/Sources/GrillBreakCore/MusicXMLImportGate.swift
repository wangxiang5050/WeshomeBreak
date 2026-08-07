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
    public let title: String
    public let musicXML: String
    public let measureCount: Int
    public let warnings: [String]

    public init(title: String, musicXML: String, measureCount: Int, warnings: [String] = []) {
        self.title = title
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
            return .rejected(reason: "Invalid MusicXML: \(error.localizedDescription)")
        }

        guard let root = document.rootElement() else {
            return .rejected(reason: "Invalid MusicXML: missing root element")
        }

        let rootName = root.name ?? ""
        guard rootName == "score-partwise" || rootName == "score-timewise" else {
            return .rejected(reason: "Invalid MusicXML: expected score-partwise or score-timewise root")
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
            warnings.append("Measure count \(measureCount) exceeds the target of 8; import is still allowed.")
        }

        let title = extractTitle(from: root) ?? "Untitled Melody"
        return .accepted(
            ImportedMelodyDraft(
                title: title,
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
            return "Multiple parts are not supported; import accepts a single part only."
        }

        let parts = elements(matching: "./part", in: root)
        if parts.count > 1 {
            return "Multiple parts are not supported; import accepts a single part only."
        }
        return nil
    }

    private func rejectForbiddenElements(in root: XMLElement) -> String? {
        // Musical content outside the Staff Melody v1 subset — reject the
        // whole file rather than silently dropping meaning.
        let forbidden: [(element: String, reason: String)] = [
            ("chord", "Chords are not supported in Staff Melody v1."),
            ("lyric", "Lyrics are not supported in Staff Melody v1."),
            ("slur", "Slurs are not supported in Staff Melody v1."),
            ("backup", "Multiple voices / layers (backup) are not supported; import accepts a single voice only."),
            ("forward", "Multiple voices / layers (forward) are not supported; import accepts a single voice only."),
            ("ornaments", "Ornaments are not supported in Staff Melody v1."),
            ("harmony", "Harmony symbols are not supported in Staff Melody v1."),
            ("figured-bass", "Figured bass is not supported in Staff Melody v1."),
            ("glissando", "Glissando is not supported in Staff Melody v1."),
            ("slide", "Slide is not supported in Staff Melody v1."),
            ("tremolo", "Tremolo is not supported in Staff Melody v1."),
            ("technical", "Technical notations are not supported in Staff Melody v1."),
            ("grace", "Grace notes are not supported in Staff Melody v1."),
            ("unpitched", "Unpitched notes are not supported in Staff Melody v1."),
            ("frame", "Chord frames are not supported in Staff Melody v1.")
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
            return "Multiple voices are not supported; import accepts a single voice only."
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
                return "Only common triplets are supported; non-triplet tuplets are rejected."
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
                    return "Nested tuplets are not supported in Staff Melody v1."
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

    private func extractTitle(from root: XMLElement) -> String? {
        if let movement = elements(matching: "./movement-title", in: root).first?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !movement.isEmpty {
            return movement
        }
        if let workTitle = elements(matching: "./work/work-title", in: root).first?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !workTitle.isEmpty {
            return workTitle
        }
        if let partName = elements(matching: ".//part-name", in: root).first?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !partName.isEmpty {
            return partName
        }
        return nil
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
