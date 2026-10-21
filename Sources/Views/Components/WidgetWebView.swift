import SwiftUI
import AppKit
import WebKit

public struct WidgetWebView: NSViewRepresentable {
    let widgetId: String
    let url: URL
    let reloadToken: UUID
    
    public init(widgetId: String, url: URL, reloadToken: UUID = UUID()) {
        self.widgetId = widgetId
        self.url = url
        self.reloadToken = reloadToken
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(widgetId: widgetId)
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        return WidgetManager.shared.getOrCreateWebView(
            id: widgetId,
            url: url,
            reloadToken: reloadToken,
            coordinator: context.coordinator
        )
    }
    
    public func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastToken != reloadToken {
            context.coordinator.lastToken = reloadToken
            WidgetManager.shared.reloadWidgetWebView(id: widgetId, url: url)
        }
    }
    
    public static let bridgeJavaScript: String = """
    window._icoCallbacks = {};
    window._icoResolve = function(reqId, result, error) {
        if (window._icoCallbacks[reqId]) {
            if (error) {
                window._icoCallbacks[reqId].reject(new Error(error));
            } else {
                window._icoCallbacks[reqId].resolve(result);
            }
            delete window._icoCallbacks[reqId];
        }
    };

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
        },
        notify: function(title, body) {
            window.webkit.messageHandlers.icoBridge.postMessage({ action: 'notify', title: title, body: body || '' });
        },
        sound: function(name) {
            window.webkit.messageHandlers.icoBridge.postMessage({ action: 'sound', name: name || 'Glass' });
        },
        storage: {
            set: function(key, value) {
                window.webkit.messageHandlers.icoBridge.postMessage({ action: 'storageSet', key: key, value: JSON.stringify(value) });
                try { localStorage.setItem(key, JSON.stringify(value)); } catch(e){}
            },
            get: function(key, fallback) {
                try {
                    var v = localStorage.getItem(key);
                    return v !== null ? JSON.parse(v) : (fallback !== undefined ? fallback : null);
                } catch(e) {
                    return fallback !== undefined ? fallback : null;
                }
            },
            remove: function(key) {
                window.webkit.messageHandlers.icoBridge.postMessage({ action: 'storageRemove', key: key });
                try { localStorage.removeItem(key); } catch(e){}
            }
        },
        fetch: function(url, options) {
            return new Promise(function(resolve, reject) {
                var reqId = 'req_' + Math.random().toString(36).substr(2, 9);
                window._icoCallbacks[reqId] = {
                    resolve: function(resp) {
                        resolve({
                            status: resp.status,
                            ok: resp.status >= 200 && resp.status < 300,
                            text: function() { return Promise.resolve(resp.text); },
                            json: function() { return Promise.resolve(JSON.parse(resp.text)); }
                        });
                    },
                    reject: reject
                };
                window.webkit.messageHandlers.icoBridge.postMessage({
                    action: 'fetch',
                    reqId: reqId,
                    url: url,
                    method: (options && options.method) || 'GET',
                    headers: (options && options.headers) || {},
                    body: (options && options.body) || null
                });
            });
        },
        onCollapse: function(callback) {
            window.addEventListener('ico:collapse', callback);
        },
        onExpand: function(callback) {
            window.addEventListener('ico:expand', callback);
        }
    };
    """
    
    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let widgetId: String
        var lastToken: UUID?
        
        public init(widgetId: String) {
            self.widgetId = widgetId
        }
        
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
                    
                case "sound":
                    let soundName = body["name"] as? String ?? "Glass"
                    NSSound(named: soundName)?.play()
                    
                case "notify":
                    let title = body["title"] as? String ?? "ICO"
                    let msg = body["body"] as? String ?? ""
                    sendSystemNotification(title: title, body: msg)
                    
                case "storageSet":
                    if let key = body["key"] as? String, let valStr = body["value"] as? String {
                        UserDefaults.standard.set(valStr, forKey: "ico_widget_\(widgetId)_\(key)")
                    }
                    
                case "storageRemove":
                    if let key = body["key"] as? String {
                        UserDefaults.standard.removeObject(forKey: "ico_widget_\(widgetId)_\(key)")
                    }
                    
                case "fetch":
                    guard let reqId = body["reqId"] as? String,
                          let urlStr = body["url"] as? String,
                          let targetURL = URL(string: urlStr) else {
                        return
                    }
                    let method = body["method"] as? String ?? "GET"
                    let headers = body["headers"] as? [String: String] ?? [:]
                    let reqBody = body["body"] as? String
                    
                    performNativeFetch(
                        webView: message.webView,
                        reqId: reqId,
                        url: targetURL,
                        method: method,
                        headers: headers,
                        body: reqBody
                    )
                    
                default:
                    break
                }
            }
        }
        
        private func sendSystemNotification(title: String, body: String) {
            let cleanTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let cleanBody = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let scriptText = "display notification \"\(cleanBody)\" with title \"\(cleanTitle)\" sound name \"Glass\""
            
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                if let script = NSAppleScript(source: scriptText) {
                    script.executeAndReturnError(&error)
                }
            }
            NSSound(named: "Glass")?.play()
        }
        
        private func performNativeFetch(
            webView: WKWebView?,
            reqId: String,
            url: URL,
            method: String,
            headers: [String: String],
            body: String?
        ) {
            var request = URLRequest(url: url)
            request.httpMethod = method
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
            }
            if let body = body {
                request.httpBody = body.data(using: .utf8)
            }
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                let httpResp = response as? HTTPURLResponse
                let statusCode = httpResp?.statusCode ?? (error == nil ? 200 : 500)
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let errString = error?.localizedDescription
                
                Task { @MainActor in
                    guard let wv = webView else { return }
                    if let err = errString {
                        let escaped = err.replacingOccurrences(of: "'", with: "\\'")
                        wv.evaluateJavaScript("window._icoResolve('\(reqId)', null, '\(escaped)');", completionHandler: nil)
                    } else {
                        let dict: [String: Any] = ["status": statusCode, "text": text]
                        if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            wv.evaluateJavaScript("window._icoResolve('\(reqId)', \(jsonString), null);", completionHandler: nil)
                        }
                    }
                }
            }.resume()
        }
    }
}
