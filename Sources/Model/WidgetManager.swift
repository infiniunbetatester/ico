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

@MainActor
@Observable
public final class WidgetManager {
    public static let shared = WidgetManager()
    
    public var installedWidgets: [CustomWidgetInfo] = []
    public var activeWidgetId: String?
    
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
            try? fm.createDirectory(at: cryptoDir, withIntermediateDirectories: true)
            seedCryptoWidget(at: cryptoDir)
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
    
    public func createSampleWidget() {
        let dir = widgetsDirectory
        let sampleName = "widget-\(Int(Date().timeIntervalSince1970) % 10000)"
        let sampleDir = dir.appendingPathComponent(sampleName, isDirectory: true)
        try? FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        
        let jsonContent = """
        {
          "name": "Новый виджет",
          "icon": "sparkles",
          "description": "Шаблон HTML + JS",
          "height": 240
        }
        """
        try? jsonContent.write(to: sampleDir.appendingPathComponent("widget.json"), atomically: true, encoding: .utf8)
        
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; user-select: none; }
            body { background: transparent; color: #fff; padding: 18px; }
            .card { background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.08); border-radius: 14px; padding: 16px; text-align: center; }
            h2 { font-size: 16px; font-weight: 600; margin-bottom: 6px; }
            p { font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 14px; }
            button { background: #fff; color: #000; border: none; padding: 8px 16px; border-radius: 9px; font-size: 12px; font-weight: 600; cursor: pointer; transition: transform 0.1s; }
            button:active { transform: scale(0.96); }
          </style>
        </head>
        <body>
          <div class="card">
            <h2>✨ Твой собственный виджет</h2>
            <p>Редактируй index.html в этой папке!</p>
            <button onclick="window.ico.toast('Привет из JS!', 'sparkles')">Кликни меня</button>
          </div>
        </body>
        </html>
        """
        try? htmlContent.write(to: sampleDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        
        reloadWidgets()
        activeWidgetId = sampleName
        openWidgetsFolderInFinder()
    }
    
    // MARK: - Default Starter Crypto Widget
    private func seedCryptoWidget(at dir: URL) {
        let json = """
        {
          "name": "Криптовалюты",
          "icon": "bitcoinsign.circle.fill",
          "description": "Курсы BTC, ETH, TON, SOL в реальном времени",
          "height": 260
        }
        """
        try? json.write(to: dir.appendingPathComponent("widget.json"), atomically: true, encoding: .utf8)
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; user-select: none; }
            body { background: transparent; color: #fff; padding: 10px 16px; }
            .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
            .title { font-size: 13px; font-weight: 600; color: rgba(255,255,255,0.9); }
            .badge { font-size: 10px; color: #6ee7b7; background: rgba(110,231,183,0.12); padding: 3px 8px; border-radius: 6px; font-weight: 500; }
            .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
            .coin-card { background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.07); border-radius: 12px; padding: 12px 14px; cursor: pointer; transition: all 0.15s ease; }
            .coin-card:hover { background: rgba(255,255,255,0.09); transform: translateY(-1px); }
            .coin-top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
            .symbol { font-size: 13px; font-weight: 700; }
            .change { font-size: 10.5px; font-weight: 600; }
            .positive { color: #4ade80; }
            .negative { color: #f87171; }
            .price { font-size: 16px; font-weight: 600; font-variant-numeric: tabular-nums; }
            .hint { font-size: 9.5px; color: rgba(255,255,255,0.35); text-align: center; margin-top: 10px; }
          </style>
        </head>
        <body>
          <div class="header">
            <span class="title">Рынок крипто (Binance Live)</span>
            <span class="badge" id="status">Обновлено</span>
          </div>
          
          <div class="grid" id="coins">
            <div class="coin-card" onclick="copyCoin('BTC', '$91,420')">
              <div class="coin-top"><span class="symbol">BTC / USDT</span><span class="change positive" id="btc-c">+2.4%</span></div>
              <div class="price" id="btc-p">$91,420</div>
            </div>
            <div class="coin-card" onclick="copyCoin('ETH', '$3,180')">
              <div class="coin-top"><span class="symbol">ETH / USDT</span><span class="change positive" id="eth-c">+1.8%</span></div>
              <div class="price" id="eth-p">$3,180</div>
            </div>
            <div class="coin-card" onclick="copyCoin('TON', '$5.42')">
              <div class="coin-top"><span class="symbol">TON / USDT</span><span class="change positive" id="ton-c">+4.1%</span></div>
              <div class="price" id="ton-p">$5.42</div>
            </div>
            <div class="coin-card" onclick="copyCoin('SOL', '$184.20')">
              <div class="coin-top"><span class="symbol">SOL / USDT</span><span class="change negative" id="sol-c">-0.8%</span></div>
              <div class="price" id="sol-p">$184.20</div>
            </div>
          </div>
          
          <div class="hint">Кликните на карточку, чтобы скопировать цену в буфер macOS</div>

          <script>
            async function fetchRates() {
              try {
                const res = await fetch('https://api.binance.com/api/v3/ticker/24hr?symbols=["BTCUSDT","ETHUSDT","TONUSDT","SOLUSDT"]');
                const data = await res.json();
                data.forEach(item => {
                  const p = parseFloat(item.lastPrice);
                  const c = parseFloat(item.priceChangePercent);
                  const pFormatted = p > 100 ? '$' + p.toLocaleString('en-US', {maximumFractionDigits: 1}) : '$' + p.toFixed(2);
                  const cFormatted = (c >= 0 ? '+' : '') + c.toFixed(2) + '%';
                  const cClass = c >= 0 ? 'change positive' : 'change negative';
                  
                  if (item.symbol === 'BTCUSDT') updateCoin('btc', pFormatted, cFormatted, cClass);
                  if (item.symbol === 'ETHUSDT') updateCoin('eth', pFormatted, cFormatted, cClass);
                  if (item.symbol === 'TONUSDT') updateCoin('ton', pFormatted, cFormatted, cClass);
                  if (item.symbol === 'SOLUSDT') updateCoin('sol', pFormatted, cFormatted, cClass);
                });
                document.getElementById('status').innerText = new Date().toLocaleTimeString([], {hour: '2-digit', minute:'2-digit', second:'2-digit'});
              } catch(e) {}
            }
            
            function updateCoin(id, p, c, cClass) {
              const pEl = document.getElementById(id + '-p');
              const cEl = document.getElementById(id + '-c');
              if (pEl) pEl.innerText = p;
              if (cEl) { cEl.innerText = c; cEl.className = cClass; }
            }
            
            function copyCoin(symbol, price) {
              const text = symbol + ': ' + price;
              if (window.ico) {
                window.ico.copy(text);
                window.ico.toast('Скопировано: ' + text, 'checkmark.circle.fill');
              } else {
                navigator.clipboard.writeText(text);
              }
            }
            
            fetchRates();
            setInterval(fetchRates, 10000);
          </script>
        </body>
        </html>
        """
        try? html.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
}
