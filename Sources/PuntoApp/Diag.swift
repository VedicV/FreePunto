import Foundation
import os.log

// * -- Безпечне внутрішнє логування (без створення файлів на робочому столі) --
final class DiagnosticsLog: @unchecked Sendable {
    static let shared = DiagnosticsLog()

    private let lock = NSLock()
    private var buffer: [String] = []
    private let maxEntries = 120
    private let logger = Logger(subsystem: "com.freepunto.FreePunto", category: "Diagnostics")
    private let customLogFile: URL? = {
        if let path = ProcessInfo.processInfo.environment["FREEPUNTO_LOG_FILE"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/tmp/freepunto.log")
    }()

    private init() {}

    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formatted = "\(timestamp) \(message)"

        lock.lock()
        buffer.append(formatted)
        if buffer.count > maxEntries {
            buffer.removeFirst(buffer.count - maxEntries)
        }
        lock.unlock()

        logger.debug("\(message, privacy: .public)")

        // Записуємо у файл ТІЛЬКИ якщо явно задано змінну FREEPUNTO_LOG_FILE
        if let fileURL = customLogFile, let data = "\(formatted)\n".data(using: .utf8) {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try? data.write(to: fileURL, options: .atomic)
            } else if let handle = try? FileHandle(forWritingTo: fileURL) {
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
                _ = try? handle.close()
            }
        }
    }

    func recentLogs() -> String {
        lock.lock()
        defer { lock.unlock() }
        return buffer.joined(separator: "\n")
    }
}

// * -- Загальний виклик для логування подій у системний журнал та буфер діагностики --
func rawLog(_ message: String) {
    DiagnosticsLog.shared.log(message)
}
