import Foundation
import os.log

// * -- Безпечне внутрішнє логування (без збереження на диск за замовчуванням) --
final class DiagnosticsLog: @unchecked Sendable {
    static let shared = DiagnosticsLog()

    private let logger = Logger(subsystem: "com.freepunto.FreePunto", category: "Diagnostics")
    private let customLogFile: URL? = {
        guard let path = ProcessInfo.processInfo.environment["FREEPUNTO_LOG_FILE"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }()

    private init() {}

    func log(_ message: String) {
        logger.debug("\(message, privacy: .private)")

        // Записуємо у файл ТІЛЬКИ якщо явно задано змінну FREEPUNTO_LOG_FILE
        if let fileURL = customLogFile {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let formatted = "\(timestamp) \(message)\n"
            if let data = formatted.data(using: .utf8) {
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    _ = try? data.write(to: fileURL, options: .atomic)
                } else if let handle = try? FileHandle(forWritingTo: fileURL) {
                    _ = try? handle.seekToEnd()
                    _ = try? handle.write(contentsOf: data)
                    _ = try? handle.close()
                }
            }
        }
    }
}

// * -- Загальний виклик для логування подій у системний журнал --
func rawLog(_ message: String) {
    DiagnosticsLog.shared.log(message)
}
