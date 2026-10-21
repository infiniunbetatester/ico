import Foundation
import AppKit
import Observation

@MainActor
@Observable
public final class TelegramSync {
    public static let shared = TelegramSync()
    
    private let tokenKey = "ico_telegram_bot_token"
    private let chatIdKey = "ico_telegram_chat_id"
    
    public var botToken: String {
        didSet {
            UserDefaults.standard.set(botToken, forKey: tokenKey)
        }
    }
    
    public var chatID: String {
        didSet {
            UserDefaults.standard.set(chatID, forKey: chatIdKey)
        }
    }
    
    public var isSending: Bool = false
    public var lastStatus: String? = nil
    
    public var isConfigured: Bool {
        !botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private init() {
        self.botToken = UserDefaults.standard.string(forKey: tokenKey) ?? ""
        self.chatID = UserDefaults.standard.string(forKey: chatIdKey) ?? ""
    }
    
    /// Отправка текста или ссылки в Telegram
    public func sendText(_ text: String) async throws {
        let token = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let chat = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !token.isEmpty, !chat.isEmpty else {
            throw NSError(domain: "TelegramSync", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Укажите Bot Token и Chat ID в Настройках ⚙️"
            ])
        }
        
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw NSError(domain: "TelegramSync", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Неверный формат Bot Token"
            ])
        }
        
        isSending = true
        defer { isSending = false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        
        let payload: [String: Any] = [
            "chat_id": chat,
            "text": text,
            "disable_web_page_preview": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorText = parseTelegramError(data: data)
            throw NSError(domain: "TelegramSync", code: 500, userInfo: [
                NSLocalizedDescriptionKey: errorText
            ])
        }
        
        lastStatus = "Отправлено успешно"
    }
    
    /// Отправка изображения в Telegram
    public func sendImage(_ image: NSImage) async throws {
        let token = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let chat = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !token.isEmpty, !chat.isEmpty else {
            throw NSError(domain: "TelegramSync", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Укажите Bot Token и Chat ID в Настройках ⚙️"
            ])
        }
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TelegramSync", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Не удалось подготовить изображение для отправки"
            ])
        }
        
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendPhoto") else {
            throw NSError(domain: "TelegramSync", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Неверный формат Bot Token"
            ])
        }
        
        isSending = true
        defer { isSending = false }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        
        var body = Data()
        // chat_id
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(chat)\r\n".data(using: .utf8)!)
        
        // caption
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
        body.append("Изображение из буфера обмена ICO 🏝\r\n".data(using: .utf8)!)
        
        // photo file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"clipboard.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(pngData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorText = parseTelegramError(data: data)
            throw NSError(domain: "TelegramSync", code: 500, userInfo: [
                NSLocalizedDescriptionKey: errorText
            ])
        }
        
        lastStatus = "Картинка отправлена"
    }
    
    /// Тестовая отправка сообщения для проверки конфигурации
    public func sendTestMessage() async throws {
        try await sendText("🔔 ICO Dynamic Island: Связь с Telegram успешно настроена! Буфер обмена Mac подключен к вашему телефону.")
    }
    
    private func parseTelegramError(data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let desc = json["description"] as? String {
            return "Telegram: \(desc)"
        }
        return "Ошибка соединения с Telegram API"
    }
}
