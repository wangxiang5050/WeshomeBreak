import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import GrillBreakCore

/// Plays Melody Playback attacks on the system piano. One instance per rest,
/// owned by the overlay manager so each screen does not sound its own copy.
final class PianoOutput {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var started = false
    private var noteOffs: [DispatchWorkItem] = []

    func render(_ moment: MelodyPlaybackMoment) {
        if moment.silenced {
            silence()
        }
        for attack in moment.attacks {
            guard startIfNeeded() else { return }
            let note = UInt8(clamping: attack.midi)
            let velocity = UInt8(clamping: min(127, max(1, attack.velocity)))
            sampler.stopNote(note, onChannel: 0)
            sampler.startNote(note, withVelocity: velocity, onChannel: 0)
            let off = DispatchWorkItem { [weak self] in
                self?.sampler.stopNote(note, onChannel: 0)
            }
            noteOffs.append(off)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + max(0, attack.soundingSeconds),
                execute: off
            )
        }
    }

    func stop() {
        silence()
        if started {
            engine.stop()
            started = false
        }
    }

    private func silence() {
        noteOffs.forEach { $0.cancel() }
        noteOffs.removeAll()
        guard started else { return }
        for midi in 0..<128 {
            sampler.stopNote(UInt8(midi), onChannel: 0)
        }
    }

    private func startIfNeeded() -> Bool {
        if started { return true }
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        do {
            try engine.start()
            let bank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
            try sampler.loadSoundBankInstrument(
                at: bank,
                program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            started = true
            return true
        } catch {
            engine.stop()
            return false
        }
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
