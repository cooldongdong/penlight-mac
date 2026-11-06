import Foundation

/// Appends a line to ~/Library/Logs/Penlight.log (unified logging is hard to read back).
func penlightLog(_ message: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Penlight.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.data(using: .utf8)!.write(to: url)
    }
}
