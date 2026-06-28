import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let message):
            return "Launch at login could not be updated. \(message)"
        }
    }
}

final class LaunchAtLoginService {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // We use ServiceManagement instead of writing login item plists or
            // scripting System Settings. It is stricter about app bundle shape
            // and signing, but that strictness is the point: login behavior
            // should stay inside macOS's consent and lifecycle model.
            throw LaunchAtLoginError.registrationFailed(error.localizedDescription)
        }
    }
}
