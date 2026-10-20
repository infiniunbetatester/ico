import Foundation
import AppKit

public struct NowPlayingTrack: Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double
    public var elapsed: Double
    public var isPlaying: Bool
    public var appName: String
    public var artworkData: Data?
}

@MainActor
public final class UniversalMediaController {
    public static let shared = UniversalMediaController()
    
    public var currentTrack: NowPlayingTrack?
    public var isAnyMediaActive: Bool = false
    
    nonisolated private static let perlPath: String = "/usr/bin/perl"
    private var scriptPath: String?
    private var dylibPath: String?
    
    private var listenerProcess: Process?
    private var listenerInputPipe: Pipe?
    private var listenerOutputPipe: Pipe?
    private var lineBuffer = Data()
    private let commandQueue = DispatchQueue(label: "com.ico.app.mediaCommands", qos: .userInitiated)
    
    public init() {
        locateAdapterFiles()
        startAdapterListener()
    }
    
    // MARK: - File Locator
    
    private func locateAdapterFiles() {
        let fileManager = FileManager.default
        let currentDir = FileManager.default.currentDirectoryPath
        let bundlePath = Bundle.main.bundlePath
        
        let possibleScriptPaths = [
            Bundle.main.path(forResource: "run", ofType: "pl"),
            "\(bundlePath)/Contents/Resources/run.pl",
            "\(currentDir)/Resources/run.pl",
            "\(currentDir)/ICO.app/Contents/Resources/run.pl"
        ].compactMap { $0 }
        
        for path in possibleScriptPaths {
            if fileManager.fileExists(atPath: path) {
                self.scriptPath = path
                break
            }
        }
        
        let possibleDylibPaths = [
            "\(bundlePath)/Contents/Frameworks/libMediaRemoteAdapter.dylib",
            "\(currentDir)/Frameworks/libMediaRemoteAdapter.dylib",
            "\(currentDir)/ICO.app/Contents/Frameworks/libMediaRemoteAdapter.dylib"
        ]
        
        for path in possibleDylibPaths {
            if fileManager.fileExists(atPath: path) {
                self.dylibPath = path
                break
            }
        }
    }
    
    // MARK: - Real-Time MediaRemote Loop Listener
    
    private func startAdapterListener() {
        guard let script = scriptPath, let dylib = dylibPath else { return }
        
        stopAdapterListener()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: UniversalMediaController.perlPath)
        process.arguments = [script, dylib, "loop"]
        
        let inPipe = Pipe()
        process.standardInput = inPipe
        self.listenerInputPipe = inPipe
        
        let outPipe = Pipe()
        process.standardOutput = outPipe
        self.listenerOutputPipe = outPipe
        process.standardError = Pipe()
        
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let available = handle.availableData
            guard !available.isEmpty else { return }
            
