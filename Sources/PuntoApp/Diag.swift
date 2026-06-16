import Foundation

// * -- Сирий файловий лог для налагодження в release-білді --
func rawLog(_ message: String) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let logURL = home.appendingPathComponent("Desktop/freepunto.log")
    let line = "\(Date()) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }

    // Створюємо файл якщо немає, потім дописуємо.
    if !FileManager.default.fileExists(atPath: logURL.path) {
        _ = try? data.write(to: logURL, options: .atomic)
    } else if let h = try? FileHandle(forWritingTo: logURL) {
        _ = try? h.seekToEnd()
        _ = try? h.write(contentsOf: data)
        _ = try? h.close()
    }
}
