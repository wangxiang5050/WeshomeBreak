import AVFoundation
import Foundation
import Testing
@testable import WeshomeBreak

@Suite("PianoOutput")
struct PianoOutputTests {
    @Test
    func systemPianoBankIsTheInstalledGMSoundFont() {
        #expect(FileManager.default.fileExists(atPath: PianoOutput.systemPianoBank.path))
    }

    @Test
    func stoppingARestLoadsThePianoAgain() async {
        let piano = PianoOutput()
        let ready = await withCheckedContinuation { continuation in
            piano.prepare { continuation.resume(returning: $0) }
        }
        #expect(ready)
        #expect(!piano.instrumentNeedsLoad)
        piano.stop()
        #expect(piano.instrumentNeedsLoad)
        let again = await withCheckedContinuation { continuation in
            piano.prepare { continuation.resume(returning: $0) }
        }
        #expect(again)
        #expect(!piano.instrumentNeedsLoad)
    }

    @Test
    func bundledPianoKeepsItsVoiceAfterTheEngineStops() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/UprightPianoKW.sf2")
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        let grab = SampleGrab()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()
        _ = AVAudioSequencer(audioEngine: engine)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            grab.add(buffer)
        }
        #expect(PianoOutput.loadInstrument(
            sampler,
            url: url,
            bankMSB: PianoOutput.bundledBankMSB,
            bankLSB: PianoOutput.bundledBankLSB
        ))
        let first = voice(sampler, grab)
        engine.stop()
        try engine.start()
        #expect(PianoOutput.loadInstrument(
            sampler,
            url: url,
            bankMSB: PianoOutput.bundledBankMSB,
            bankLSB: PianoOutput.bundledBankLSB
        ))
        let second = voice(sampler, grab)
        engine.stop()
        #expect(first > 0.04)
        #expect(abs(second - first) / first < 0.35)
    }

    private func voice(_ sampler: AVAudioUnitSampler, _ grab: SampleGrab) -> Double {
        _ = grab.take()
        sampler.startNote(60, withVelocity: 90, onChannel: 0)
        Thread.sleep(forTimeInterval: 0.35)
        sampler.stopNote(60, onChannel: 0)
        Thread.sleep(forTimeInterval: 0.05)
        let samples = grab.take()
        var sum = 0.0
        for sample in samples {
            sum += Double(sample) * Double(sample)
        }
        return samples.isEmpty ? 0 : (sum / Double(samples.count)).squareRoot()
    }
}

private final class SampleGrab: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func add(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        lock.unlock()
    }

    func take() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let copy = samples
        samples.removeAll(keepingCapacity: true)
        return copy
    }
}
