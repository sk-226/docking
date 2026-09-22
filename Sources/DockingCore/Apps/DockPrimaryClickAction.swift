import AppKit

enum DockPrimaryClickAction: Equatable {
    case open
    case showInFinder
    case toggleApplication
    case openHidingOthers

    static func resolve(isApplication: Bool, modifiers: NSEvent.ModifierFlags) -> Self {
        if isApplication && modifiers.contains([.command, .option]) { return .openHidingOthers }
        if modifiers.contains(.command) { return .showInFinder }
        if isApplication && modifiers.contains(.option) { return .toggleApplication }
        return .open
    }
}
