import Foundation

/// How fast Melody Playback goes. One choice for every User Melody.
/// Quarter-note speeds: 慢板 60, 行板 72, 中板 96, 快板 120, 急板 144.
public enum PlaybackTempo: Int, CaseIterable, Sendable, Equatable {
    case lento = 60
    case andante = 72
    case moderato = 96
    case allegro = 120
    case presto = 144

    public static let defaultTempo = PlaybackTempo.andante

    public var quartersPerMinute: Double { Double(rawValue) }

    public var settingsTitle: String {
        switch self {
        case .lento: "慢板 60"
        case .andante: "行板 72"
        case .moderato: "中板 96"
        case .allegro: "快板 120"
        case .presto: "急板 144"
        }
    }
}

/// Where Melody Playback is currently coming out.
public enum PlaybackOutput: Sendable, Equatable {
    case headphones
    case speakers
}

public enum MelodyPlaybackPhase: Sendable, Equatable {
    case idle
    case playing
    case paused
    case finished
}

public struct PlaybackAttack: Sendable, Equatable {
    public var midi: Int
    public var velocity: Int
    public var soundingSeconds: TimeInterval

    public init(midi: Int, velocity: Int, soundingSeconds: TimeInterval) {
        self.midi = midi
        self.velocity = velocity
        self.soundingSeconds = soundingSeconds
    }
}

/// Vertical line on the engraved staff: which written note or rest, and how
/// far through that event's performed time the line has walked.
public struct PlaybackLine: Sendable, Equatable {
    public var eventIndex: Int
    public var fractionThroughEvent: Double

    public init(eventIndex: Int, fractionThroughEvent: Double) {
        self.eventIndex = eventIndex
        self.fractionThroughEvent = fractionThroughEvent
    }
}

public struct MelodyPlaybackMoment: Sendable, Equatable {
    public var phase: MelodyPlaybackPhase
    public var offersStart: Bool
    public var attacks: [PlaybackAttack]
    public var silenced: Bool
    public var line: PlaybackLine?

    public init(
        phase: MelodyPlaybackPhase,
        offersStart: Bool,
        attacks: [PlaybackAttack],
        silenced: Bool,
        line: PlaybackLine?
    ) {
        self.phase = phase
        self.offersStart = offersStart
        self.attacks = attacks
        self.silenced = silenced
        self.line = line
    }
}

/// Sounds one User Melody as piano from its stored notation.
public final class MelodyPlayback {
    public private(set) var tempo: PlaybackTempo
    public var isAvailable: Bool { !spans.isEmpty }

    private var phase: MelodyPlaybackPhase = .idle
    private var quarter: Double = 0
    private var output: PlaybackOutput = .speakers
    private var spans: [Span] = []

    public init(musicXML: String?, tempo: PlaybackTempo) {
        self.tempo = tempo
        load(musicXML)
    }

    public func start() -> MelodyPlaybackMoment {
        guard isAvailable else { return moment(attacks: [], silenced: false) }
        if phase == .playing { return moment(attacks: [], silenced: false) }
        if phase == .paused, let span = span(containing: quarter) {
            quarter = span.attackStart
        } else {
            quarter = 0
        }
        phase = .playing
        return moment(attacks: attacks(at: quarter), silenced: false)
    }

    public func pause() -> MelodyPlaybackMoment {
        guard phase == .playing else { return moment(attacks: [], silenced: false) }
        phase = .paused
        return moment(attacks: [], silenced: true)
    }

    public func advance(seconds: TimeInterval) -> MelodyPlaybackMoment {
        guard phase == .playing, seconds > 0 else {
            return moment(attacks: [], silenced: false)
        }
        let previous = quarter
        let next = previous + seconds * tempo.quartersPerMinute / 60
        let total = spans.last.map { $0.performanceStart + $0.performanceQuarters } ?? 0
        if next >= total - 1e-9 {
            let crossed = spans.filter {
                $0.isAttack && $0.performanceStart > previous + 1e-9 && $0.performanceStart < total - 1e-9
            }
            quarter = total
            phase = .finished
            return moment(attacks: crossed.map(attack), silenced: true)
        }
        let crossed = spans.filter {
            $0.isAttack && $0.performanceStart > previous + 1e-9 && $0.performanceStart <= next + 1e-9
        }
        quarter = next
        return moment(attacks: crossed.map(attack), silenced: false)
    }

    /// Headphones becoming speakers while a note is going is one pause.
    /// Moving onto headphones, or from one headphone output to another, keeps playing.
    public func noteOutput(_ output: PlaybackOutput) -> MelodyPlaybackMoment {
        let previous = self.output
        self.output = output
        if phase == .playing, previous == .headphones, output == .speakers {
            return pause()
        }
        return moment(attacks: [], silenced: false)
    }

