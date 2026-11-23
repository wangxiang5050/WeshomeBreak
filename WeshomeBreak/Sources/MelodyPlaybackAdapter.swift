import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import GrillBreakCore

/// Plays one Melody Playback sequence on the bundled piano. One instance for
/// the whole rest, owned by the overlay manager so each screen does not sound
/// its own copy. The sequencer is the clock; the line does not trigger notes.
final class PianoOutput {
    /// 系统通用 MIDI 音色库。打包的钢琴加载失败时才用 Program 0。
    static let systemPianoBank = URL(
        fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"
    )
    /// AUSampler 认的是 melodic bank，不是 SF2 文件头里的 bank 0。
    static let bundledBankMSB = UInt8(kAUSampler_DefaultMelodicBankMSB)
    static let bundledBankLSB = UInt8(kAUSampler_DefaultBankLSB)

    var instrumentNeedsLoad: Bool {
        gate.lock()
        defer { gate.unlock() }
        return !instrumentLoaded
    }

    static func loadInstrument(
        _ sampler: AVAudioUnitSampler,
        url: URL,
        bankMSB: UInt8,
        bankLSB: UInt8
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,
                bankMSB: bankMSB,
                bankLSB: bankLSB
            )
            return true
        } catch {
            return false
        }
    }
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var sequencer: AVAudioSequencer?
    private var started = false
    private var bankReady = false
    private var instrumentLoaded = false
    private var running = false
    private var sample = 0.0
    private var sampleAt = 0.0
    private var haveSample = false
    private var attached = false
    private var epoch = 0
    /// Held for the whole bank load so the main thread can keep taking clicks.
    private let gate = NSLock()
    private let stashLock = NSLock()
    private var stashed: MelodyPlaybackMoment?

    func prepare(completion: @escaping (Bool) -> Void) {
        if bankReady {
            completion(true)
            return
        }
        let epoch = self.epoch
        DispatchQueue.global(qos: .userInitiated).async {
            self.gate.lock()
            let ready = self.epoch == epoch && self.startIfNeeded()
            self.stashLock.lock()
            let stashed = self.stashed
            self.stashed = nil
            self.stashLock.unlock()
            if let stashed, self.epoch == epoch {
                self.apply(stashed)
            }
            self.gate.unlock()
            DispatchQueue.main.async {
                guard self.epoch == epoch else { return }
                self.bankReady = ready
                completion(ready)
            }
        }
    }

    func render(_ moment: MelodyPlaybackMoment) {
        if gate.try() {
            apply(moment)
            gate.unlock()
            return
        }
        stashLock.lock()
        stashed = moment
        stashLock.unlock()
    }

    private func apply(_ moment: MelodyPlaybackMoment) {
        if moment.silenced {
            silence()
        }
        if let sequence = moment.sequence {
            install(sequence)
        }
        if moment.phase != .playing {
            running = false
        }
    }

    func musicalSeconds(now: TimeInterval) -> TimeInterval? {
        guard gate.try() else { return nil }
        defer { gate.unlock() }
        guard running, let sequencer else { return nil }
        let raw = sequencer.currentPositionInSeconds
        if !haveSample || raw + 0.000_001 < sample {
            sample = raw
            sampleAt = now
            haveSample = true
        } else if raw > sample + 0.000_001 {
            sample = raw
            sampleAt = now
        }
        return PlayheadTiming.heardSeconds(
            sampled: sample,
            sampledAt: sampleAt,
            now: now,
            latency: engine.outputNode.presentationLatency,
            maximumLead: 1.0 / 30
        )
    }

    func stop() {
        gate.lock()
        epoch += 1
        silence()
        sequencer = nil
        if started {
            engine.stop()
            started = false
        }
        instrumentLoaded = false
        gate.unlock()
        bankReady = false
    }

    private func install(_ sequence: PlaybackSequence) {
        guard startIfNeeded(), let sequencer else { return }
        sequencer.stop()
        let tail = engine.outputNode.presentationLatency + 0.05
        guard let data = Self.midiData(sequence: sequence, tail: tail) else { return }
        do {
            try sequencer.load(from: data, options: [])
            sequencer.prepareToPlay()
            try sequencer.start()
            running = true
            haveSample = false
        } catch {
            running = false
        }
    }

    private func silence() {
        sequencer?.stop()
        running = false
        haveSample = false
        guard started else { return }
        for midi in 0..<128 {
            sampler.stopNote(UInt8(midi), onChannel: 0)
        }
    }

    private func startIfNeeded() -> Bool {
        if started { return true }
        if !attached {
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            attached = true
        }
        do {
            if !engine.isRunning {
                try engine.start()
            }
            if sequencer == nil {
                sequencer = AVAudioSequencer(audioEngine: engine)
            }
            if !instrumentLoaded {
                instrumentLoaded = loadBundledPiano() || Self.loadInstrument(
                    sampler,
                    url: Self.systemPianoBank,
                    bankMSB: Self.bundledBankMSB,
                    bankLSB: Self.bundledBankLSB
                )
            }
            guard instrumentLoaded else { return false }
            started = true
            return true
        } catch {
            engine.stop()
            started = false
            sequencer = nil
            return false
        }
    }

    private func loadBundledPiano() -> Bool {
        guard let url = Bundle.main.url(forResource: "UprightPianoKW", withExtension: "sf2") else {
            return false
        }
        return Self.loadInstrument(
            sampler,
            url: url,
            bankMSB: Self.bundledBankMSB,
            bankLSB: Self.bundledBankLSB
        )
    }

    /// Tempo is 60 so one beat is one second. The track runs slightly past the
    /// score so a note-off at the boundary is still delivered.
    private static func midiData(sequence: PlaybackSequence, tail: TimeInterval) -> Data? {
        var music: MusicSequence?
        guard NewMusicSequence(&music) == noErr, let music else { return nil }
        defer { DisposeMusicSequence(music) }

        var tempoTrack: MusicTrack?
        guard MusicSequenceGetTempoTrack(music, &tempoTrack) == noErr, let tempoTrack else { return nil }
        guard MusicTrackNewExtendedTempoEvent(tempoTrack, 0, 60) == noErr else { return nil }

        var track: MusicTrack?
        guard MusicSequenceNewTrack(music, &track) == noErr, let track else { return nil }
        for note in sequence.notes {
            var message = MIDINoteMessage(
                channel: 0,
                note: UInt8(clamping: note.midi),
                velocity: UInt8(clamping: min(127, max(1, note.velocity))),
                releaseVelocity: 0,
                duration: Float32(max(0.01, note.soundingSeconds))
            )
            guard MusicTrackNewMIDINoteEvent(track, MusicTimeStamp(max(0, note.startSeconds)), &message) == noErr else {
                return nil
            }
        }

        var length = MusicTimeStamp(max(0, sequence.seconds) + max(0, tail))
        let size = UInt32(MemoryLayout<MusicTimeStamp>.size)
        MusicTrackSetProperty(track, kSequenceTrackProperty_TrackLength, &length, size)
        MusicTrackSetProperty(tempoTrack, kSequenceTrackProperty_TrackLength, &length, size)

        var data: Unmanaged<CFData>?
        guard MusicSequenceFileCreateData(music, .midiType, .eraseFile, 480, &data) == noErr,
              let data
        else { return nil }
        return data.takeRetainedValue() as Data
    }
}

