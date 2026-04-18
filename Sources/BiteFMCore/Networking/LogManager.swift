import Foundation
import os
#if os(macOS)
import AppKit
#endif

public final class LogManager {
    public static let shared = LogManager()

    private let logger = Logger(subsystem: AppIdentifiers.logSubsystem, category: "App")
    private let logFileURL: URL?
    private let maxLogSize = 1024 * 1024 // 1 MB

    private init() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            self.logFileURL = nil
            return
        }

        let appLogFolderURL = appSupportURL.appendingPathComponent("BiteFM", isDirectory: true).appendingPathComponent("logs", isDirectory: true)

        do {
            try fileManager.createDirectory(at: appLogFolderURL, withIntermediateDirectories: true)
            self.logFileURL = appLogFolderURL.appendingPathComponent("app.log")

            // Log file start
            self.log("--- App gestartet ---", type: .info)
        } catch {
            print("Fehler beim Erstellen des Log-Verzeichnisses: \(error)")
            self.logFileURL = nil
        }
    }

    public func log(_ message: String, type: OSLogType = .default) {
        // 1. System-Log (Logger) - persistent in system database
        switch type {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        case .fault: logger.fault("\(message, privacy: .public)")
        default: logger.log(level: .default, "\(message, privacy: .public)")
        }

        // 2. File-Log - easy to find and send
        appendToFile(message, type: type)

        // 3. Xcode-Konsole (nur DEBUG): keine .debug-Zeilen, um Simulator-/Framework-Noise lesbar zu halten.
        // Detaillierte Routine-Logs weiter in Datei + Unified Logging (Console.app / Logger).
        #if DEBUG
        if type != .debug {
            print("[\(Date())] \(message)")
        }
        #endif
    }

    private func appendToFile(_ message: String, type: OSLogType) {
        guard let url = logFileURL else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let typeString = type.description.uppercased()
        let logLine = "[\(timestamp)] [\(typeString)] \(message)\n"

        guard let data = logLine.data(using: .utf8) else { return }

        // Ensure parent directory exists
        let parentDir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        if FileManager.default.fileExists(atPath: url.path) {
            // Check size and rotate if necessary
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int, size > maxLogSize {
                rotateLogFile()
            }
        }

        // Re-check existence as it might have been deleted/rotated
        if FileManager.default.fileExists(atPath: url.path) {
            if let fileHandle = try? FileHandle(forWritingTo: url) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            do {
                try data.write(to: url)
            } catch {
                #if DEBUG
                print("FAILED to write log to file: \(error)")
                #endif
            }
        }
    }

    private func rotateLogFile() {
        guard let url = logFileURL else { return }
        let backupURL = url.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: url, to: backupURL)
    }

    /// macOS: Reveal in Finder. iOS: no system folder picker; path is logged for diagnostics.
    public func openLogFolder() {
        #if os(macOS)
        guard logFileURL != nil else { return }
        guard let folder = logFileURL?.deletingLastPathComponent() else { return }
        NSWorkspace.shared.selectFile(logFileURL?.path, inFileViewerRootedAtPath: folder.path)
        #else
        if let path = logFileURL?.path {
            log("Log-_datei (iOS, App-Sandbox): \(path)", type: .info)
        }
        #endif
    }
}

extension OSLogType: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        default: return "DEFAULT"
        }
    }
}
