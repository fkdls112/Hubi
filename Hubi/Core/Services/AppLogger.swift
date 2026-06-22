import Foundation
import Observation

@MainActor
@Observable
final class AppLogger {
    static let shared = AppLogger()

    enum Level: String, Sendable {
        case debug, info, warning, error
    }

    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String
    }

    private(set) var recentLogs: [LogEntry] = []
    private let maxEntries = 1000
    nonisolated let logFile: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logFile = docs.appendingPathComponent("hubi.log")
    }

    nonisolated func debug(_ msg: String)   { log(.debug, msg) }
    nonisolated func info(_ msg: String)    { log(.info, msg) }
    nonisolated func warning(_ msg: String) { log(.warning, msg) }
    nonisolated func error(_ msg: String)   { log(.error, msg) }

    nonisolated private func log(_ level: Level, _ msg: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: msg)
        Task { @MainActor in
            self.recentLogs.append(entry)
            if self.recentLogs.count > self.maxEntries {
                self.recentLogs.removeFirst(self.recentLogs.count - self.maxEntries)
            }
        }
        persistAsync(entry)
        #if DEBUG
        print("[\(level.rawValue.uppercased())] \(msg)")
        #endif
    }

    nonisolated private func persistAsync(_ entry: LogEntry) {
        let line = "[\(entry.timestamp.ISO8601Format())] [\(entry.level.rawValue.uppercased())] \(entry.message)\n"
        let url = logFile
        DispatchQueue.global(qos: .background).async {
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