/// Reads the system default output and calls it headphones only for a
/// personal listening device: built-in headphone jack, or a Bluetooth device
/// whose name is not a loudspeaker.
enum PlaybackOutputSense {
    static func current() -> PlaybackOutput {
        let device = defaultOutputDevice()
        guard device != 0 else { return .speakers }
        let source = fourCC(property(.dataSource, device: device))
        if source == "hdpn" { return .headphones }
        let transport = fourCC(property(.transport, device: device))
        if transport == "airp" { return .speakers }
        let name = (deviceName(device) + " " + deviceUID(device)).lowercased()
        if name.contains("headphone") || name.contains("headset")
            || name.contains("airpod") || name.contains("earpod")
            || name.contains("耳机") || name.contains("耳塞") {
            return .headphones
        }
        if transport == "blue" || transport == "blea" || transport == "ble " {
            if name.contains("speaker") || name.contains("homepod")
                || name.contains("soundbar") || name.contains("音箱") {
                return .speakers
            }
            return .headphones
        }
        return .speakers
    }

    private enum Property {
        case dataSource
        case transport
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        return status == noErr ? device : 0
    }

    private static func property(_ property: Property, device: AudioDeviceID) -> UInt32 {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let selector: AudioObjectPropertySelector
        let scope: AudioObjectPropertyScope
        switch property {
        case .dataSource:
            selector = kAudioDevicePropertyDataSource
            scope = kAudioObjectPropertyScopeOutput
        case .transport:
            selector = kAudioDevicePropertyTransportType
            scope = kAudioObjectPropertyScopeGlobal
        }
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : 0
    }

    private static func deviceName(_ device: AudioDeviceID) -> String {
        stringProperty(kAudioDevicePropertyDeviceNameCFString, device: device)
    }

    private static func deviceUID(_ device: AudioDeviceID) -> String {
        stringProperty(kAudioDevicePropertyDeviceUID, device: device)
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        device: AudioDeviceID
    ) -> String {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr else { return "" }
        return name as String
    }

    private static func fourCC(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? ""
    }
}
