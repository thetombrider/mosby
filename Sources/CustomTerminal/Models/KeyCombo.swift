import AppKit

struct KeyCombo: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt     // NSEvent.ModifierFlags rawValue (device-independent mask only)
    let display: String     // e.g. "⌘⇧T" — human readable

    func matches(_ event: NSEvent) -> Bool {
        let m = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        return event.keyCode == keyCode && m == modifiers
    }
}
