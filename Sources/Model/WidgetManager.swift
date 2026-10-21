import Foundation
import AppKit
import WebKit
import Observation

public struct CustomWidgetInfo: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let iconName: String
    public let description: String
    public let folderURL: URL
    public let htmlURL: URL
    public let height: CGFloat
}

public struct StoreWidget: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let iconName: String
    public let description: String
    public let category: String
    public let defaultHeight: CGFloat
    public let htmlContent: String
    public let widgetJson: String
}

@MainActor
@Observable
public final class WidgetManager {
    public static let shared = WidgetManager()
    
    public var installedWidgets: [CustomWidgetInfo] = []
    public var activeWidgetId: String?
    public var isViewingWidget: Bool = false // false = catalog/store, true = running widget view
    
    // Cache of running webviews to preserve state, timers and memory across collapse/expand
    @ObservationIgnored
    private var webViewCache: [String: (view: WKWebView, token: UUID)] = [:]
    
    public func getOrCreateWebView(id: String, url: URL, reloadToken: UUID, coordinator: WidgetWebView.Coordinator) -> WKWebView {
        if let cached = webViewCache[id] {
            if cached.token != reloadToken {
                let folder = url.deletingLastPathComponent()
                cached.view.loadFileURL(url, allowingReadAccessTo: folder)
                webViewCache[id] = (cached.view, reloadToken)
            }
            return cached.view
        }
        
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        let bridgeScript = WKUserScript(
            source: WidgetWebView.bridgeJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bridgeScript)
        contentController.add(coordinator, name: "icoBridge")
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = coordinator
        
        let folder = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: folder)
        
