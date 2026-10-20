import AppKit
import CoreGraphics
import CoreImage
@preconcurrency import ScreenCaptureKit
import Vision
import Observation

private struct IslandQRFrame: @unchecked Sendable {
    let image: CGImage
}

private enum IslandQRError: LocalizedError {
    case permission
    case missingDisplay
    case noQR
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permission: "Разрешите приложению запись экрана в настройках конфиденциальности."
        case .missingDisplay: "Экран отключён. Повторите выделение."
        case .noQR: "В выбранной области QR-код не обнаружен."
        case .unavailable: "Не удалось начать выделение области."
        }
    }
}

@MainActor
@Observable
public final class IslandQRCode {
    public enum Mode: String, CaseIterable, Identifiable {
        case generate = "Генератор"
        case scan = "Сканер"

        public var id: String { rawValue }
    }

    public var mode: Mode = .generate
    public var inputText: String = "https://github.com/infiniunbetatester/ico"
    public var scannedResult: String = ""
    public private(set) var isBusy = false
    public private(set) var isSelecting = false
    public private(set) var didCopy = false
    public private(set) var error: String?

    @ObservationIgnored var onCompleted: (() -> Void)?
    @ObservationIgnored private let picker = IslandRegionPicker()
    @ObservationIgnored private var copyFeedbackTask: Task<Void, Never>?

    public init() {}

    // MARK: - QR Code Generator

    public func generateImage(from text: String, size: CGFloat = 200) -> NSImage? {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let data = content.data(using: .utf8) else { return nil }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        let extent = outputImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let scale = size / extent.width
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let rep = NSCIImageRep(ciImage: transformed)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }

    public func copyQRImage() {
        guard let image = generateImage(from: inputText, size: 512) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        flashCopyFeedback()
    }

    public func pasteClipboardText() {
        if let string = NSPasteboard.general.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func saveQRPNG() {
        guard let image = generateImage(from: inputText, size: 1024),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "qr_code.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }

    // MARK: - QR Code Scanner

    public func scan() {
        guard !isBusy else { return }
        mode = .scan
        isBusy = true
        error = nil
        didCopy = false

        Task { @MainActor in
            defer {
                isBusy = false
                isSelecting = false
            }

            do {
                if !CGPreflightScreenCaptureAccess() {
                    guard CGRequestScreenCaptureAccess() else {
                        throw IslandQRError.permission
                    }
                }

                isSelecting = true
                let region = try await picker.select()
                isSelecting = false

                // Delay to allow overlay window removal
                try await Task.sleep(nanoseconds: 90_000_000)

                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )

                guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
                    throw IslandQRError.missingDisplay
                }

                let ownApplications = content.applications.filter {
                    $0.processID == ProcessInfo.processInfo.processIdentifier
                }

                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: ownApplications,
                    exceptingWindows: []
                )

                let configuration = SCStreamConfiguration()
                configuration.sourceRect = region.sourceRect
                configuration.width = max(1, Int((region.sourceRect.width * region.scale).rounded()))
                configuration.height = max(1, Int((region.sourceRect.height * region.scale).rounded()))
                configuration.showsCursor = false

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )

                let frame = IslandQRFrame(image: image)

                let detected = try await Task.detached(priority: .userInitiated) {
                    let request = VNDetectBarcodesRequest()
                    request.symbologies = [.qr, .microQR]

                    let handler = VNImageRequestHandler(cgImage: frame.image, options: [:])
                    try handler.perform([request])

                    let observations = request.results ?? []
                    guard let first = observations.first, let payload = first.payloadStringValue else {
                        return ""
                    }
                    return payload
                }.value

                guard !detected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw IslandQRError.noQR
                }

                scannedResult = detected
                copyScannedResult()
                onCompleted?()
            } catch is CancellationError {
                // Cancelled by user with Esc
            } catch {
                self.error = error.localizedDescription
                onCompleted?()
            }
        }
    }

    public func copyScannedResult() {
        guard !scannedResult.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(scannedResult, forType: .string)
        flashCopyFeedback()
    }

    public func openScannedURL() {
        guard let url = URL(string: scannedResult),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    public var isScannedURL: Bool {
        guard let url = URL(string: scannedResult),
              let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public func transferScannedToGenerator() {
        inputText = scannedResult
        mode = .generate
    }

    private func flashCopyFeedback() {
        didCopy = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.didCopy = false
        }
    }
}
