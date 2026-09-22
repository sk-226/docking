import AppKit
import Darwin

@MainActor
final class DockWindowEventRegion {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias NewRegion = @convention(c) (UnsafePointer<CGRect>, UnsafeMutablePointer<OpaquePointer?>) -> Int32
    private typealias ReleaseRegion = @convention(c) (OpaquePointer) -> Void
    private typealias SetEventShape = @convention(c) (Int32, UInt32, OpaquePointer) -> Int32
    private let framework: UnsafeMutableRawPointer
    private let mainConnection: MainConnection
    private let newRegion: NewRegion
    private let releaseRegion: ReleaseRegion
    private let setEventShape: SetEventShape
    private var lastWindowNumber: Int?
    private var lastRegion: CGRect?
    private var lastWindowSize: CGSize?
    private var lastError: Int32?

    init?() {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let connection = dlsym(framework, "CGSMainConnectionID"),
              let create = dlsym(framework, "CGSNewRegionWithRect"),
              let release = dlsym(framework, "CGSReleaseRegion"),
              let set = dlsym(framework, "CGSSetWindowEventShape") else {
            dlclose(framework)
            return nil
        }
        self.framework = framework
        // Dock-2427.6: 0x1000e5464 は CGRect と出力ポインター，0x10032ae88 は connection・window・region を渡す．
        mainConnection = unsafeBitCast(connection, to: MainConnection.self)
        newRegion = unsafeBitCast(create, to: NewRegion.self)
        releaseRegion = unsafeBitCast(release, to: ReleaseRegion.self)
        setEventShape = unsafeBitCast(set, to: SetEventShape.self)
    }

    deinit { dlclose(framework) }

    func update(window: NSWindow, contentFrame: CGRect) -> Bool {
        guard window.windowNumber > 0 else { return false }
        var rect = Self.region(contentFrame: contentFrame, windowFrame: window.frame)
        if lastWindowNumber == window.windowNumber && lastRegion == rect && lastWindowSize == window.frame.size { return true }
        var region: OpaquePointer?
        let creation = newRegion(&rect, &region)
        guard creation == 0, let region else {
            report(creation)
            return false
        }
        defer { releaseRegion(region) }
        let status = setEventShape(mainConnection(), UInt32(window.windowNumber), region)
        guard status == 0 else {
            report(status)
            return false
        }
        lastWindowNumber = window.windowNumber
        lastWindowSize = window.frame.size
        lastRegion = rect
        lastError = nil
        return true
    }

    nonisolated static func region(contentFrame: CGRect, windowFrame: CGRect) -> CGRect {
        let clipped = contentFrame.intersection(windowFrame)
        guard !clipped.isNull else { return .zero }
        return CGRect(x: clipped.minX - windowFrame.minX, y: windowFrame.maxY - clipped.maxY,
                      width: clipped.width, height: clipped.height)
    }

    private func report(_ status: Int32) {
        guard lastError != status else { return }
        lastError = status
        DockingLog.dock.error("Dock input-region update failed with status \(status).")
    }
}
