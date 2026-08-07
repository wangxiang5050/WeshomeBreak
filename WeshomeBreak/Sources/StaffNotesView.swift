import SwiftUI

/// The "五线谱音符" break scene: a standard five-line staff centered on
/// screen, with notes continuously flying in from random directions and
/// random start times, converging onto the staff to form a short phrase.
/// Pitches are drawn from a simple set of natural (C-major-ish) staff
/// positions so the result reads like a real, if illustrative, score.
///
/// Time-driven purely as a function of elapsed seconds since the view
/// appeared (via `TimelineView`), rather than mutable per-note state — each
/// "slot" deterministically replays its own randomized flight every
/// `cycleDuration` seconds, seeded by `(slot, generation)` so the pattern
/// varies from cycle to cycle without needing to store per-note state.
struct StaffNotesView: View {
    private let sceneStart = Date()

    private let slotCount = 10
    private let cycleDuration: Double = 6
    private let travelDuration: Double = 2.2
    private let holdDuration: Double = 2.4

    /// Staff position range, in half-line-spacing units above the bottom
    /// line, spanning a couple of natural notes below/above the five lines
    /// themselves (i.e. C4 through roughly D5/E5) — enough range to look
    /// like a real melodic phrase without needing ledger-line accuracy.
    private let pitchRange = -2...10

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { graphicsContext, size in
                draw(in: graphicsContext, size: size, elapsed: context.date.timeIntervalSince(sceneStart))
            }
        }
        .background(nightBackground)
        .ignoresSafeArea()
    }

    private var nightBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.04, blue: 0.09),
                Color(red: 0.06, green: 0.07, blue: 0.14)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, size: CGSize, elapsed: Double) {
        let staff = StaffGeometry(size: size)
        drawStaffLines(staff, in: context)

        for slot in 0..<slotCount {
            drawNote(for: slot, elapsed: elapsed, staff: staff, in: context)
        }
    }

    private struct StaffGeometry {
        let leftX: CGFloat
        let rightX: CGFloat
        let centerY: CGFloat
        let lineSpacing: CGFloat

        init(size: CGSize) {
            leftX = size.width * 0.15
            rightX = size.width * 0.85
            centerY = size.height / 2
            lineSpacing = min(size.height * 0.045, 32)
        }

        var halfLineSpacing: CGFloat { lineSpacing / 2 }

        /// The five staff lines are centered on `centerY`, two above and
        /// two below it.
        func lineY(_ index: Int) -> CGFloat {
            centerY + CGFloat(index - 2) * lineSpacing
        }

        /// Maps a pitch offset (in half-line-spacing units, measured from
        /// the bottom staff line) to a vertical position.
        func y(forPitchOffset offset: Int) -> CGFloat {
            lineY(4) - CGFloat(offset) * halfLineSpacing
        }
    }

    private func drawStaffLines(_ staff: StaffGeometry, in context: GraphicsContext) {
        for index in 0..<5 {
            var path = Path()
            let y = staff.lineY(index)
            path.move(to: CGPoint(x: staff.leftX, y: y))
            path.addLine(to: CGPoint(x: staff.rightX, y: y))
            context.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 1.5)
        }
    }

    /// A single note slot's deterministic flight parameters for whichever
    /// `cycleDuration`-long "generation" is currently active.
    private struct NoteSpec {
        let pitchOffset: Int
        let spawnAngle: Double
        let phraseX: CGFloat
        let startDelay: Double
    }

    private func spec(forSlot slot: Int, generation: Int) -> NoteSpec {
        var generator = SeededGenerator(slot: slot, generation: generation)
        return NoteSpec(
            pitchOffset: Int.random(in: pitchRange, using: &generator),
            spawnAngle: Double.random(in: 0..<(2 * .pi), using: &generator),
            phraseX: CGFloat.random(in: 0.1...0.9, using: &generator),
            startDelay: Double.random(in: 0..<(cycleDuration - travelDuration - holdDuration), using: &generator)
        )
    }

    private func drawNote(for slot: Int, elapsed: Double, staff: StaffGeometry, in context: GraphicsContext) {
        // Stagger each slot's cycle so all ten notes don't spawn in lockstep.
        let staggeredElapsed = elapsed + Double(slot) * (cycleDuration / Double(slotCount))
        let generation = Int(floor(staggeredElapsed / cycleDuration))
        let localTime = staggeredElapsed - Double(generation) * cycleDuration
        let spec = spec(forSlot: slot, generation: generation)

        let flightTime = localTime - spec.startDelay
        guard flightTime >= 0 else { return }

        let target = CGPoint(
            x: staff.leftX + spec.phraseX * (staff.rightX - staff.leftX),
            y: staff.y(forPitchOffset: spec.pitchOffset)
        )
        let radius = max(staff.rightX, 1) + 200
        let spawn = CGPoint(
            x: staff.centerY.isNaN ? target.x : target.x + CGFloat(cos(spec.spawnAngle)) * radius,
            y: target.y + CGFloat(sin(spec.spawnAngle)) * radius
        )

        let position: CGPoint
        let opacity: Double

        if flightTime < travelDuration {
            let progress = flightTime / travelDuration
            let eased = 1 - pow(1 - progress, 3)
            position = CGPoint(
                x: spawn.x + (target.x - spawn.x) * eased,
                y: spawn.y + (target.y - spawn.y) * eased
            )
            opacity = min(1, progress * 4)
        } else if flightTime < travelDuration + holdDuration {
            position = target
            opacity = 1
        } else {
            position = target
            let fadeElapsed = flightTime - travelDuration - holdDuration
            let fadeDuration = max(cycleDuration - spec.startDelay - travelDuration - holdDuration, 0.001)
            opacity = max(0, 1 - fadeElapsed / fadeDuration)
        }

        guard opacity > 0 else { return }
        drawNoteGlyph(at: position, opacity: opacity, in: context)
    }

    private func drawNoteGlyph(at point: CGPoint, opacity: Double, in context: GraphicsContext) {
        let noteColor = Color(red: 1, green: 0.94, blue: 0.78).opacity(opacity)
        let headRadius: CGFloat = 6

        var head = Path()
        head.addEllipse(in: CGRect(
            x: point.x - headRadius,
            y: point.y - headRadius * 0.8,
            width: headRadius * 2,
            height: headRadius * 1.6
        ))
        context.fill(head, with: .color(noteColor))

        var stem = Path()
        stem.move(to: CGPoint(x: point.x + headRadius - 1, y: point.y))
        stem.addLine(to: CGPoint(x: point.x + headRadius - 1, y: point.y - 32))
        context.stroke(stem, with: .color(noteColor), lineWidth: 2)
    }
}

/// A tiny deterministic xorshift64 generator, seeded from a note's slot
/// index and generation number. Using `RandomNumberGenerator` (rather than
/// an ad-hoc hash function) lets `spec(forSlot:generation:)` use the
/// standard `Int.random(in:using:)`/`Double.random(in:using:)` APIs while
/// still being fully reproducible within a given cycle — the same slot and
/// generation always produce the same flight, but different generations
/// (and thus different `cycleDuration`-length passes) vary the pattern.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(slot: Int, generation: Int) {
        let mixed = UInt64(bitPattern: Int64(slot) &* 1_000_003 &+ Int64(generation) &* 97 &+ 1)
        state = mixed == 0 ? 0x9E3779B97F4A7C15 : mixed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
