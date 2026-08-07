import GrillBreakCore
import SwiftUI

/// Ticket 07's settings panel: work/rest durations, skip/delay permissions
/// (plus delay length), and the scene mode selection strategy. Every control
/// binds directly to `BreakSettingsStore`, which persists to `UserDefaults`
/// and pushes changes live to the running scheduler/overlay — there's
/// nothing to "save", edits apply as they're made.
struct SettingsView: View {
    @ObservedObject var settingsStore: BreakSettingsStore
    let availableSceneModes: [BreakSceneMode]

    private static let durationRange: ClosedRange<Double> = 1...120
    private static let delayRange: ClosedRange<Double> = 1...60

    var body: some View {
        Form {
            Section("时长") {
                durationRow(
                    title: "工作时长",
                    minutes: minutesBinding(for: \.workDuration),
                    range: Self.durationRange
                )
                durationRow(
                    title: "休息时长",
                    minutes: minutesBinding(for: \.breakDuration),
                    range: Self.durationRange
                )
            }

            Section("跳过 / 延迟") {
                Toggle("允许跳过休息", isOn: $settingsStore.allowSkip)
                Toggle("允许延迟休息", isOn: $settingsStore.allowDelay)
                durationRow(
                    title: "延迟时长",
                    minutes: minutesBinding(for: \.delayInterval),
                    range: Self.delayRange
                )
                .disabled(!settingsStore.allowDelay)
            }

            Section("展示模式") {
                Picker("选择策略", selection: $settingsStore.sceneModeSelectionRaw) {
                    Text("随机轮换").tag(BreakSettingsStore.randomSelectionValue)
                    ForEach(availableSceneModes, id: \.identifier) { mode in
                        Text(mode.displayName).tag(mode.identifier)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func durationRow(title: String, minutes: Binding<Double>, range: ClosedRange<Double>) -> some View {
        Stepper(value: minutes, in: range, step: 1) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(minutes.wrappedValue)) 分钟")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Bridges a `TimeInterval` (seconds) setting to a whole-minutes `Double`
    /// for the stepper controls.
    private func minutesBinding(for keyPath: ReferenceWritableKeyPath<BreakSettingsStore, TimeInterval>) -> Binding<Double> {
        Binding(
            get: { settingsStore[keyPath: keyPath] / 60 },
            set: { settingsStore[keyPath: keyPath] = $0 * 60 }
        )
    }
}
