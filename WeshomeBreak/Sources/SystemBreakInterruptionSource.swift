import AppKit
import CoreGraphics
import Foundation
import GrillBreakCore

/// The real, system-backed `BreakInterruptionSource` used by the running
/// app. `GrillBreakCore.BreakScheduler` never talks to these APIs directly —
/// it only depends on the `BreakInterruptionSource` protocol — so this is
/// the one place the ticket's two detection heuristics live.
struct SystemBreakInterruptionSource: BreakInterruptionSource {
    private let doNotDisturbAssertionsPath: String

    init(
        doNotDisturbAssertionsPath: String = "\(NSHomeDirectory())/Library/DoNotDisturb/DB/Assertions.json"
    ) {
        self.doNotDisturbAssertionsPath = doNotDisturbAssertionsPath
    }

    /// `true` while some on-screen window occupies an entire display at the
    /// normal window layer (`kCGWindowLayer == 0`) — the same heuristic
    /// many menu-bar utilities use to hide themselves while another app is
    /// full-screen (slideshow, video, meeting, etc.), since there is no
    /// public API that directly reports "some app is full-screen".
    func isFullScreenAppActive() -> Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            .optionOnScreenOnly,
            kCGNullWindowID
        ) as? [[String: AnyObject]] else {
            return false
        }

        let screenSizes = NSScreen.screens.map { $0.frame.size }
        guard !screenSizes.isEmpty else { return false }

        for windowInfo in windowInfoList {
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"]
            else {
                continue
            }

            let matchesAScreen = screenSizes.contains { screenSize in
                abs(screenSize.width - width) < 1 && abs(screenSize.height - height) < 1
            }
            if matchesAScreen {
                return true
            }
        }
        return false
    }

    /// `true` while macOS Focus/Do Not Disturb is enabled, inferred from the
    /// per-user assertions database macOS itself maintains at
    /// `~/Library/DoNotDisturb/DB/Assertions.json`. This file isn't public
    /// API and its shape isn't documented, so every step here is defensive:
    /// any read/parse failure is treated as "not active" rather than ever
    /// blocking a break because detection itself broke.
    func isDoNotDisturbActive() -> Bool {
        guard let data = FileManager.default.contents(atPath: doNotDisturbAssertionsPath) else {
            return false
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]]
        else {
            return false
        }

        for entry in entries {
            guard let records = entry["storeAssertionRecords"] as? [[String: Any]] else {
                continue
            }
            if !records.isEmpty {
                return true
            }
        }
        return false
    }
}