    public func dismiss() -> MelodyPlaybackMoment {
        let stop = phase == .playing || phase == .paused
        phase = .idle
        quarter = 0
        return moment(attacks: [], silenced: stop)
    }

    public func replace(musicXML: String?) -> MelodyPlaybackMoment {
        let stop = phase == .playing || phase == .paused
        load(musicXML)
        phase = .idle
        quarter = 0
        return moment(attacks: [], silenced: stop)
    }

    public var moment: MelodyPlaybackMoment {
        moment(attacks: [], silenced: false)
    }

    private func moment(attacks: [PlaybackAttack], silenced: Bool) -> MelodyPlaybackMoment {
        MelodyPlaybackMoment(
            phase: phase,
            offersStart: phase != .playing && isAvailable,
            attacks: attacks,
            silenced: silenced,
            line: line()
        )
    }

    private func line() -> PlaybackLine? {
        guard phase == .playing || phase == .paused else { return nil }
        guard let span = span(containing: quarter) else { return nil }
        let fraction: Double
        if span.performanceQuarters <= 0 {
            fraction = 0
        } else {
            fraction = (quarter - span.performanceStart) / span.performanceQuarters
        }
        return PlaybackLine(
            eventIndex: span.eventIndex,
            fractionThroughEvent: min(1, max(0, fraction))
        )
    }

    private func span(containing quarter: Double) -> Span? {
        spans.first {
            quarter + 1e-9 >= $0.performanceStart
                && quarter < $0.performanceStart + $0.performanceQuarters - 1e-9
        } ?? spans.last(where: { abs(($0.performanceStart + $0.performanceQuarters) - quarter) < 1e-6 })
    }

    private func attacks(at quarter: Double) -> [PlaybackAttack] {
        spans.filter { $0.isAttack && abs($0.performanceStart - quarter) < 1e-6 }.map(attack)
    }

    private func attack(_ span: Span) -> PlaybackAttack {
        PlaybackAttack(
            midi: span.midi ?? 0,
            velocity: span.velocity,
            soundingSeconds: span.soundingQuarters * 60 / tempo.quartersPerMinute
        )
    }

    private func load(_ musicXML: String?) {
        spans = musicXML.flatMap { ScorePerformance.spans(from: $0) } ?? []
    }
}

private struct Span {
    var performanceStart: Double
    var performanceQuarters: Double
    var soundingQuarters: Double
    var midi: Int?
    var velocity: Int
    var eventIndex: Int
    var attackStart: Double
    var isAttack: Bool
}

private enum ScorePerformance {
    static func spans(from musicXML: String) -> [Span] {
        guard let document = try? XMLDocument(xmlString: musicXML, options: [.nodeLoadExternalEntitiesNever]),
              let root = document.rootElement()
        else { return [] }

        let measures = parsedMeasures(in: root)
        let order = unfold(measures)
        return perform(measures, visits: order)
    }

