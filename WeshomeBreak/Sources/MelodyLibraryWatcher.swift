import Foundation

/// Polls the Melody Library so another Mac's iCloud Drive edits show up
/// while this app is open. iCloud delivery is slower than this interval.
final class MelodyLibraryDirectoryWatcher {
    private let onChange: @MainActor () -> Void
    private var timer: DispatchSourceTimer?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [onChange] in
            Task { @MainActor in
                onChange()
            }
        }
        timer.resume()
        self.timer = timer
    }
}
