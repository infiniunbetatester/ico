// Integration adapter, compiled ONLY as part of the existing ICO app.
import AppKit
import SwiftUI

@MainActor
public func makeICOFileDropWindow(
    screen: NSScreen,
    welcomeIsVisible: @escaping () -> Bool = { false }
) -> LiquidDropWindowController {
    let state = IslandState.shared
    state.resetDropletPull()
    var configuration = LiquidDropConfiguration(
        currentMetrics: {
            if welcomeIsVisible() {
                return LiquidNotchMetrics(bodyWidth: 520, bodyHeight: 320, cornerRadius: 30)
            }
            let minimal = state.view == .compact && state.compactStyle == .minimal
            return LiquidNotchMetrics(
                bodyWidth: state.targetWidth,
                bodyHeight: state.targetHeight,
                cornerRadius: state.targetRadius,
                shoulderWidth: minimal ? 6 : 16,
                additionalHitHeight: state.toastMessage == nil ? 0 : 65,
                isVisible: !(state.view == .compact && state.compactStyle == .hidden)
            )
        },
        isExpanded: { state.view == .open || welcomeIsVisible() },
        requestShelf: { state.expandShelfFromDroplet() },
        receiveFiles: { state.absorbDroppedFiles(urls: $0) }
    )
    configuration.canAcceptDrops = { !welcomeIsVisible() }
    configuration.activityChanged = { state.isExternalFileDragActive = $0 }
    configuration.reportError = { _ in
        state.showToast("Не удалось получить файл", icon: "exclamationmark.triangle.fill")
    }
    configuration.log = { print("[ICO Drop] \($0)") }
    // Increase this BEFORE creating the window if any existing panel/toast exceeds this area.
    configuration.receiverSize = CGSize(width: 640, height: 480)

    return LiquidDropWindowController(screen: screen, configuration: configuration) {
        // Keep the real root, activeContentPanel, services and all unrelated application logic.
        DynamicIslandRootView()
    }
}
