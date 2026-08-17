import AppKit
import Combine

/// While the menu-bar `.menu` is open, updates the status `NSMenuItem` title
/// directly so the countdown keeps moving without SwiftUI rebuilding the
/// menu (which desyncs hover highlight).
@MainActor
final class MenuBarLiveStatusTitleUpdater {
    private let breakCycle: BreakCycle
    private var trackingObservers: [NSObjectProtocol] = []
    private var remainingCancellable: AnyCancellable?
    private weak var trackedMenu: NSMenu?

    init(breakCycle: BreakCycle) {
        self.breakCycle = breakCycle
    }

    func start() {
        guard trackingObservers.isEmpty else { return }

        let begin = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let menu = notification.object as? NSMenu
            Task { @MainActor [weak self] in
                self?.menuDidBeginTracking(menu)
            }
        }
        let end = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let menu = notification.object as? NSMenu
            Task { @MainActor [weak self] in
                self?.menuDidEndTracking(menu)
            }
        }
        trackingObservers = [begin, end]

        remainingCancellable = breakCycle.remaining.$seconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshTrackedStatusTitle()
            }
    }

    deinit {
        trackingObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func menuDidBeginTracking(_ menu: NSMenu?) {
        guard let menu, Self.isWeshomeBreakMenu(menu) else { return }
        trackedMenu = menu
        refreshTrackedStatusTitle()
    }

    private func menuDidEndTracking(_ menu: NSMenu?) {
        guard let menu, trackedMenu === menu else { return }
        trackedMenu = nil
    }

    private func refreshTrackedStatusTitle() {
        guard let menu = trackedMenu, !menu.items.isEmpty else { return }
        menu.items[0].title = breakCycle.statusLine
    }

    private static func isWeshomeBreakMenu(_ menu: NSMenu) -> Bool {
        let titles = menu.items.map(\.title)
        return titles.contains(MenuBarCopy.quit)
            && titles.contains(where: { $0.hasPrefix("设置") })
            && titles.contains(MenuBarCopy.startBreakNow)
    }
}
