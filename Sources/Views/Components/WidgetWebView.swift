import SwiftUI
import AppKit
import WebKit

public struct WidgetWebView: NSViewRepresentable {
    let url: URL
    let reloadToken: UUID
    
    public init(url: URL, reloadToken: UUID = UUID()) {
        self.url = url
        self.reloadToken = reloadToken
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        // Inject window.ico bridge into JavaScript
        let bridgeScript = WKUserScript(
            source: """
            window.ico = {
                toast: function(text, icon) {
                    window.webkit.messageHandlers.icoBridge.postMessage({ action: 'toast', text: text, icon: icon || 'sparkles' });
                },
                copy: function(text) {
                    window.webkit.messageHandlers.icoBridge.postMessage({ action: 'copy', text: text });
                },
                close: function() {
                    window.webkit.messageHandlers.icoBridge.postMessage({ action: 'close' });
                },
                openURL: function(url) {
                    window.webkit.messageHandlers.icoBridge.postMessage({ action: 'openURL', url: url });
                }
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bridgeScript)
        contentController.add(context.coordinator, name: "icoBridge")
        config.userContentController = contentController
        
        // Preferences
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        webView.navigationDelegate = context.coordinator
        
        loadHTML(into: webView)
        return webView
    }
    
    public func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedURL != url || context.coordinator.lastToken != reloadToken {
            context.coordinator.lastLoadedURL = url
            context.coordinator.lastToken = reloadToken
            loadHTML(into: webView)
        }
    }
    
    private func loadHTML(into webView: WKWebView) {
        let folder = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: folder)
    }
    
    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastLoadedURL: URL?
        var lastToken: UUID?
        
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "icoBridge",
                  let body = message.body as? [String: Any],
                  let action = body["action"] as? String else {
                return
            }
            
            Task { @MainActor in
                switch action {
                case "toast":
                    let text = body["text"] as? String ?? ""
                    let icon = body["icon"] as? String ?? "sparkles"
                    IslandState.shared.showToast(text, icon: icon)
                    
                case "copy":
                    if let text = body["text"] as? String {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    
                case "close":
                    IslandState.shared.collapse()
                    
                case "openURL":
                    if let str = body["url"] as? String, let url = URL(string: str) {
                        NSWorkspace.shared.open(url)
                    }
                    
                default:
                    break
                }
            }
        }
    }
}
