import AppKit
import Foundation

@MainActor struct LiquidFilePayload {
    let urls: [URL]
    let promises: [NSFilePromiseReceiver]

    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    static func advertisesFiles(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: acceptedTypes) != nil
    }

    static func read(_ pasteboard: NSPasteboard) -> LiquidFilePayload? {
        // AppKit selects one representation for each pasteboard item, preferring promises.
        let objects = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self, NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        var urls: [URL] = []
        var promises: [NSFilePromiseReceiver] = []
        for object in objects {
            if let promise = object as? NSFilePromiseReceiver { promises.append(promise) }
            else if let url = object as? URL, url.isFileURL { urls.append(url) }
        }
        guard !urls.isEmpty || !promises.isEmpty else { return nil }
        return LiquidFilePayload(urls: urls, promises: promises)
    }
}

@MainActor final class LiquidFileReceiver {
    @MainActor private final class Batch {
        var urls: [URL]
        var remaining = 0
        let receivers: [NSFilePromiseReceiver]
        let completed: ([URL]) -> Void
        let failed: (Error) -> Void
        init(_ payload: LiquidFilePayload, completed: @escaping ([URL]) -> Void, failed: @escaping (Error) -> Void) {
            urls = payload.urls
            receivers = payload.promises
            self.completed = completed
            self.failed = failed
        }
    }

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ICO.FilePromises"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private var batches: [UUID: Batch] = [:]

    func receive(_ payload: LiquidFilePayload, configuration: LiquidDropConfiguration) -> Bool {
        guard !payload.promises.isEmpty else {
            configuration.receiveFiles(Self.unique(payload.urls))
            return !payload.urls.isEmpty
        }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask, appropriateFor: nil, create: true)
            let destination = support
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "ICO", isDirectory: true)
                .appendingPathComponent("ReceivedFiles", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let id = UUID()
            let batch = Batch(payload, completed: configuration.receiveFiles, failed: configuration.reportError)
            batches[id] = batch
            for promise in batch.receivers {
                // No file contents are requested until performDragOperation has accepted the drop.
                promise.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: queue) { [weak self] url, error in
                    Task { @MainActor [weak self] in self?.received(url, error: error, batchID: id) }
                }
                // fileNames is populated by receivePromisedFiles, not before that call.
                batch.remaining += max(1, promise.fileNames.count)
            }
            return true
        } catch {
            configuration.reportError(error)
            return false
        }
    }

    private func received(_ url: URL, error: Error?, batchID: UUID) {
        guard let batch = batches[batchID] else { return }
        if let error { batch.failed(error) }
        else if url.isFileURL { batch.urls.append(url) }
        batch.remaining -= 1
        if batch.remaining <= 0 {
            batches.removeValue(forKey: batchID)
            let files = Self.unique(batch.urls)
            if !files.isEmpty { batch.completed(files) }
        }
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { $0.isFileURL && seen.insert($0.standardizedFileURL).inserted }
    }
}