    private static func parsedMeasures(in root: XMLElement) -> [ParsedMeasure] {
        let measureElements: [XMLElement]
        if root.name == "score-timewise" {
            measureElements = root.elements(forName: "measure")
        } else {
            measureElements = root.elements(forName: "part").flatMap { $0.elements(forName: "measure") }
        }

        var divisions = 1
        var octaveShift = 0
        var eventIndex = 0
        var activeEnding: Set<Int>?
        var measures: [ParsedMeasure] = []

        for element in measureElements {
            var measure = ParsedMeasure()
            var pendingEndingStop = false
            for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                switch child.name {
                case "attributes":
                    if let value = text(child, "divisions"), let parsed = Int(value), parsed > 0 {
                        divisions = parsed
                    }
                case "note":
                    if !child.elements(forName: "chord").isEmpty { break }
                    let parsed = parseNote(child, divisions: divisions, octaveShift: octaveShift, eventIndex: eventIndex)
                    eventIndex += 1
                    measure.events.append(parsed)
                case "direction":
                    let parsed = parseDirection(child, octaveShift: &octaveShift)
                    measure.events.append(contentsOf: parsed.events)
                    measure.absorb(parsed.marks)
                case "sound":
                    measure.absorb(parseSound(child))
                case "barline":
                    let parsed = parseBarline(child)
                    measure.absorb(parsed.marks)
                    if let numbers = parsed.endingStart {
                        activeEnding = numbers
                    }
                    if parsed.endingStops {
                        pendingEndingStop = true
                    }
                default:
                    break
                }
            }
            measure.endingNumbers = activeEnding
            if pendingEndingStop {
                activeEnding = nil
            }
            measures.append(measure)
        }
        return measures
    }

    private static func unfold(_ measures: [ParsedMeasure]) -> [Int] {
        var visits: [Int] = []
        var index = 0
        var iteration = 1
        var repeatStart = 0
        var dcTaken = false
        var dsTaken = false
        var stopAtFine = false
        var jumpToCoda = false
        var steps = 0
        let segno = measures.firstIndex { $0.marks.segno }
        let coda = measures.firstIndex { $0.marks.coda }

        while index < measures.count && steps < 2000 {
            steps += 1
            let measure = measures[index]
            if let endings = measure.endingNumbers, !endings.contains(iteration) {
                index += 1
                continue
            }
            visits.append(index)

            var jumped = false
            if let times = measure.marks.backwardRepeatTimes, iteration < times {
                iteration += 1
                index = repeatStart
                jumped = true
            } else if measure.marks.backwardRepeatTimes != nil {
                iteration = 1
            }
            if measure.marks.forwardRepeat {
                repeatStart = index
            }

            // A D.C. or D.S. is taken once. The pass it starts plays the
            // written repeats again; that is the jump, not a second jump.
            if !jumped, measure.marks.dc, !dcTaken {
                dcTaken = true
                stopAtFine = measure.marks.alFine
                jumpToCoda = measure.marks.alCoda
                iteration = 1
                index = 0
                jumped = true
            } else if !jumped, measure.marks.ds, !dsTaken, let segno {
                dsTaken = true
                stopAtFine = measure.marks.alFine
                jumpToCoda = measure.marks.alCoda
                iteration = 1
                index = segno
                jumped = true
            }

            if !jumped, stopAtFine, measure.marks.fine {
                break
            }
            if !jumped, jumpToCoda, measure.marks.toCoda, let coda {
                jumpToCoda = false
                index = coda
                continue
            }
            if !jumped {
                index += 1
            }
        }
        return visits
    }

    private static func perform(_ measures: [ParsedMeasure], visits: [Int]) -> [Span] {
        var spans: [Span] = []
        var performance: Double = 0
        var dynamic = "mf"
        var wedge: Int?
        var dynamicMarkedSinceWedge = false
        var pendingSfz = false
        var pendingFp = false
        var openTie: (midi: Int, index: Int)?

        for visit in visits where measures.indices.contains(visit) {
            for event in measures[visit].events {
                switch event {
                case .dynamic(let name):
                    if let canonical = canonicalDynamic(name) {
                        dynamic = canonical
                        if wedge != nil { dynamicMarkedSinceWedge = true }
                    }
                case .nextAttack(let sfz, let fp):
                    pendingSfz = sfz
                    pendingFp = fp
                case .wedge(let direction):
                    switch direction {
                    case .crescendo:
                        wedge = 1
                        dynamicMarkedSinceWedge = false
                    case .diminuendo:
                        wedge = -1
                        dynamicMarkedSinceWedge = false
                    case .stop:
                        if let wedge, !dynamicMarkedSinceWedge {
                            dynamic = stepped(dynamic, by: wedge)
                        }
                        wedge = nil
                        dynamicMarkedSinceWedge = false
                    }
                case .note(let note):
                    var slot = note.quarters
                    if note.fermata { slot *= 2 }
                    var sounding = note.midi == nil ? 0 : slot
                    if note.staccato, note.midi != nil { sounding *= 0.5 }
                    var velocity = velocities[ladder.firstIndex(of: dynamic) ?? ladder.firstIndex(of: "mf")!]
                    if note.fp || pendingFp {
                        velocity = velocities[ladder.firstIndex(of: "f") ?? 6]
                        dynamic = "p"
                    }
                    if note.sfz || pendingSfz {
                        velocity = velocities[ladder.firstIndex(of: "ff") ?? 7]
                    }
                    pendingSfz = false
                    pendingFp = false
                    if note.accent {
                        velocity = min(127, velocity + 16)
                    }
                    let continues = note.tieStop && openTie?.midi == note.midi && note.midi != nil
                    if continues, let openTie {
                        spans[openTie.index].soundingQuarters += sounding
                        spans.append(Span(
                            performanceStart: performance,
                            performanceQuarters: slot,
                            soundingQuarters: 0,
                            midi: note.midi,
                            velocity: velocity,
                            eventIndex: note.eventIndex,
                            attackStart: spans[openTie.index].attackStart,
                            isAttack: false
                        ))
                    } else {
                        let attack = note.midi != nil
                        spans.append(Span(
                            performanceStart: performance,
                            performanceQuarters: slot,
                            soundingQuarters: sounding,
                            midi: note.midi,
                            velocity: velocity,
                            eventIndex: note.eventIndex,
                            attackStart: performance,
                            isAttack: attack
                        ))
                        openTie = nil
                    }
                    if note.tieStart, let midi = note.midi {
                        let attackIndex = continues ? (openTie?.index ?? spans.count - 1) : spans.count - 1
                        openTie = (midi, attackIndex)
                    } else {
                        openTie = nil
                    }
                    performance += slot
                }
            }
        }
        return spans
    }
}

