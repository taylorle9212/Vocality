import Foundation

/// Keys for user preferences. Views bind to them with @AppStorage.
enum SettingsKey {
    static let autoEnter = "autoEnter"
    static let enterKey = "enterKey"
    static let showSentBadge = "showSentBadge"
    static let playSounds = "playSounds"
    static let trailingSpace = "trailingSpace"
    static let restoreClipboard = "restoreClipboard"
    static let history = "history"
}

enum EnterKey: String, CaseIterable, Identifiable {
    case enter, shiftEnter, commandEnter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .enter: return "⏎ Return"
        case .shiftEnter: return "⇧⏎"
        case .commandEnter: return "⌘⏎"
        }
    }

    var glyph: String {
        switch self {
        case .enter: return "⏎"
        case .shiftEnter: return "⇧⏎"
        case .commandEnter: return "⌘⏎"
        }
    }
}

enum Settings {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.autoEnter: true,
            SettingsKey.enterKey: EnterKey.enter.rawValue,
            SettingsKey.showSentBadge: true,
            SettingsKey.playSounds: true,
            SettingsKey.trailingSpace: false,
            SettingsKey.restoreClipboard: true,
        ])
    }

    static var autoEnter: Bool { UserDefaults.standard.bool(forKey: SettingsKey.autoEnter) }
    static var enterKey: EnterKey {
        EnterKey(rawValue: UserDefaults.standard.string(forKey: SettingsKey.enterKey) ?? "") ?? .enter
    }
    static var showSentBadge: Bool { UserDefaults.standard.bool(forKey: SettingsKey.showSentBadge) }
    static var playSounds: Bool { UserDefaults.standard.bool(forKey: SettingsKey.playSounds) }
    static var trailingSpace: Bool { UserDefaults.standard.bool(forKey: SettingsKey.trailingSpace) }
    static var restoreClipboard: Bool { UserDefaults.standard.bool(forKey: SettingsKey.restoreClipboard) }
}
