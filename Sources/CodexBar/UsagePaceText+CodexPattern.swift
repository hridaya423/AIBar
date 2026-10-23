import CodexBarCore
import Foundation

extension UsagePaceText {
    private struct CodexPatternBox {
        var builtFrom = Date.distantPast
        var model: CodexUsagePatternModel?
    }

    private static let codexPatternLock = NSLock()
    private nonisolated(unsafe) static var codexPatternBox = CodexPatternBox()

    static var codexPattern: CodexUsagePatternModel? {
        self.codexPatternLock.lock()
        defer { self.codexPatternLock.unlock() }
        return self.codexPatternBox.model
    }

    static func updateCodexPattern(_ model: CodexUsagePatternModel?, builtFrom: Date) {
        self.codexPatternLock.lock()
        defer { self.codexPatternLock.unlock() }
        guard builtFrom >= self.codexPatternBox.builtFrom else { return }
        self.codexPatternBox = CodexPatternBox(builtFrom: builtFrom, model: model)
    }

    static func resetCodexPattern() {
        self.codexPatternLock.lock()
        defer { self.codexPatternLock.unlock() }
        self.codexPatternBox = CodexPatternBox()
    }

    static func codexPatternPace(provider: UsageProvider, window: RateWindow, now: Date) -> UsagePace? {
        // Provider-specific by design: only Codex has a learned weekday x hour usage pattern.
        guard provider == .codex else { return nil }
        return self.codexPattern?.usagePace(window: window, now: now)
    }
}