            Task { @MainActor [weak self] in
                self?.processIncomingData(available)
            }
        }
        
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                // Auto-restart after brief pause if terminated
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                self?.startAdapterListener()
            }
        }
        
        do {
            try process.run()
            self.listenerProcess = process
        } catch {
            // Failed to start listener
        }
    }
    
    private func stopAdapterListener() {
        listenerOutputPipe?.fileHandleForReading.readabilityHandler = nil
        if let proc = listenerProcess, proc.isRunning {
            proc.terminate()
        }
        listenerProcess = nil
        listenerInputPipe = nil
        listenerOutputPipe = nil
    }
    
    private func processIncomingData(_ data: Data) {
        lineBuffer.append(data)
        
        let delimiter = UInt8(ascii: "\n")
        while let index = lineBuffer.firstIndex(of: delimiter) {
            let lineData = lineBuffer.prefix(upTo: index)
            lineBuffer.removeSubrange(..<lineBuffer.index(after: index))
            
            if !lineData.isEmpty {
                parseEventLine(lineData)
            }
        }
    }
    
    private struct AdapterPayload: Decodable {
        let title: String?
        let artist: String?
        let album: String?
        let applicationName: String?
        let bundleIdentifier: String?
        let isPlaying: Bool?
        let playbackRate: Double?
        let durationMicros: Double?
        let elapsedTimeMicros: Double?
        let timestampEpochMicros: Double?
        let artworkDataBase64: String?
    }
    
    private struct AdapterEvent: Decodable {
        let type: String?
        let payload: AdapterPayload?
    }
    
    private func parseEventLine(_ data: Data) {
        guard let event = try? JSONDecoder().decode(AdapterEvent.self, from: data),
              let payload = event.payload else {
            return
        }
        
        applyPayload(payload)
    }
    
    private func applyPayload(_ payload: AdapterPayload) {
        let rawTitle = (payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else { return }
        
        let isPlaying = (payload.isPlaying == true) || ((payload.playbackRate ?? 0.0) > 0.0)
        let duration = max(1.0, (payload.durationMicros ?? 180_000_000.0) / 1_000_000.0)
        let baseElapsed = max(0.0, (payload.elapsedTimeMicros ?? 0.0) / 1_000_000.0)
        
        // Accurate real-time elapsed position using packet epoch timestamp
        var realElapsed = baseElapsed
        if isPlaying, let ts = payload.timestampEpochMicros, ts > 0 {
            let now = Date().timeIntervalSince1970
            let packetTime = ts / 1_000_000.0
            let delta = max(0.0, now - packetTime)
            if delta < 14400 { // within 4 hours
                realElapsed = min(duration, baseElapsed + delta)
            }
        }
        
        // Detect player source name
        var appName = payload.applicationName ?? "Медиа"
        let bundleId = (payload.bundleIdentifier ?? "").lowercased()
        let titleLower = rawTitle.lowercased()
        
        if bundleId.contains("yandex") || appName.contains("Yandex") || appName.contains("Яндекс") {
            appName = "Яндекс Музыка"
        } else if bundleId.contains("spotify") || appName.contains("Spotify") {
            appName = "Spotify"
        } else if bundleId.contains("apple.music") || appName == "Music" {
            appName = "Apple Music"
        } else if bundleId.contains("safari") || bundleId.contains("chrome") || titleLower.contains("youtube") {
            appName = titleLower.contains("youtube") ? "YouTube" : (appName.isEmpty ? "Браузер" : appName)
        } else if bundleId.contains("telegram") {
            appName = "Telegram"
        }
        
        let rawArtist = (payload.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.isEmpty ? appName : rawArtist
        
        // Decode artwork if present
        var artworkData: Data? = nil
        if let base64 = payload.artworkDataBase64, !base64.isEmpty {
            artworkData = Data(base64Encoded: base64)
        }
        
        self.currentTrack = NowPlayingTrack(
            title: rawTitle,
            artist: artist,
            album: payload.album ?? "",
            duration: duration,
            elapsed: realElapsed,
            isPlaying: isPlaying,
            appName: appName,
            artworkData: artworkData
        )
        self.isAnyMediaActive = isPlaying
        
        // Push directly to IslandState UI
        IslandState.shared.updateNowPlaying(
            title: rawTitle,
            artist: artist,
            source: appName,
            duration: duration,
            elapsed: realElapsed,
            isPlaying: isPlaying,
            artworkData: artworkData
        )
    }
    
    // MARK: - Instant Playback Controls
    
    public func refreshNowPlaying() {
        executeAdapterCommand("get")
    }
    
    private func executeAdapterCommand(_ command: String) {
        let line = "\(command)\n"
        guard let data = line.data(using: .utf8) else { return }
        
        // 1. Send via active persistent loop STDIN pipe (instant in-memory write, zero process spawn overhead!)
        if let proc = self.listenerProcess, proc.isRunning, let inPipe = self.listenerInputPipe {
            do {
                try inPipe.fileHandleForWriting.write(contentsOf: data)
                return
            } catch {
                // fall through if pipe closed
            }
        }
        
        // 2. Standalone fallback execution with 300ms runloop delivery
        guard let script = self.scriptPath, let dylib = self.dylibPath else { return }
        commandQueue.async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: UniversalMediaController.perlPath)
            proc.arguments = [script, dylib, command]
            
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {}
        }
    }
    
    public func togglePlayPause() {
        executeAdapterCommand("toggle_play_pause")
    }
    
    public func nextTrack() {
        executeAdapterCommand("next_track")
    }
    
    public func previousTrack() {
        executeAdapterCommand("previous_track")
    }
    
    public func seek(to seconds: Double) {
        executeAdapterCommand("set_time \(Int(seconds))")
    }
}
