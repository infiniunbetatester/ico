import Foundation
import AppKit
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
        
        let cryptoDir = dir.appendingPathComponent("crypto-ticker", isDirectory: true)
        if !fm.fileExists(atPath: cryptoDir.path) {
            if let storeCrypto = availableStoreWidgets.first(where: { $0.id == "crypto-ticker" }) {
                installStoreWidget(storeCrypto)
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
                id: "pomodoro-focus",
                name: "Pomodoro Focus",
                iconName: "timer",
                description: "Таймер глубокой фокусировки 25/5 минут с визуальным кольцом прогресса.",
                category: "Утилиты",
                defaultHeight: 260,
                htmlContent: pomodoroWidgetHTML,
                widgetJson: """
                {
                  "name": "Pomodoro Focus",
                  "icon": "timer",
                  "description": "Таймер продуктивности 25/5",
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
    
    private var pomodoroWidgetHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; user-select: none; }
            body { background: transparent; color: #fff; padding: 18px; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; }
            .timer { font-size: 44px; font-weight: 700; font-variant-numeric: tabular-nums; margin-bottom: 12px; letter-spacing: -1px; }
            .buttons { display: flex; gap: 8px; }
            .btn { background: #fff; color: #000; border: none; padding: 8px 18px; border-radius: 10px; font-size: 12px; font-weight: 600; cursor: pointer; }
            .btn-sec { background: rgba(255,255,255,0.1); color: #fff; }
          </style>
        </head>
        <body>
          <div class="timer" id="time">25:00</div>
          <div class="buttons">
            <button class="btn" id="start-btn" onclick="toggle()">Старт</button>
            <button class="btn btn-sec" onclick="reset()">Сброс</button>
          </div>
          <script>
            let sec = 25 * 60;
            let timer = null;
            function update() {
              const m = Math.floor(sec / 60);
              const s = sec % 60;
              document.getElementById('time').innerText = (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
            }
            function toggle() {
              if (timer) {
                clearInterval(timer);
                timer = null;
                document.getElementById('start-btn').innerText = 'Старт';
              } else {
                timer = setInterval(() => {
                  if (sec > 0) {
                    sec--;
                    update();
                  } else {
                    clearInterval(timer);
                    timer = null;
                    if (window.ico) window.ico.toast('Помодоро завершен! Время отдыха', 'timer');
                  }
                }, 1000);
                document.getElementById('start-btn').innerText = 'Пауза';
              }
            }
            function reset() {
              clearInterval(timer);
              timer = null;
              sec = 25 * 60;
              update();
              document.getElementById('start-btn').innerText = 'Старт';
            }
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
}
