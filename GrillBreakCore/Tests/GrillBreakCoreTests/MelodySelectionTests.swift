import Foundation
import Testing
@testable import GrillBreakCore

@Suite("MelodySelection")
struct MelodySelectionTests {

    private let alpha = UserMelody(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, title: "A", measureCount: 4)
    private let beta = UserMelody(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, title: "B", measureCount: 4)
    private let gamma = UserMelody(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!, title: "C", measureCount: 4)

    @Test("a new random rest picks the indexed melody and records it as last shown")
    func randomRestRecordsTheIndexedMelody() {
        let state = MelodySelectionState(randomIndex: { _ in 1 })

        let melody = state.beginPresentation(
            melodies: [alpha, beta, gamma],
            using: .randomNoRepeat,
            continuingSameRest: false
        )

        #expect(melody?.id == beta.id)
        #expect(state.lastShownMelodyID == beta.id)
    }

    @Test("the next random rest excludes the melody shown last time")
    func randomRestExcludesLastShown() {
        let state = MelodySelectionState(lastShownMelodyID: alpha.id, randomIndex: { _ in 0 })

        let melody = state.beginPresentation(
            melodies: [alpha, beta, gamma],
            using: .randomNoRepeat,
            continuingSameRest: false
        )

        #expect(melody?.id == beta.id)
        #expect(state.lastShownMelodyID == beta.id)
    }

    @Test("a library of two melodies alternates across new rests")
    func twoMelodiesAlternate() {
        let state = MelodySelectionState(randomIndex: { _ in 0 })

        let first = state.beginPresentation(
            melodies: [alpha, beta],
            using: .randomNoRepeat,
            continuingSameRest: false
        )
        let second = state.beginPresentation(
            melodies: [alpha, beta],
            using: .randomNoRepeat,
            continuingSameRest: false
        )
        let third = state.beginPresentation(
            melodies: [alpha, beta],
            using: .randomNoRepeat,
            continuingSameRest: false
        )

        #expect(first?.id == alpha.id)
        #expect(second?.id == beta.id)
        #expect(third?.id == alpha.id)
    }

    @Test("the only melody is shown again even when it was last shown")
    func singleMelodyWaivesExclusion() {
        let state = MelodySelectionState(lastShownMelodyID: alpha.id, randomIndex: { _ in 0 })

        let melody = state.beginPresentation(
            melodies: [alpha],
            using: .randomNoRepeat,
            continuingSameRest: false
        )

        #expect(melody?.id == alpha.id)
    }

    @Test("an empty library leaves the last shown melody in place")
    func emptyLibraryDoesNotClearLastShown() {
        let state = MelodySelectionState(lastShownMelodyID: alpha.id, randomIndex: { _ in 0 })

        let melody = state.beginPresentation(
            melodies: [],
            using: .randomNoRepeat,
            continuingSameRest: false
        )

        #expect(melody == nil)
        #expect(state.lastShownMelodyID == alpha.id)
    }

    @Test("a deleted last-shown melody is not excluded from the remaining library")
    func deletedLastShownIsNotExcluded() {
        let state = MelodySelectionState(lastShownMelodyID: alpha.id, randomIndex: { _ in 0 })

        let melody = state.beginPresentation(
            melodies: [beta, gamma],
            using: .randomNoRepeat,
            continuingSameRest: false
        )

        #expect(melody?.id == beta.id)
    }

    @Test("a manual rest shows the pinned melody and records it as last shown")
    func manualRestRecordsThePin() {
        let state = MelodySelectionState(lastShownMelodyID: alpha.id, randomIndex: { _ in 0 })

        let melody = state.beginPresentation(
            melodies: [alpha, beta],
            using: .manual(melodyID: beta.id),
            continuingSameRest: false
        )

        #expect(melody?.id == beta.id)
        #expect(state.lastShownMelodyID == beta.id)
    }

    @Test("a manual rest with no pin leaves the last shown melody in place")
    func manualRestWithoutPinDoesNotClearLastShown() {
        let state = MelodySelectionState(lastShownMelodyID: alpha.id, randomIndex: { _ in 0 })

        let melody = state.beginPresentation(
            melodies: [alpha, beta],
            using: .manual(melodyID: nil),
            continuingSameRest: false
        )

        #expect(melody == nil)
        #expect(state.lastShownMelodyID == alpha.id)
    }

    @Test("a continuing rest shows the held melody again")
    func continuingRestReusesHeldMelody() {
        let state = MelodySelectionState(randomIndex: { _ in 0 })
        _ = state.beginPresentation(
            melodies: [alpha, beta, gamma],
            using: .randomNoRepeat,
            continuingSameRest: false
        )

        let again = state.beginPresentation(
            melodies: [alpha, beta, gamma],
            using: .manual(melodyID: gamma.id),
            continuingSameRest: true
        )

        #expect(again?.id == alpha.id)
        #expect(state.lastShownMelodyID == alpha.id)
    }

    @Test("a continuing rest whose melody left the library draws a replacement")
    func continuingRestRedrawsWhenHeldMelodyIsGone() {
        let state = MelodySelectionState(randomIndex: { _ in 0 })
        _ = state.beginPresentation(
            melodies: [alpha, beta],
            using: .manual(melodyID: alpha.id),
            continuingSameRest: false
        )

        let melody = state.beginPresentation(
            melodies: [beta, gamma],
            using: .manual(melodyID: gamma.id),
            continuingSameRest: true
        )

        #expect(melody?.id == beta.id)
        #expect(state.lastShownMelodyID == beta.id)

        let kept = state.beginPresentation(
            melodies: [beta, gamma],
            using: .manual(melodyID: gamma.id),
            continuingSameRest: true
        )
        #expect(kept?.id == beta.id)
    }

    @Test("a continuing rest that had no melody stays empty")
    func continuingEmptyRestStaysEmpty() {
        let state = MelodySelectionState(lastShownMelodyID: alpha.id, randomIndex: { _ in 0 })
        _ = state.beginPresentation(
            melodies: [],
            using: .randomNoRepeat,
            continuingSameRest: false
        )

        let melody = state.beginPresentation(
            melodies: [beta, gamma],
            using: .randomNoRepeat,
            continuingSameRest: true
        )

        #expect(melody == nil)
        #expect(state.lastShownMelodyID == alpha.id)
    }
}
