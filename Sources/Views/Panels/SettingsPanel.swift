import SwiftUI

public struct SettingsPanel: View {
    @Bindable var state: IslandState
    @State private var telegram = TelegramSync.shared
    @State private var isTestingTelegram: Bool = false
    @State private var testSuccessMessage: String? = nil
    @State private var testErrorMessage: String? = nil
    
    public init(state: IslandState) {
        self.state = state
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Настройки ICO")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Персонализация челки, Telegram-мост и поведение окна")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    Spacer()
                    
                    Button {
                        withAnimation(IslandToolsStyle.spring) {
                            state.isSettingsOpen = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                            Text("Закрыть")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(Color.white.opacity(0.75))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                
                // Section 1: Compact Notch Appearance
                settingsCard(title: "Размер и стиль компактной челки", icon: "macbook.and.iphone") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            ForEach(CompactStyle.allCases) { style in
                                let isSelected = state.compactStyle == style
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        state.setCompactStyle(style)
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Text(styleTitle(style))
                                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                            .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                                        
                                        Text(styleSubtitle(style))
                                            .font(.system(size: 9.5))
                                            .foregroundColor(isSelected ? Color.black.opacity(0.7) : Color.white.opacity(0.45))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? Color.white : Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Text("Совет: если выбрать «Невидимая», полоска скроется и появится только когда вы подведете курсор к вырезу экрана.")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.4))
                            .padding(.top, 2)
                    }
                }
                
                // Section 2: Window Behavior
                settingsCard(title: "Поведение окна", icon: "macwindow.on.rectangle") {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Поверх всех окон (Always on Top)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Text(state.isAlwaysOnTop
                                 ? "Челка закреплена поверх всех приложений, рабочего стола и полноэкранных окон."
                                 : "Челка больше не загораживает другие приложения и не перекрывает полноэкранные окна.")
                                .font(.system(size: 10.5))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $state.isAlwaysOnTop)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                
                // Section 2.5: Touch Bar Behavior
                settingsCard(title: "Панель Touch Bar", icon: "menubar.rectangle") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Постоянный Touch Bar (Всегда активен)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                Text(state.isTouchBarPersistent
                                     ? "Тачбар ICO работает постоянно, даже когда остров свёрнут (системный Control Strip справа сохраняется)."
                                     : "Тачбар активируется только при раскрытии острова или клике на него.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Color.white.opacity(0.5))
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $state.isTouchBarPersistent)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Раскрывать челку при нажатии на Touch Bar")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                Text(state.expandOnTouchBarTap
                                     ? "При переключении вкладок на тачбаре челка на экране автоматически открывается."
                                     : "Тачбар работает автономно: челка на экране не выскакивает (её можно открыть кнопкой ⌃ слева на тачбаре).")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Color.white.opacity(0.5))
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $state.expandOnTouchBarTap)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }
                
                // Section 3: Telegram Sync
                settingsCard(title: "Синхронизация буфера с Telegram", icon: "paperplane.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Отправляйте текст, ссылки и изображения из буфера обмена Mac на свой телефон в 1 клик.")
                            .font(.system(size: 10.5))
                            .foregroundColor(Color.white.opacity(0.6))
                        
                        // Bot Token Input
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Telegram Bot Token:")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.75))
                            
                            HStack {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.35))
                                TextField("123456789:ABCDefGhIJKlmNoPQRsTUVwxyZ...", text: $telegram.botToken)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        
                        // Chat ID Input
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ваш Chat ID (или ID канала/группы):")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.75))
                            
                            HStack {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.35))
                                TextField("123456789", text: $telegram.chatID)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        
                        // Test Button & Instructions
                        HStack(spacing: 10) {
                            Button {
                                testTelegramConnection()
                            } label: {
                                HStack(spacing: 5) {
                                    if isTestingTelegram {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 11))
                                    }
                                    Text("Проверить отправку")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .frame(height: 29)
                                .background(telegram.isConfigured ? Color.white : Color.white.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(!telegram.isConfigured || isTestingTelegram)
                            
                            if let success = testSuccessMessage {
                                Text(success)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(Color(red: 0.6, green: 0.88, blue: 0.68))
                            } else if let error = testErrorMessage {
                                Text(error)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.45))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.top, 2)
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        HStack(spacing: 12) {
                            Text("Как настроить за 1 минуту:")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.5))
                            
                            Button {
                                if let url = URL(string: "https://t.me/BotFather") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Text("1. Создать бота (@BotFather)")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(.cyan)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                if let url = URL(string: "https://t.me/userinfobot") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Text("2. Узнать свой ID (@userinfobot)")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(.cyan)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Section 4: Widgets & Dev
                settingsCard(title: "Виджеты и расширения", icon: "puzzlepiece.extension.fill") {
                    HStack(spacing: 10) {
                        Button {
                            WidgetManager.shared.openWidgetsFolderInFinder()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "folder.fill")
                                Text("Открыть папку ~/.ico/widgets")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            WidgetManager.shared.createCustomTemplate()
                            state.showToast("Создан шаблон виджета", icon: "sparkles")
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                Text("Создать свой виджет")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 640, height: 380)
    }
    
    private func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.85))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.92))
            }
            
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    private func styleTitle(_ style: CompactStyle) -> String {
        switch style {
        case .standard: return "24px Стандарт"
        case .minimal: return "6px Тонкая"
        case .hidden: return "0px Невидимая"
        }
    }
    
    private func styleSubtitle(_ style: CompactStyle) -> String {
        switch style {
        case .standard: return "Классический остров"
        case .minimal: return "Ультратонкая черта"
        case .hidden: return "Только при наведении"
        }
    }
    
    private func testTelegramConnection() {
        isTestingTelegram = true
        testSuccessMessage = nil
        testErrorMessage = nil
        
        Task {
            do {
                try await telegram.sendTestMessage()
                testSuccessMessage = "Тест успешно отправлен! Проверьте Telegram 📱"
                state.showToast("Telegram подключен!", icon: "paperplane.fill")
            } catch {
                testErrorMessage = error.localizedDescription
                state.showToast("Ошибка: проверьте токен", icon: "exclamationmark.triangle.fill")
            }
            isTestingTelegram = false
        }
    }
}