        webViewCache[id] = (webView, reloadToken)
        return webView
    }
    
    public func reloadWidgetWebView(id: String, url: URL) {
        if let cached = webViewCache[id] {
            let folder = url.deletingLastPathComponent()
            cached.view.loadFileURL(url, allowingReadAccessTo: folder)
        }
    }
    
    public func notifyWidgets(isExpanded: Bool) {
        let script = isExpanded ? "window.dispatchEvent(new CustomEvent('ico:expand'));" : "window.dispatchEvent(new CustomEvent('ico:collapse'));"
        for (_, entry) in webViewCache {
            entry.view.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    public var widgetsDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ico/widgets", isDirectory: true)
    }
    
    public init() {
        ensureDirectoryAndSeedDefault()
        reloadWidgets()
    }
    
    public func ensureDirectoryAndSeedDefault() {
        let dir = widgetsDirectory
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        let seedKey = "ico_widgets_seeded_v3"
        if !UserDefaults.standard.bool(forKey: seedKey) {
            UserDefaults.standard.set(true, forKey: seedKey)
            if let todoWidget = availableStoreWidgets.first(where: { $0.id == "todo-checklist" }) {
                installStoreWidget(todoWidget)
            }
        }
    }
    
    public func reloadWidgets() {
        let dir = widgetsDirectory
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            installedWidgets = []
            return
        }
        
        var loaded: [CustomWidgetInfo] = []
        for folder in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
            
            let htmlFile = folder.appendingPathComponent("index.html")
            guard fm.fileExists(atPath: htmlFile.path) else { continue }
            
            let jsonFile = folder.appendingPathComponent("widget.json")
            var widgetName = folder.lastPathComponent
            var widgetIcon = "puzzlepiece.extension.fill"
            var widgetDesc = "Пользовательский виджет"
            var widgetHeight: CGFloat = 260
            
            if let jsonData = try? Data(contentsOf: jsonFile),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                if let name = json["name"] as? String, !name.isEmpty { widgetName = name }
                if let icon = json["icon"] as? String, !icon.isEmpty { widgetIcon = icon }
                if let desc = json["description"] as? String { widgetDesc = desc }
                if let h = json["height"] as? CGFloat, h >= 120, h <= 450 { widgetHeight = h }
            }
            
            let info = CustomWidgetInfo(
                id: folder.lastPathComponent,
                name: widgetName,
                iconName: widgetIcon,
                description: widgetDesc,
                folderURL: folder,
                htmlURL: htmlFile,
                height: widgetHeight
            )
            loaded.append(info)
        }
        
        self.installedWidgets = loaded
        if activeWidgetId == nil || !loaded.contains(where: { $0.id == activeWidgetId }) {
            self.activeWidgetId = loaded.first?.id
        }
    }
    
    public func openWidgetsFolderInFinder() {
        let dir = widgetsDirectory
        ensureDirectoryAndSeedDefault()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }
    
    public func openWidgetCode(id: String) {
        let dir = widgetsDirectory.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
        }
    }
    
    public func installStoreWidget(_ item: StoreWidget) {
        let dir = widgetsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let jsonPath = dir.appendingPathComponent("widget.json")
        try? item.widgetJson.write(to: jsonPath, atomically: true, encoding: .utf8)
        
        let htmlPath = dir.appendingPathComponent("index.html")
        try? item.htmlContent.write(to: htmlPath, atomically: true, encoding: .utf8)
        
        reloadWidgets()
        activeWidgetId = item.id
        isViewingWidget = true
    }
    
    public func uninstallWidget(id: String) {
        webViewCache.removeValue(forKey: id)
        let dir = widgetsDirectory.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        reloadWidgets()
        if activeWidgetId == id {
            activeWidgetId = installedWidgets.first?.id
            if activeWidgetId == nil {
                isViewingWidget = false
            }
        }
    }
    
    public func createCustomTemplate() {
        let dir = widgetsDirectory
        let templateId = "custom-\(Int(Date().timeIntervalSince1970) % 10000)"
        let sampleDir = dir.appendingPathComponent(templateId, isDirectory: true)
        try? FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        
        let jsonContent = """
        {
          "name": "Мой виджет",
          "icon": "sparkles",
          "description": "Пользовательский HTML / CSS / JS виджет",
          "height": 260
        }
        """
        try? jsonContent.write(to: sampleDir.appendingPathComponent("widget.json"), atomically: true, encoding: .utf8)
        
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; user-select: none; }
            body { background: transparent; color: #fff; padding: 20px; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; text-align: center; }
            .card { background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 22px; max-width: 480px; width: 100%; box-shadow: 0 8px 30px rgba(0,0,0,0.3); }
            h2 { font-size: 17px; font-weight: 600; margin-bottom: 8px; color: #fff; }
            p { font-size: 12px; color: rgba(255,255,255,0.65); line-height: 1.5; margin-bottom: 16px; }
            .btn { background: #fff; color: #000; border: none; padding: 8px 18px; border-radius: 10px; font-size: 12px; font-weight: 600; cursor: pointer; transition: transform 0.1s, opacity 0.15s; margin: 0 4px; }
            .btn:hover { opacity: 0.9; }
            .btn:active { transform: scale(0.96); }
            .btn-secondary { background: rgba(255,255,255,0.12); color: #fff; border: 1px solid rgba(255,255,255,0.15); }
          </style>
        </head>
        <body>
          <div class="card">
            <h2>✨ Твой персональный виджет</h2>
            <p>Отредактируй <b>index.html</b> и <b>widget.json</b> в этой папке. Поддерживаются любые веб-технологии, WebSockets, LocalStorage и API <code>window.ico</code>!</p>
            <div>
              <button class="btn" onclick="window.ico.toast('Привет из твоего виджета! ✨', 'sparkles')">Вызвать тост</button>
              <button class="btn btn-secondary" onclick="window.ico.copy('Скопировано из виджета!')">В буфер обмена</button>
            </div>
          </div>
        </body>
        </html>
        """
        try? htmlContent.write(to: sampleDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        
        reloadWidgets()
        activeWidgetId = templateId
        isViewingWidget = true
        NSWorkspace.shared.selectFile(sampleDir.appendingPathComponent("index.html").path, inFileViewerRootedAtPath: sampleDir.path)
    }
    
    // MARK: - Built-in Widget Catalog / Store
    
    public var availableStoreWidgets: [StoreWidget] {
        [
            StoreWidget(
                id: "crypto-ticker",
                name: "Криптовалюты",
                iconName: "bitcoinsign.circle.fill",
                description: "Живые курсы BTC, ETH, TON, SOL с Binance в реальном времени.",
                category: "Финансы",
                defaultHeight: 260,
                htmlContent: cryptoWidgetHTML,
                widgetJson: """
                {
                  "name": "Криптовалюты",
                  "icon": "bitcoinsign.circle.fill",
                  "description": "Курсы BTC, ETH, TON, SOL с Binance",
                  "height": 260
                }
                """
            ),
            StoreWidget(
                id: "weather-minimal",
                name: "Погода",
                iconName: "cloud.sun.fill",
                description: "Текущая погода, температура, ветер и осадки без необходимости API ключей.",
                category: "Информеры",
                defaultHeight: 260,
                htmlContent: weatherWidgetHTML,
                widgetJson: """
                {
                  "name": "Погода",
                  "icon": "cloud.sun.fill",
                  "description": "Минималистичный погодный информер",
                  "height": 260
                }
                """
            ),
            StoreWidget(
                id: "quick-notes",
                name: "Блокнот",
                iconName: "note.text",
                description: "Быстрые заметки прямо в челке с мгновенным автосохранением в памяти.",
                category: "Продуктивность",
                defaultHeight: 260,
                htmlContent: notesWidgetHTML,
                widgetJson: """
                {
                  "name": "Блокнот",
                  "icon": "note.text",
                  "description": "Быстрые заметки с автосохранением",
                  "height": 260
                }
                """
            ),
            StoreWidget(
                id: "todo-checklist",
                name: "Чек-лист задач",
                iconName: "checklist",
                description: "Простой список дел на сегодня. Вычёркивай выполненные задачи в один клик.",
                category: "Продуктивность",
                defaultHeight: 260,
                htmlContent: todoWidgetHTML,
                widgetJson: """
                {
                  "name": "Чек-лист задач",
                  "icon": "checklist",
                  "description": "Простой список дел на сегодня",
                  "height": 260
                }
                """
            ),
            StoreWidget(
                id: "world-clock",
                name: "Мировое время",
                iconName: "globe.americas.fill",
                description: "Точное время в ключевых финансовых и IT столицах (Москва, Лондон, Нью-Йорк, Токио).",
                category: "Информеры",
                defaultHeight: 260,
                htmlContent: worldClockWidgetHTML,
                widgetJson: """
                {
                  "name": "Мировое время",
                  "icon": "globe.americas.fill",
                  "description": "Часовые пояса мира",
                  "height": 260
                }
                """
            ),
            StoreWidget(
                id: "screen-ruler",
                name: "Экранная линейка",
                iconName: "ruler.fill",
                description: "Интерактивный замер пикселей на экране с определением размеров, диагонали, соотношения сторон и экспортом в CSS.",
                category: "Инструменты",
                defaultHeight: 270,
                htmlContent: screenRulerWidgetHTML,
                widgetJson: """
                {
                  "name": "Экранная линейка",
                  "icon": "ruler.fill",
                  "description": "Замер размеров элементов на экране в пикселях",
                  "height": 270
                }
                """
            )
        ]
    }
    
    // MARK: - Preset HTML Codes
    
    private var cryptoWidgetHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif; user-select: none; }
            body { background: transparent; color: #fff; padding: 18px 20px; }
            .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
            .card { background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.06); border-radius: 13px; padding: 12px 14px; display: flex; flex-direction: column; justify-content: space-between; cursor: pointer; transition: background 0.15s, transform 0.1s; }
            .card:hover { background: rgba(255,255,255,0.08); transform: translateY(-1px); }
            .card:active { transform: scale(0.98); }
            .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
            .title { font-size: 13px; font-weight: 600; color: rgba(255,255,255,0.9); }
            .change { font-size: 11px; font-weight: 600; padding: 2px 6px; border-radius: 5px; }
            .pos { color: #4ade80; background: rgba(74, 222, 128, 0.12); }
            .neg { color: #f87171; background: rgba(248, 113, 113, 0.12); }
            .price { font-size: 17px; font-weight: 700; font-variant-numeric: tabular-nums; }
          </style>
        </head>
        <body>
          <div class="grid" id="grid">
            <div class="card" onclick="copyTicker('BTC', '104,230')">
              <div class="header"><span class="title">₿ Bitcoin</span><span class="change pos" id="btc-c">+2.4%</span></div>
              <div class="price" id="btc-p">$104,230</div>
            </div>
            <div class="card" onclick="copyTicker('ETH', '3,420')">
              <div class="header"><span class="title">♦ Ethereum</span><span class="change pos" id="eth-c">+1.8%</span></div>
              <div class="price" id="eth-p">$3,420</div>
            </div>
            <div class="card" onclick="copyTicker('TON', '6.84')">
              <div class="header"><span class="title">💎 TON</span><span class="change pos" id="ton-c">+4.1%</span></div>
              <div class="price" id="ton-p">$6.84</div>
            </div>
            <div class="card" onclick="copyTicker('SOL', '248.5')">
              <div class="header"><span class="title">◎ Solana</span><span class="change neg" id="sol-c">-0.8%</span></div>
              <div class="price" id="sol-p">$248.50</div>
            </div>
          </div>
          <script>
            function copyTicker(symbol, price) {
              if (window.ico) {
                window.ico.copy(symbol + ': $' + price);
                window.ico.toast(symbol + ' скопирован', 'doc.on.clipboard');
              }
            }
            async function fetchPrices() {
              try {
                const res = await fetch('https://api.binance.com/api/v3/ticker/24hr?symbols=[%22BTCUSDT%22,%22ETHUSDT%22,%22TONUSDT%22,%22SOLUSDT%22]');
                const data = await res.json();
                const map = {};
                data.forEach(item => { map[item.symbol] = item; });
                if (map['BTCUSDT']) updateUI('btc', map['BTCUSDT']);
                if (map['ETHUSDT']) updateUI('eth', map['ETHUSDT']);
                if (map['TONUSDT']) updateUI('ton', map['TONUSDT']);
                if (map['SOLUSDT']) updateUI('sol', map['SOLUSDT']);
              } catch(e) {}
            }
            function updateUI(id, data) {
              const p = parseFloat(data.lastPrice);
              const c = parseFloat(data.priceChangePercent);
              document.getElementById(id + '-p').innerText = '$' + p.toLocaleString('en-US', { minimumFractionDigits: p < 10 ? 2 : 0, maximumFractionDigits: 2 });
              const cEl = document.getElementById(id + '-c');
              cEl.innerText = (c >= 0 ? '+' : '') + c.toFixed(1) + '%';
              cEl.className = 'change ' + (c >= 0 ? 'pos' : 'neg');
            }
            fetchPrices();
            setInterval(fetchPrices, 10000);
          </script>
        </body>
        </html>
        """
    }
    
    private var weatherWidgetHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; user-select: none; }
            body { background: transparent; color: #fff; padding: 18px 20px; }
            .box { background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.06); border-radius: 14px; padding: 16px 20px; display: flex; justify-content: space-between; align-items: center; }
            .temp { font-size: 38px; font-weight: 700; line-height: 1; }
            .city { font-size: 15px; font-weight: 600; margin-bottom: 4px; color: #fff; }
            .desc { font-size: 12px; color: rgba(255,255,255,0.6); }
            .stats { display: flex; gap: 14px; text-align: right; font-size: 11.5px; color: rgba(255,255,255,0.7); }
            .val { font-weight: 600; color: #fff; font-size: 13px; }
          </style>
        </head>
        <body>
          <div class="box" onclick="window.ico && window.ico.toast('Погода обновлена', 'cloud.sun.fill')">
            <div>
              <div class="city" id="city">Мой город</div>
              <div class="desc" id="cond">Ясно · Комфортно</div>
            </div>
            <div class="temp" id="temp">+18°</div>
            <div class="stats">
              <div><div>Ветер</div><div class="val" id="wind">3 м/с</div></div>
              <div><div>Влажность</div><div class="val" id="hum">45%</div></div>
            </div>
          </div>
          <script>
            async function getWeather() {
              try {
                const res = await fetch('https://wttr.in/?format=j1');
                const data = await res.json();
                const cur = data.current_condition[0];
                const area = data.nearest_area[0];
                document.getElementById('temp').innerText = (parseInt(cur.temp_C) > 0 ? '+' : '') + cur.temp_C + '°';
                document.getElementById('city').innerText = area.areaName[0].value;
                document.getElementById('cond').innerText = cur.weatherDesc[0].value;
                document.getElementById('wind').innerText = Math.round(cur.windspeedKmph / 3.6) + ' м/с';
                document.getElementById('hum').innerText = cur.humidity + '%';
              } catch(e) {}
            }
            getWeather();
          </script>
        </body>
        </html>
        """
    }
    
    private var notesWidgetHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            body { background: transparent; color: #fff; padding: 14px 18px; height: 100vh; display: flex; flex-direction: column; }
            textarea { flex: 1; width: 100%; background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.07); border-radius: 12px; color: #fff; font-size: 13px; line-height: 1.5; padding: 14px; resize: none; outline: none; }
            textarea:focus { border-color: rgba(255,255,255,0.18); background: rgba(255,255,255,0.06); }
            .footer { display: flex; justify-content: space-between; align-items: center; padding-top: 8px; font-size: 11px; color: rgba(255,255,255,0.45); }
            .btn { background: rgba(255,255,255,0.1); border: none; color: #fff; padding: 4px 10px; border-radius: 6px; font-size: 11px; cursor: pointer; }
          </style>
        </head>
        <body>
          <textarea id="note" placeholder="Быстрые заметки, ссылки или мысли... (автосохранение)"></textarea>
          <div class="footer">
            <span id="status">Сохранено локально</span>
            <button class="btn" onclick="copyNote()">Скопировать всё</button>
          </div>
          <script>
            const noteEl = document.getElementById('note');
            noteEl.value = localStorage.getItem('ico_notes') || '';
            noteEl.addEventListener('input', () => {
              localStorage.setItem('ico_notes', noteEl.value);
              document.getElementById('status').innerText = 'Сохранено (' + noteEl.value.length + ' симв.)';
            });
            function copyNote() {
              if (window.ico && noteEl.value) {
                window.ico.copy(noteEl.value);
                window.ico.toast('Заметка скопирована', 'doc.on.clipboard');
              }
            }
          </script>
        </body>
        </html>
        """
    }
    
    private var todoWidgetHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif; user-select: none; }
            body { background: transparent; color: #fff; padding: 12px 16px; height: 100vh; display: flex; flex-direction: column; overflow: hidden; }
            .header { display: flex; gap: 8px; margin-bottom: 10px; }
            input[type="text"] {
              flex: 1; height: 32px; background: rgba(255,255,255,0.06);
              border: 1px solid rgba(255,255,255,0.09); border-radius: 9px;
              color: #fff; font-size: 12px; padding: 0 12px; outline: none;
              transition: border-color 0.15s, background 0.15s;
            }
            input[type="text"]:focus {
              background: rgba(255,255,255,0.09); border-color: rgba(255,255,255,0.22);
            }
            .add-btn {
              height: 32px; padding: 0 14px; background: #fff; color: #000;
              border: none; border-radius: 9px; font-size: 12px; font-weight: 600;
              cursor: pointer; transition: transform 0.1s, opacity 0.15s;
            }
            .add-btn:active { transform: scale(0.96); }
            .list {
              flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 6px; padding-right: 4px;
            }
            .list::-webkit-scrollbar { width: 4px; }
            .list::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 4px; }
            .item {
              display: flex; align-items: center; gap: 10px;
              padding: 8px 10px; background: rgba(255,255,255,0.035);
              border: 1px solid rgba(255,255,255,0.05); border-radius: 9px;
              transition: background 0.15s;
            }
            .item:hover { background: rgba(255,255,255,0.06); }
            .checkbox {
              width: 18px; height: 18px; border-radius: 6px;
              border: 1.5px solid rgba(255,255,255,0.3); display: flex;
              align-items: center; justify-content: center; cursor: pointer;
              flex-shrink: 0; transition: all 0.15s;
            }
            .item.done .checkbox {
              background: #10b981; border-color: #10b981;
            }
            .checkbox svg { display: none; width: 11px; height: 11px; stroke: #fff; stroke-width: 2.5; stroke-linecap: round; stroke-linejoin: round; fill: none; }
            .item.done .checkbox svg { display: block; }
            .item-text {
              flex: 1; font-size: 12px; color: rgba(255,255,255,0.9);
              line-height: 1.3; word-break: break-word; user-select: text; cursor: pointer;
            }
            .item.done .item-text {
              text-decoration: line-through; color: rgba(255,255,255,0.35);
            }
            .del-btn {
              width: 20px; height: 20px; border: none; background: transparent;
              color: rgba(255,255,255,0.3); font-size: 13px; cursor: pointer;
              display: flex; align-items: center; justify-content: center;
              border-radius: 5px; opacity: 0; transition: opacity 0.15s, color 0.15s;
            }
            .item:hover .del-btn { opacity: 1; }
            .del-btn:hover { color: #f43f5e; }
            .empty-msg {
              text-align: center; color: rgba(255,255,255,0.35); font-size: 11.5px;
              margin: auto 0; padding: 20px;
            }
            .footer {
              display: flex; justify-content: space-between; align-items: center;
              padding-top: 8px; font-size: 10.5px; color: rgba(255,255,255,0.45);
              border-top: 1px solid rgba(255,255,255,0.06); margin-top: 6px;
            }
            .clean-btn {
              background: transparent; border: none; color: rgba(255,255,255,0.5);
              font-size: 10.5px; cursor: pointer; text-decoration: underline;
            }
            .clean-btn:hover { color: rgba(255,255,255,0.85); }
          </style>
        </head>
        <body>
          <div class="header">
            <input type="text" id="task-input" placeholder="Добавить задачу (нажми Enter)..." />
            <button class="add-btn" onclick="addTask()">Добавить</button>
          </div>
          <div class="list" id="task-list"></div>
          <div class="footer">
            <span id="counter">0 задач</span>
            <button class="clean-btn" onclick="clearDone()">Очистить выполненные</button>
          </div>
          <script>
            let todos = [];
            try {
              const saved = localStorage.getItem('ico_todos');
              if (saved) todos = JSON.parse(saved);
            } catch(e) {}

            const input = document.getElementById('task-input');
            const listEl = document.getElementById('task-list');
            const counterEl = document.getElementById('counter');

            input.addEventListener('keydown', (e) => {
              if (e.key === 'Enter') addTask();
            });

            function save() {
              try {
                localStorage.setItem('ico_todos', JSON.stringify(todos));
                if (window.ico && window.ico.storage) {
                  window.ico.storage.set('todos', todos);
                }
              } catch(e) {}
              render();
            }

            function addTask() {
              const text = input.value.trim();
              if (!text) return;
              todos.unshift({ id: Date.now(), text: text, done: false });
              input.value = '';
              save();
            }

            function toggleTask(id) {
              const item = todos.find(t => t.id === id);
              if (!item) return;
              item.done = !item.done;
              if (item.done && window.ico && window.ico.sound) {
                window.ico.sound('Ping');
              }
              save();
              const allDone = todos.length > 0 && todos.every(t => t.done);
              if (allDone && window.ico && window.ico.toast) {
                window.ico.toast('Все задачи выполнены! 🎉', 'checkmark.circle.fill');
              }
            }

            function deleteTask(id) {
              todos = todos.filter(t => t.id !== id);
              save();
            }

            function clearDone() {
              const countBefore = todos.length;
              todos = todos.filter(t => !t.done);
              if (todos.length !== countBefore) {
                save();
                if (window.ico && window.ico.toast) {
                  window.ico.toast('Выполненные задачи удалены', 'trash');
                }
              }
            }

            function render() {
              listEl.innerHTML = '';
              if (todos.length === 0) {
                listEl.innerHTML = '<div class="empty-msg">Список пуст. Напиши задачу выше, чтобы не забыть! ✍️</div>';
                counterEl.innerText = '0 задач';
                return;
              }
              const doneCount = todos.filter(t => t.done).length;
              counterEl.innerText = doneCount + ' из ' + todos.length + ' выполнено';

              todos.forEach(t => {
                const row = document.createElement('div');
                row.className = 'item' + (t.done ? ' done' : '');
                row.innerHTML = `
                  <div class="checkbox" onclick="toggleTask(${t.id})">
                    <svg viewBox="0 0 12 10"><polyline points="1.5 5 4.5 8 10.5 2"></polyline></svg>
                  </div>
                  <div class="item-text" onclick="toggleTask(${t.id})">${escapeHtml(t.text)}</div>
                  <button class="del-btn" onclick="deleteTask(${t.id})" title="Удалить">✕</button>
                `;
                listEl.appendChild(row);
              });
            }

            function escapeHtml(str) {
              return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
            }

            render();
          </script>
        </body>
        </html>
        """
    }
    
    private var worldClockWidgetHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; user-select: none; }
            body { background: transparent; color: #fff; padding: 16px 20px; }
            .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
            .card { background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.06); border-radius: 12px; padding: 12px; text-align: center; }
            .city { font-size: 11px; font-weight: 500; color: rgba(255,255,255,0.5); margin-bottom: 6px; }
            .time { font-size: 17px; font-weight: 700; font-variant-numeric: tabular-nums; }
          </style>
        </head>
        <body>
          <div class="grid">
            <div class="card"><div class="city">Москва</div><div class="time" id="t-msk">--:--</div></div>
            <div class="card"><div class="city">Лондон</div><div class="time" id="t-lon">--:--</div></div>
            <div class="card"><div class="city">Нью-Йорк</div><div class="time" id="t-nyc">--:--</div></div>
            <div class="card"><div class="city">Токио</div><div class="time" id="t-tyo">--:--</div></div>
          </div>
          <script>
            function updateClocks() {
              const now = new Date();
              document.getElementById('t-msk').innerText = now.toLocaleTimeString('ru-RU', { timeZone: 'Europe/Moscow', hour: '2-digit', minute: '2-digit' });
              document.getElementById('t-lon').innerText = now.toLocaleTimeString('en-GB', { timeZone: 'Europe/London', hour: '2-digit', minute: '2-digit' });
              document.getElementById('t-nyc').innerText = now.toLocaleTimeString('en-US', { timeZone: 'America/New_York', hour: '2-digit', minute: '2-digit' });
              document.getElementById('t-tyo').innerText = now.toLocaleTimeString('ja-JP', { timeZone: 'Asia/Tokyo', hour: '2-digit', minute: '2-digit' });
            }
            updateClocks();
            setInterval(updateClocks, 1000);
          </script>
        </body>
        </html>
        """
    }
    
    private var screenRulerWidgetHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif; user-select: none; }
            body { background: transparent; color: #fff; padding: 14px 18px; }
            .header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }
            .title-group { display: flex; align-items: center; gap: 8px; }
            .title { font-size: 13.5px; font-weight: 600; color: #fff; }
            .sub { font-size: 10px; color: rgba(255,255,255,0.45); }
            .measure-btn {
              background: linear-gradient(135deg, #00d2ff 0%, #007aff 100%);
              color: #fff;
              border: none;
              border-radius: 9px;
              padding: 7px 15px;
              font-size: 11.5px;
              font-weight: 600;
              cursor: pointer;
              display: flex;
              align-items: center;
              gap: 6px;
              box-shadow: 0 4px 12px rgba(0,122,255,0.3);
              transition: all 0.15s ease;
            }
            .measure-btn:hover { transform: scale(1.02); filter: brightness(1.1); }
            .measure-btn:active { transform: scale(0.97); }
            .main-card {
              background: rgba(255,255,255,0.04);
              border: 1px solid rgba(255,255,255,0.08);
              border-radius: 14px;
              padding: 13px 15px;
              min-height: 118px;
            }
            .hero-row { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 8px; }
            .hero-size { font-size: 26px; font-weight: 700; font-variant-numeric: tabular-nums; letter-spacing: -0.5px; color: #fff; }
            .hero-unit { font-size: 12.5px; font-weight: 500; color: #00d2ff; margin-left: 4px; }
            .chips-row { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 11px; }
            .chip {
              background: rgba(255,255,255,0.06);
              border: 1px solid rgba(255,255,255,0.08);
              border-radius: 7px;
              padding: 4px 8px;
              font-size: 10.5px;
              font-variant-numeric: tabular-nums;
              color: rgba(255,255,255,0.85);
            }
            .chip b { color: #00d2ff; font-weight: 600; margin-right: 3px; }
            .actions-row { display: flex; gap: 6px; flex-wrap: wrap; }
            .act-btn {
              background: rgba(255,255,255,0.07);
              border: 1px solid rgba(255,255,255,0.09);
              border-radius: 7px;
              padding: 5px 10px;
              font-size: 10.5px;
              font-weight: 500;
              color: rgba(255,255,255,0.9);
              cursor: pointer;
              transition: all 0.15s ease;
            }
            .act-btn:hover { background: rgba(255,255,255,0.15); color: #fff; }
            .act-btn:active { transform: scale(0.96); }
            .empty-state {
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
              text-align: center;
              padding: 18px 10px;
              color: rgba(255,255,255,0.5);
            }
            .empty-state .icon { font-size: 24px; margin-bottom: 6px; opacity: 0.8; }
            .empty-state .txt { font-size: 11.5px; font-weight: 500; margin-bottom: 2px; color: rgba(255,255,255,0.7); }
            .empty-state .sub { font-size: 10px; opacity: 0.6; }
            .history-section { margin-top: 10px; }
            .history-title { font-size: 9.5px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: rgba(255,255,255,0.4); margin-bottom: 6px; }
            .history-list { display: flex; gap: 6px; overflow-x: auto; padding-bottom: 2px; }
            .history-item {
              background: rgba(255,255,255,0.05);
              border: 1px solid rgba(255,255,255,0.06);
              border-radius: 7px;
              padding: 4px 9px;
              font-size: 10.5px;
              font-variant-numeric: tabular-nums;
              color: rgba(255,255,255,0.75);
              cursor: pointer;
              white-space: nowrap;
              transition: all 0.15s;
            }
            .history-item:hover { background: rgba(0,210,255,0.15); border-color: rgba(0,210,255,0.3); color: #fff; }
          </style>
        </head>
        <body>
          <div class="header">
            <div class="title-group">
              <span style="font-size: 16px;">📐</span>
              <div>
                <div class="title">Экранная линейка</div>
                <div class="sub">Замер пикселей на экране · Esc для отмены</div>
              </div>
            </div>
            <button class="measure-btn" onclick="startMeasure()">
              <span>📐</span>
              <span>Замерить область</span>
            </button>
          </div>

          <div class="main-card" id="card-content">
            <div class="empty-state">
              <div class="icon">📏</div>
              <div class="txt">Замер ещё не выполнялся</div>
              <div class="sub">Нажмите «Замерить область» и потяните рамку на экране</div>
            </div>
          </div>

          <div class="history-section" id="history-section" style="display: none;">
            <div class="history-title">Недавние замеры</div>
            <div class="history-list" id="history-list"></div>
          </div>

          <script>
            let current = null;
            let history = [];

            try {
              history = window.ico.storage.get('ruler_history', []) || [];
            } catch(e) {
              history = [];
            }

            if (history.length > 0) {
              setCurrent(history[0], false);
              renderHistory();
            }

            async function startMeasure() {
              try {
                const res = await window.ico.measure();
                if (!res) return;
                setCurrent(res, true);
                saveToHistory(res);
                window.ico.toast(res.width + ' × ' + res.height + ' px', 'ruler.fill');
                window.ico.sound('Glass');
              } catch(e) {
                console.error(e);
              }
            }

            function setCurrent(data, animate) {
              current = data;
              const card = document.getElementById('card-content');
              card.innerHTML = `
                <div class="hero-row">
                  <div>
                    <span class="hero-size">${Math.round(data.width)} × ${Math.round(data.height)}</span>
                    <span class="hero-unit">px</span>
                  </div>
                </div>
                <div class="chips-row">
                  <div class="chip"><b>Диагональ:</b> ${Math.round(data.diagonal)} px</div>
                  <div class="chip"><b>Пропорции:</b> ${data.aspectRatio}</div>
                  <div class="chip"><b>Retina (@${data.scale}x):</b> ${Math.round(data.retinaWidth)} × ${Math.round(data.retinaHeight)} px</div>
                  <div class="chip"><b>Позиция:</b> X:${Math.round(data.x)} Y:${Math.round(data.y)}</div>
                </div>
                <div class="actions-row">
                  <button class="act-btn" onclick="copyValue('${Math.round(data.width)}x${Math.round(data.height)}', '${Math.round(data.width)}×${Math.round(data.height)}')">📋 WxH</button>
                  <button class="act-btn" onclick="copyValue('width: ${Math.round(data.width)}px; height: ${Math.round(data.height)}px;', 'CSS')">📋 CSS</button>
                  <button class="act-btn" onclick="copyValue('w-[${Math.round(data.width)}px] h-[${Math.round(data.height)}px]', 'Tailwind')">📋 Tailwind</button>
                  <button class="act-btn" onclick="copyValue(JSON.stringify(current, null, 2), 'JSON')">📋 JSON</button>
                </div>
              `;
            }

            function copyValue(val, label) {
              window.ico.copy(val);
              window.ico.toast('Скопировано: ' + label, 'checkmark');
            }

            function saveToHistory(item) {
              history = [item, ...history.filter(h => !(h.width === item.width && h.height === item.height))].slice(0, 6);
              try {
                window.ico.storage.set('ruler_history', history);
              } catch(e){}
              renderHistory();
            }

            function renderHistory() {
              const sec = document.getElementById('history-section');
              const list = document.getElementById('history-list');
              if (!history || history.length === 0) {
                sec.style.display = 'none';
                return;
              }
              sec.style.display = 'block';
              list.innerHTML = history.map((h, i) => `
                <div class="history-item" onclick="setCurrent(history[${i}], false)">
                  ${Math.round(h.width)} × ${Math.round(h.height)} px <span style="opacity: 0.5;">(${h.aspectRatio})</span>
                </div>
              `).join('');
            }
          </script>
        </body>
        </html>
        """
    }
}