private struct ParsedMeasure {
    var events: [RawEvent] = []
    var marks = JumpMarks()
    var endingNumbers: Set<Int>?

    mutating func absorb(_ marks: JumpMarks) {
        self.marks = self.marks.merging(marks)
    }
}

private struct JumpMarks {
    var segno = false
    var coda = false
    var fine = false
    var toCoda = false
    var dc = false
    var ds = false
    var alFine = false
    var alCoda = false
    var forwardRepeat = false
    var backwardRepeatTimes: Int?
}

private enum RawEvent {
    case dynamic(String)
    case wedge(Wedge)
    case nextAttack(sfz: Bool, fp: Bool)
    case note(RawNote)
}

private enum Wedge {
    case crescendo
    case diminuendo
    case stop
}

private struct RawNote {
    var quarters: Double
    var midi: Int?
    var eventIndex: Int
    var staccato: Bool
    var accent: Bool
    var fermata: Bool
    var sfz: Bool
    var fp: Bool
    var tieStart: Bool
    var tieStop: Bool
}

private let ladder = ["ppp", "pp", "p", "mp", "mf", "f", "ff", "fff"]
private let velocities = [28, 40, 54, 68, 84, 100, 112, 122]

private func canonicalDynamic(_ name: String) -> String? {
    switch name {
    case "pppp": return "ppp"
    case "ffff": return "fff"
    default: return ladder.contains(name) ? name : nil
    }
}

private func stepped(_ name: String, by delta: Int) -> String {
    guard let index = ladder.firstIndex(of: name) else { return name }
    let next = min(ladder.count - 1, max(0, index + delta))
    return ladder[next]
}

private func parseNote(_ note: XMLElement, divisions: Int, octaveShift: Int, eventIndex: Int) -> RawEvent {
    let duration = Int(text(note, "duration") ?? "") ?? divisions
    let quarters = Double(duration) / Double(max(divisions, 1))
    let isRest = !note.elements(forName: "rest").isEmpty
    var midi: Int?
    if !isRest, let pitch = note.elements(forName: "pitch").first {
        let step = text(pitch, "step") ?? "C"
        let octave = Int(text(pitch, "octave") ?? "") ?? 4
        let alter = Int(Double(text(pitch, "alter") ?? "") ?? 0)
        midi = midiNumber(step: step, alter: alter, octave: octave + octaveShift)
    }
    let notations = note.elements(forName: "notations")
    let articulationNames = notations
        .flatMap { $0.elements(forName: "articulations") }
        .flatMap { $0.children?.compactMap { $0 as? XMLElement } ?? [] }
        .map(\.name)
    let has = { (name: String) in articulationNames.contains(name) }
    let fermata = notations.contains { !$0.elements(forName: "fermata").isEmpty }
    let tieTypes = note.elements(forName: "tie").compactMap { $0.attribute(forName: "type")?.stringValue }
        + notations.flatMap { $0.elements(forName: "tied") }.compactMap { $0.attribute(forName: "type")?.stringValue }
    return .note(RawNote(
        quarters: quarters,
        midi: midi,
        eventIndex: eventIndex,
        staccato: has("staccato"),
        accent: has("accent"),
        fermata: fermata,
        sfz: false,
        fp: false,
        tieStart: tieTypes.contains("start"),
        tieStop: tieTypes.contains("stop")
    ))
}

