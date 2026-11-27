import AppKit
import Carbon.HIToolbox

/// Pastes text at the cursor of the frontmost app and optionally presses Return.
enum Paster {
    /// Returns true if Return (or the chosen send key) was pressed.
    @MainActor
    static func paste(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = Settings.restoreClipboard ? pasteboard.string(forType: .string) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postKey(UInt16(kVK_ANSI_V), flags: .maskCommand)

        var sent = false
        if Settings.autoEnter {
            // Give the target app a moment to insert the text before sending.
            try? await Task.sleep(for: .milliseconds(150))
            switch Settings.enterKey {
            case .enter: postKey(UInt16(kVK_Return), flags: [])
            case .shiftEnter: postKey(UInt16(kVK_Return), flags: .maskShift)
            case .commandEnter: postKey(UInt16(kVK_Return), flags: .maskCommand)
            }
            sent = true
        }

        if let saved {
            try? await Task.sleep(for: .milliseconds(600))
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
        return sent
    }

    private static func postKey(_ key: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Fixes developer terms that speech models often mishear.
enum TextCleanup {
    private static let replacements: [(pattern: String, replacement: String)] = [
        ("cloud code|clod code|clawed code", "Claude Code"),
        ("t three code|tea three code", "T3 Code"),
        ("get hub|git hub", "GitHub"),
        ("type script", "TypeScript"),
        ("java script", "JavaScript"),
        ("next js|next dot js", "Next.js"),
        ("node js|node dot js", "Node.js"),
        ("pie torch|py torch", "PyTorch"),
        ("post gress|post gres", "PostgreSQL"),
        ("tail wind", "Tailwind"),
        ("open a i", "OpenAI"),
        ("v s code", "VS Code"),
        ("x code", "Xcode"),
        ("swift u i", "SwiftUI"),
    ]

    private static let compiled: [(NSRegularExpression, String)] = replacements.compactMap { item in
        guard let regex = try? NSRegularExpression(pattern: "\\b(?:\(item.pattern))\\b", options: .caseInsensitive)
        else { return nil }
        return (regex, item.replacement)
    }

    static func apply(_ text: String) -> String {
        var result = text
        for (regex, replacement) in compiled {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        }
        return result
    }
}
