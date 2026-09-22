import AppKit
import Darwin

@MainActor
final class AppExposeService {
    private typealias SendNotification = @convention(c) (CFString, Int32) -> Int32
    private let framework: UnsafeMutableRawPointer?
    private let sendNotification: SendNotification?

    init() {
        let framework = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/HIServices", RTLD_LAZY | RTLD_LOCAL)
        self.framework = framework
        if let framework, let symbol = dlsym(framework, "CoreDockSendNotification") {
            // Dock-2427.6 の受信側は第2引数を _LSASNCreateWithPid に渡す．戻り値は OSStatus．
            sendNotification = unsafeBitCast(symbol, to: SendNotification.self)
        } else {
            sendNotification = nil
        }
    }

    deinit {
        if let framework { dlclose(framework) }
    }

    func showWindows(of application: NSRunningApplication) {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !application.isTerminated else { return }
                guard let sendNotification = self.sendNotification else {
                    DockingLog.dock.error("App Exposé is unavailable: CoreDockSendNotification was not found.")
                    return
                }
                let result = sendNotification("com.apple.expose.front.awake" as CFString, application.processIdentifier)
                if result != 0 { DockingLog.dock.error("App Exposé failed with status \(result).") }
            }
        }
    }
}
