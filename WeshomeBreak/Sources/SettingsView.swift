import AppKit
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
    @ObservedObject var loginLaunch: LoginLaunchController
    let availableSceneModes: [BreakSceneMode]

    @Environment(\.openWindow) private var openWindow

    @State private var isImporting = false
    @State private var editingTitles: [UUID: String] = [:]
    @State private var titleBaselines: [UUID: String] = [:]
    @FocusState private var focusedMelodyID: UUID?
    /// Form height at its natural size. Zero until the first layout.
    @State private var naturalContentHeight: CGFloat = 0
    /// Chosen once: the saved frame, or the natural size on the first open.
    /// Later content growth does not change it, so the remembered frame stays put.
    @State private var lockedContentSize: CGSize?

    private static let durationRange: ClosedRange<Double> = 1...120
    private static let delayRange: ClosedRange<Double> = 1...60
    private static let staffNotationScaleRange = BreakSettingsStore.staffNotationScaleRange
    private static let durationProportionPercentRange = BreakSettingsStore.durationProportionPercentRange
    private static let musicXMLTypes: [UTType] = [
        UTType(filenameExtension: "musicxml"),
        UTType(filenameExtension: "mxl")
    ].compactMap { $0 }

    var body: some View {
        ScrollView(.vertical) {
            settingsForm
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: NaturalContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .defaultScrollAnchor(.top)
        .frame(
            minWidth: SettingsWindowMetrics.minWidth,
            idealWidth: lockedContentSize?.width ?? SettingsWindowMetrics.minWidth,
            maxWidth: .infinity,
            minHeight: SettingsWindowMetrics.minHeight,
            idealHeight: lockedContentSize?.height ?? SettingsWindowMetrics.minHeight,
            maxHeight: .infinity,
            alignment: .top
        )
        .onPreferenceChange(NaturalContentHeightKey.self) { height in
            guard lockedContentSize == nil,
                  height > 1,
                  abs(height - naturalContentHeight) > 0.5 else {
                return
            }
            naturalContentHeight = height
        }
        .background {
            SettingsWindowFrameMemory(naturalContentHeight: naturalContentHeight) { size in
                if lockedContentSize == nil {
                    lockedContentSize = size
                }
            }
        }
    }

    private var settingsForm: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动", isOn: $settingsStore.launchAtLogin)
                    .onChange(of: settingsStore.launchAtLogin) { _, enabled in
                        loginLaunch.apply(enabled: enabled)
                    }
                    .help("登录本机后自动打开 Weshome Break")
                if loginLaunch.needsApproval {
                    Text("macOS 需要你在「系统设置 → 通用 → 登录项」中允许 Weshome Break。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开登录项设置") {
                        loginLaunch.openSystemSettings()
                    }
                }
                if let failureMessage = loginLaunch.failureMessage {
                    Text(failureMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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
                Text(melodyLibraryStore.residenceSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("导入 MusicXML…") {
                    isImporting = true
                }

                Toggle("随机旋律", isOn: $settingsStore.randomMelodyEnabled)
                if let randomMelodyNote {
                    Text(randomMelodyNote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            if let oldValue, oldValue != newValue {
                commitTitle(id: oldValue)
            }
            if let newValue {
                beginTitleEdit(id: newValue)
            }
        }
        .onDisappear {
            if let focusedMelodyID {
                commitTitle(id: focusedMelodyID)
            }
        }
    }

    /// Shown only while 「随机旋律」 is on. The switch stays editable when
    /// Scene Mode Selection is not fixed to Staff Melody; the note says the
    /// rest still uses the manual current melody until it is.
    private var randomMelodyNote: String? {
        guard settingsStore.randomMelodyEnabled else { return nil }
        if settingsStore.sceneModeSelectionRaw == StaffMelodySceneSession.sceneModeIdentifier {
            return "此开关生效时，下次休息不按「当前」勾选，而从曲库随机抽取。"
        }
        return "仅当选择策略为「五线谱旋律」时，休息才会随机；现在仍用当前旋律。"
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
                TextField("", text: titleBinding(for: melody), prompt: Text("名称"))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .focused($focusedMelodyID, equals: melody.id)
                    .onSubmit { commitTitle(id: melody.id) }
                    .accessibilityLabel("旋律名称")
                Text("\(melody.measureCount) 小节")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(
                minWidth: SettingsWindowMetrics.titleColumnMinWidth,
                maxWidth: .infinity,
                alignment: .leading
            )

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
        .labelsHidden()
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

    private func beginTitleEdit(id: UUID) {
        guard editingTitles[id] == nil,
              let title = melodyLibraryStore.melodies.first(where: { $0.id == id })?.title else {
            return
        }
        editingTitles[id] = title
        titleBaselines[id] = title
    }

    private func commitTitle(id: UUID) {
        let draft = editingTitles[id]
        let baseline = titleBaselines[id]
        editingTitles[id] = nil
        titleBaselines[id] = nil
        guard let melody = melodyLibraryStore.melodies.first(where: { $0.id == id }) else {
            return
        }
        let text = draft ?? melody.title
        let original = baseline ?? text
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == original.trimmingCharacters(in: .whitespacesAndNewlines) {
            return
        }
        melodyLibraryStore.rename(id: id, to: text)
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

/// Content size of the Settings window. The minimum still fits one row of
/// controls and a slice of the form; there is no maximum other than the screen.
fileprivate enum SettingsWindowMetrics {
    static let minWidth: CGFloat = 420
    static let minHeight: CGFloat = 360
    static let titleColumnMinWidth: CGFloat = 128
    static let frameAutosaveName: NSWindow.FrameAutosaveName = "WeshomeBreak.Settings"

    static func hasSavedFrame(_ name: NSWindow.FrameAutosaveName) -> Bool {
        UserDefaults.standard.object(forKey: "NSWindow Frame \(name)") != nil
    }
}

private struct NaturalContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Restores the Settings window's frame, or sizes it to the form the first time.
/// AppKit stores the frame for this agent app; SwiftUI scene restoration does not.
private struct SettingsWindowFrameMemory: NSViewRepresentable {
    var naturalContentHeight: CGFloat
    var lockContentSize: (CGSize) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.naturalContentHeight = naturalContentHeight
        context.coordinator.lockContentSize = lockContentSize
        context.coordinator.schedule()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var hostView: NSView?
        var naturalContentHeight: CGFloat = 0
        var lockContentSize: (CGSize) -> Void = { _ in }
        private var didApply = false

        func schedule() {
            let hostView = hostView
            Task { @MainActor [weak self] in
                guard let self, let window = hostView?.window else { return }
                self.apply(to: window)
            }
        }

        private func apply(to window: NSWindow) {
            window.styleMask.insert(.resizable)
            guard !didApply else { return }

            let name = SettingsWindowMetrics.frameAutosaveName
            let hadSavedFrame = SettingsWindowMetrics.hasSavedFrame(name)
            let restored = window.setFrameUsingName(name, force: true)
            if !restored && (hadSavedFrame || naturalContentHeight <= 1) {
                return
            }
            didApply = true
            // Naming the frame also restores a saved one, so clamp or size afterwards.
            window.setFrameAutosaveName(name)

            let contentSize = restored
                ? clampedContentSize(of: window)
                : sizeToNaturalContent(of: window)
            if !restored {
                window.saveFrame(usingName: name)
            }

            let applied = window.frame
            Task { @MainActor [weak window] in
                self.lockContentSize(contentSize)
                guard let window, window.frame.size != applied.size else { return }
                window.setFrame(applied, display: true, animate: false)
            }
        }

        /// Grows a restored frame up to the minimum. Keeps the top edge put.
        private func clampedContentSize(of window: NSWindow) -> CGSize {
            let content = window.contentRect(forFrameRect: window.frame)
            let width = max(SettingsWindowMetrics.minWidth, content.width)
            let height = max(SettingsWindowMetrics.minHeight, content.height)
            guard width != content.width || height != content.height else {
                return CGSize(width: width, height: height)
            }
            place(contentSize: CGSize(width: width, height: height), on: window)
            return CGSize(width: width, height: height)
        }

        private func sizeToNaturalContent(of window: NSWindow) -> CGSize {
            let size = CGSize(
                width: SettingsWindowMetrics.minWidth,
                height: max(SettingsWindowMetrics.minHeight, naturalContentHeight)
            )
            place(contentSize: size, on: window)
            return size
        }

        private func place(contentSize: CGSize, on window: NSWindow) {
            let contentRect = NSRect(origin: .zero, size: contentSize)
            let target = window.frameRect(forContentRect: contentRect)
            var frame = window.frame
            frame.origin.y += frame.height - target.height
            frame.size = target.size
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
