import Foundation

public struct CodexUsagePatternSource: Sendable {
    private let codexSessionsRoot: URL
    private let openCodeReader: OpenCodeTokenCostReader
    private let lookbackDays: Int

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        lookbackDays: Int = 60,
        cacheRoot: URL? = nil)
    {
        self.codexSessionsRoot = homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        self.openCodeReader = OpenCodeTokenCostReader(homeDirectory: homeDirectory, cacheRoot: cacheRoot)
        self.lookbackDays = lookbackDays
    }

    public init(codexSessionsRoot: URL, openCodeReader: OpenCodeTokenCostReader, lookbackDays: Int = 60) {
        self.codexSessionsRoot = codexSessionsRoot
        self.openCodeReader = openCodeReader
        self.lookbackDays = lookbackDays
    }

    public func buildModel(now: Date = Date(), calendar: Calendar = .current) -> CodexUsagePatternModel {
        CodexUsagePatternModel.build(events: self.loadEvents(now: now), calendar: calendar)
    }

    func loadEvents(now: Date = Date()) -> [CodexUsagePatternModel.Event] {
        let since = now.addingTimeInterval(-Double(self.lookbackDays) * 86400)
        var events = self.openCodeReader
            .loadOpenAIUsageEvents(since: since, until: now)
            .map { CodexUsagePatternModel.Event(timestamp: $0.timestamp, weight: $0.weight) }
        events.append(contentsOf: self.codexSessionFileEvents(since: since))
        return events
    }

    private func codexSessionFileEvents(since: Date) -> [CodexUsagePatternModel.Event] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: self.codexSessionsRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles])
        else {
            return []
        }

        var events: [CodexUsagePatternModel.Event] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= since,
                  let size = values.fileSize
            else {
                continue
            }
            events.append(.init(timestamp: modified, weight: max(1, Double(size) / 1000)))
        }
        return events
    }
}
