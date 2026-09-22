import Foundation

enum DockLaunchTarget {
    static func itemID(for application: RunningApplicationSnapshot, candidates: [DockItem]) -> UUID? {
        if let exact = candidates.first(where: { $0.runningProcessIdentifier == application.processIdentifier }) {
            return exact.id
        }
        return candidates.first {
            $0.isApplication && $0.runningProcessIdentifier == nil
                && (($0.bundleIdentifier != nil && $0.bundleIdentifier == application.bundleIdentifier)
                    || ($0.url != nil && $0.url == application.bundleURL))
        }?.id
    }
}
