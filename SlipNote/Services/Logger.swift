import Foundation
import os.log

/// Simple logging service for debugging user actions
final class Logger {
    static let shared = Logger()

    private let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.slipnote.app", category: "SlipNote")
    private let fileURL: URL
    private let dateFormatter: DateFormatter

    private init() {
        // Log file in Application Support
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupportURL.appendingPathComponent("SlipNote")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        fileURL = appDirectory.appendingPathComponent("slipnote.log")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    // MARK: - Log Levels

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: "DEBUG", message: message, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: "INFO", message: message, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: "WARN", message: message, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: "ERROR", message: message, file: file, function: function, line: line)
    }

    // MARK: - Event Logging

    func event(_ action: String, details: [String: Any]? = nil) {
        var message = "EVENT: \(action)"
        if let details = details {
            let detailsStr = details.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            message += " [\(detailsStr)]"
        }
        info(message)
    }

    // MARK: - Private

    private func log(level: String, message: String, file: String, function: String, line: Int) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] [\(level)] [\(fileName):\(line)] \(message)\n"

        // Console log
        logger.log("\(logLine, privacy: .public)")

        // File log
        writeToFile(logLine)
    }

    private func writeToFile(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Append to existing file
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try? fileHandle.close()
            }
        } else {
            // Create new file
            try? data.write(to: fileURL)
        }

        // Rotate log if too large (> 1MB)
        rotateIfNeeded()
    }

    private func rotateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int,
              size > 1_000_000 else { return }

        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }
}
