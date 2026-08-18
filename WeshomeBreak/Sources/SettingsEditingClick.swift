import AppKit
import SwiftUI

/// Policy for ending melody-title editing: a click keeps editing only when it
/// lands in a text field or its field editor. Form chrome, Spacer, and other
/// controls are not first responders, so SwiftUI will not resign focus on its own.
@MainActor
enum SettingsEditingClick {
    static func shouldResignTitleEditing(hitView: NSView?) -> Bool {
        var current = hitView
        while let view = current {
            if view is NSTextView || view is NSTextField {
                return false
            }
            current = view.superview
        }
        return true
    }
}

/// Watches mouse-downs in the hosting window and resigns title focus when the
/// click is outside a text input. Scoped to this view's window so overlay /
/// menu-bar clicks are ignored.
struct ResignTitleEditingOnOutsideClick: NSViewRepresentable {
    var isEditing: Bool
    var onResign: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.isEditing = isEditing
        context.coordinator.onResign = onResign
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.isEditing = isEditing
        context.coordinator.onResign = onResign
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var hostView: NSView?
        var isEditing = false
        var onResign: () -> Void = {}
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            remove()
        }

        private func handle(_ event: NSEvent) {
            let window = event.window
            let location = event.locationInWindow
            let hostWindow = hostView?.window
            let editing = isEditing
            Task { @MainActor [weak self] in
                guard let self,
                      editing,
                      window === hostWindow,
                      let contentView = window?.contentView else {
                    return
                }
                let hit = contentView.hitTest(location)
                guard SettingsEditingClick.shouldResignTitleEditing(hitView: hit) else {
                    return
                }
                window?.makeFirstResponder(nil)
                self.onResign()
            }
        }
    }
}
