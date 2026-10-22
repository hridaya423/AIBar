import AppKit
import Testing
@testable import CodexBar

@MainActor
struct SettingsWindowOpeningTests {
    @Test
    func `keepalive shell is configured`() {
        _ = NSApplication.shared

        let keepaliveShell = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        keepaliveShell.contentView = KeepaliveWindowConfiguratorView()

        #expect(keepaliveShell.identifier?.rawValue == "CodexBarLifecycleKeepalive")
        #expect(keepaliveShell.styleMask == [.borderless])
        #expect(keepaliveShell.alphaValue == 0)
        #expect(keepaliveShell.frame.size == NSSize(width: 1, height: 1))
    }

    @Test
    func `missing relay falls back to appkit`() {
        var appKitAttempted = false
        let opener = SettingsWindowOpener(
            notification: { false },
            appKit: {
                appKitAttempted = true
                return true
            })

        let outcome = opener.open(preferred: .notification)

        #expect(outcome == .fallback)
        #expect(appKitAttempted)
    }
}
