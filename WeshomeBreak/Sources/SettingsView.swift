import GrillBreakCore
import SwiftUI
import UniformTypeIdentifiers

/// Ticket 07's settings panel: work/rest durations, skip/delay permissions
/// (plus delay length), scene mode selection strategy, and Melody Library
/// import / manage / manual selection. Every control binds to a store that
/// persists immediately — there's nothing to "save", edits apply as made.
struct SettingsView: View {
    /// Shared with `WeshomeBreakApp`'s Melody Preview `Window` scene id.
    static let melodyPreviewWindowID = "melody-preview"

    @ObservedObject var settingsStore: BreakSettingsStore
    @ObservedObject var melodyLibraryStore: MelodyLibraryStore
    let availableSceneModes: [BreakSceneMode]

    @Environment(\.openWindow) private var openWindow

    @State private var isImporting = false
    @State private var editingTitles: [UUID: String] = [:]
    @FocusState private var focusedMelodyID: UUID?

    private static let durationRange: ClosedRange<Double> = 1...120
    private static let delayRange: ClosedRange<Double> = 1...60
    private static let staffNotationScaleRange = BreakSettingsStore.staffNotationScaleRange
    private static let durationProportionPercentRange = BreakSettingsStore.durationProportionPercentRange
    private static let musicXMLTypes: [UTType] = [
        UTType(filenameExtension: "musicxml"),
        UTType(filenameExtension: "mxl")
    ].compactMap { $0 }

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

            Section("旋律库") {
                Button("导入 MusicXML…") {
                    isImporting = true
                }

                staffNotationScaleRow
                durationProportionRow

                if let statusMessage = melodyLibraryStore.feedback.message {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(melodyLibraryStore.feedback.isError ? .red : .secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if melodyLibraryStore.melodies.isEmpty {
                    Text("还没有旋律。可用 Audiveris / MuseScore 导出 .musicxml 或 .mxl 后导入。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(melodyLibraryStore.melodies) { melody in
                        melodyRow(melody)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: Self.musicXMLTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .background {
            ResignTitleEditingOnOutsideClick(isEditing: focusedMelodyID != nil) {
                focusedMelodyID = nil
            }
        }
        .onChange(of: focusedMelodyID) { oldValue, newValue in
            guard let oldValue, oldValue != newValue else { return }
            commitTitle(id: oldValue)
        }
        .onDisappear {
            if let focusedMelodyID {
                commitTitle(id: focusedMelodyID)
            }
        }
    }

    private func melodyRow(_ melody: UserMelody) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                melodyLibraryStore.select(id: melody.id)
            } label: {
                Image(systemName: melodyLibraryStore.selectedMelodyID == melody.id
                      ? "checkmark.circle.fill"
                      : "circle")
            }
            .buttonStyle(.plain)
            .help("设为当前旋律")

            VStack(alignment: .leading, spacing: 2) {
                TextField("名称", text: titleBinding(for: melody))
                    .textFieldStyle(.plain)
                    .focused($focusedMelodyID, equals: melody.id)
                    .onSubmit { commitTitle(id: melody.id) }
                    .accessibilityLabel("旋律名称")
                Text("\(melody.measureCount) 小节")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if melodyLibraryStore.selectedMelodyID == melody.id {
                Text("当前")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                melodyLibraryStore.delete(id: melody.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除旋律")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            // User cancelled the open panel — don't treat as a failure banner.
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                return
            }
            melodyLibraryStore.reportFailure("无法打开文件：\(error.localizedDescription)")
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            melodyLibraryStore.importFile(at: url)
        }
    }

    private func titleBinding(for melody: UserMelody) -> Binding<String> {
        Binding(
            get: { editingTitles[melody.id] ?? melody.title },
            set: { editingTitles[melody.id] = $0 }
        )
    }

    private func commitTitle(id: UUID) {
        guard let melody = melodyLibraryStore.melodies.first(where: { $0.id == id }) else {
            editingTitles[id] = nil
            return
        }
        let draft = editingTitles[id] ?? melody.title
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) == melody.title {
            editingTitles[id] = nil
            return
        }
        melodyLibraryStore.rename(id: id, to: draft)
        editingTitles[id] = nil
    }

    /// Staff Notation Scale: applies to both the Staff Melody Scene (next
    /// break onward) and the Melody Preview window (live).
    private var staffNotationScaleRow: some View {
        HStack {
            Stepper(
                value: $settingsStore.staffNotationScalePercent,
                in: Self.staffNotationScaleRange,
                step: 5
            ) {
                HStack {
                    Text("谱面大小")
                    Spacer()
                    Text("\(settingsStore.staffNotationScalePercent)%")
                        .foregroundStyle(.secondary)
                }
            }

            Button("预览") {
                openWindow(id: Self.melodyPreviewWindowID)
            }
            .disabled(melodyLibraryStore.selectedMelodyID == nil)
            .help(
                melodyLibraryStore.selectedMelodyID == nil
                    ? "先选中一首旋律才能预览"
                    : "在独立窗口预览当前旋律的谱面"
            )
        }
    }

    /// Duration Proportion: applies to both the Staff Melody Scene (next
    /// break onward) and the Melody Preview window (live).
    private var durationProportionRow: some View {
        Stepper(
            value: $settingsStore.durationProportionPercent,
            in: Self.durationProportionPercentRange,
            step: 5
        ) {
            HStack {
                Text("时值比例")
                Spacer()
                Text("\(settingsStore.durationProportionPercent)%")
                    .foregroundStyle(.secondary)
            }
        }
        .help("越接近 100% 越按时值拉开；越低则短时值音符挤得更紧。")
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
