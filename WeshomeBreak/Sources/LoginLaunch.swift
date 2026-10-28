import ServiceManagement

/// Registers or removes this app as a macOS login item.
///
/// `SMAppService.mainApp` is tied to the running bundle, so the copy that
/// is actually launched (the Xcode Debug app, or the copy in /Applications)
/// is the one that comes back at the next login.
enum LoginLaunch {
    enum Outcome: Equatable {
        case updated
        case needsApproval
    }

    static func apply(enabled: Bool) throws -> Outcome {
        let service = SMAppService.mainApp
        if enabled {
            switch service.status {
            case .enabled:
                return .updated
            case .requiresApproval:
                return .needsApproval
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
            return service.status == .requiresApproval ? .needsApproval : .updated
        }

        if service.status != .notRegistered {
            try service.unregister()
        }
        return .updated
    }
}

@MainActor
final class LoginLaunchController: ObservableObject {
    @Published private(set) var needsApproval = false
    @Published private(set) var failureMessage: String?

    func apply(enabled: Bool) {
        do {
            let outcome = try LoginLaunch.apply(enabled: enabled)
            failureMessage = nil
            needsApproval = outcome == .needsApproval
        } catch {
            needsApproval = false
            failureMessage = "无法设置登录时启动：\(error.localizedDescription)"
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
