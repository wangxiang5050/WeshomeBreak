import Foundation
import Testing
@testable import WeshomeBreak

@Suite("PianoOutput")
struct PianoOutputTests {
    @Test
    func systemPianoBankIsTheInstalledGMSoundFont() {
        #expect(FileManager.default.fileExists(atPath: PianoOutput.systemPianoBank.path))
    }
}