private func parseDirection(_ direction: XMLElement, octaveShift: inout Int) -> (events: [RawEvent], marks: JumpMarks) {
    var events: [RawEvent] = []
    var marks = JumpMarks()
    for type in direction.elements(forName: "direction-type") {
        for dynamics in type.elements(forName: "dynamics") {
            for child in dynamics.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                if let name = child.name, ladder.contains(name) || ["sfz", "sf", "fz", "fp"].contains(name) {
                    if canonicalDynamic(name) != nil {
                        events.append(.dynamic(name))
                    } else {
                        events.append(.nextAttack(sfz: name != "fp", fp: name == "fp"))
                    }
                }
            }
        }
        for wedge in type.elements(forName: "wedge") {
            switch wedge.attribute(forName: "type")?.stringValue {
            case "crescendo": events.append(.wedge(.crescendo))
            case "diminuendo": events.append(.wedge(.diminuendo))
            case "stop": events.append(.wedge(.stop))
            default: break
            }
        }
        for shift in type.elements(forName: "octave-shift") {
            octaveShift = octaveShiftValue(shift)
        }
        if !type.elements(forName: "segno").isEmpty { marks.segno = true }
        if !type.elements(forName: "coda").isEmpty { marks.coda = true }
        for words in type.elements(forName: "words") {
            marks = marks.merging(marksFromWords(words.stringValue ?? ""))
        }
    }
    for sound in direction.elements(forName: "sound") {
        marks = marks.merging(parseSound(sound))
    }
    return (events, marks)
}

private func parseSound(_ sound: XMLElement) -> JumpMarks {
    var marks = JumpMarks()
    if sound.attribute(forName: "segno") != nil { marks.segno = true }
    if sound.attribute(forName: "coda") != nil { marks.coda = true }
    if sound.attribute(forName: "fine")?.stringValue == "yes" { marks.fine = true }
    if sound.attribute(forName: "tocoda") != nil { marks.toCoda = true }
    if sound.attribute(forName: "dacapo")?.stringValue == "yes" {
        marks.dc = true
    }
    if sound.attribute(forName: "dalsegno") != nil {
        marks.ds = true
    }
    return marks
}

private func parseBarline(_ barline: XMLElement) -> (marks: JumpMarks, endingStart: Set<Int>?, endingStops: Bool) {
    var marks = JumpMarks()
    var endingStart: Set<Int>?
    var endingStops = false
    for rep in barline.elements(forName: "repeat") {
        switch rep.attribute(forName: "direction")?.stringValue {
        case "forward":
            marks.forwardRepeat = true
        case "backward":
            marks.backwardRepeatTimes = Int(rep.attribute(forName: "times")?.stringValue ?? "") ?? 2
        default:
            break
        }
    }
    for ending in barline.elements(forName: "ending") {
        let type = ending.attribute(forName: "type")?.stringValue
        if type == "start" {
            let numbers = (ending.attribute(forName: "number")?.stringValue ?? "")
                .split { $0 == "," || $0 == " " }
                .compactMap { Int($0) }
            endingStart = Set(numbers)
        }
        if type == "stop" || type == "discontinue" {
            endingStops = true
        }
    }
    return (marks, endingStart, endingStops)
}

private func marksFromWords(_ raw: String) -> JumpMarks {
    let text = raw.lowercased()
    var marks = JumpMarks()
    if text.contains("d.c.") || text.contains("d. c.") || text.contains("da capo") {
        marks.dc = true
    }
    if text.contains("d.s.") || text.contains("d. s.") || text.contains("dal segno") {
        marks.ds = true
    }
    if text.contains("al coda") || text.contains("to coda") {
        marks.alCoda = true
        marks.toCoda = text.contains("to coda")
    }
    if text.contains("al fine") {
        marks.alFine = true
    } else if text.contains("fine") {
        marks.fine = true
    }
    return marks
}

private func octaveShiftValue(_ shift: XMLElement) -> Int {
    let type = shift.attribute(forName: "type")?.stringValue
    if type == "stop" { return 0 }
    let size = Int(shift.attribute(forName: "size")?.stringValue ?? "") ?? 8
    let octaves = size >= 15 ? 2 : 1
    return type == "down" ? -octaves : octaves
}

private func midiNumber(step: String, alter: Int, octave: Int) -> Int {
    let steps = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    return (octave + 1) * 12 + (steps[step] ?? 0) + alter
}

private func text(_ element: XMLElement, _ name: String) -> String? {
    element.elements(forName: name).first?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

extension JumpMarks {
    func merging(_ other: JumpMarks) -> JumpMarks {
        var copy = self
        copy.segno = segno || other.segno
        copy.coda = coda || other.coda
        copy.fine = fine || other.fine
        copy.toCoda = toCoda || other.toCoda
        copy.dc = dc || other.dc
        copy.ds = ds || other.ds
        copy.alFine = alFine || other.alFine
        copy.alCoda = alCoda || other.alCoda
        copy.forwardRepeat = forwardRepeat || other.forwardRepeat
        if let times = other.backwardRepeatTimes {
            copy.backwardRepeatTimes = times
        }
        return copy
    }
}
