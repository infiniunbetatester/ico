import SwiftUI

public struct ClipboardPanel: View {
    @Bindable var state: IslandState
    
    public init(state: IslandState) {
        self.state = state
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Search & Tools Bar
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.53))
                    
                    TextField("Поиск в буфере обмена...", text: $state.clipQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.89, green: 0.89, blue: 0.91))
                }
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(Color(red: 0.1, green: 0.1, blue: 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                let filteredCount = state.clips.filter {
                    state.clipQuery.isEmpty || $0.text.localizedCaseInsensitiveContains(state.clipQuery)
                }.count
                
                Text("\(filteredCount) записей")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.43))
                
                if !state.clips.isEmpty {
                    // Quick Send to Telegram
                    Button {
                        if let first = state.clips.first {
                            sendClipToTelegram(text: first.text)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 9))
                            Text("В Telegram")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Color.cyan)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.cyan.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Отправить последний скопированный текст в Telegram")
                    
                    Button {
                        state.clearAllClips()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 9.5))
                            Text("Очистить")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Color(red: 0.85, green: 0.4, blue: 0.4))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Очистить всю историю буфера")
                }
            }
            .frame(height: 32)
            
            // Real Clipboard Items List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 7) {
                    let filtered = state.clips.filter {
                        state.clipQuery.isEmpty || $0.text.localizedCaseInsensitiveContains(state.clipQuery)
                    }
                    
                    if filtered.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 20))
                                .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.43))
                            Text("Скопируйте любой текст или ссылку (⌘C)")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.43))
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ForEach(filtered) { clip in
                            RealClipRowView(
                                clip: clip,
                                isCopied: state.copiedClipId == clip.id,
                                onTap: {
                                    state.copyClipToPasteboard(id: clip.id)
                                },
                                onSendTelegram: {
                                    sendClipToTelegram(text: clip.text)
                                },
                                onDelete: {
                                    state.removeClip(id: clip.id)
                                }
                            )
                        }
                    }
                }
            }
            .frame(height: 220)
            
            // Footer
            HStack {
                Text("Нажмите на строку чтобы скопировать, или ✈️ чтобы отправить на телефон в Telegram")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(red: 0.37, green: 0.37, blue: 0.4))
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("Реальный буфер macOS")
                        .font(.system(size: 9.5))
                }
                .foregroundColor(Color(red: 0.37, green: 0.37, blue: 0.4))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .frame(width: 640)
    }
    
    private func sendClipToTelegram(text: String) {
        guard !text.isEmpty else { return }
        let tg = TelegramSync.shared
        if !tg.isConfigured {
            state.showToast("Настройте Telegram в Настройках ⚙️", icon: "exclamationmark.triangle.fill")
            withAnimation(IslandToolsStyle.spring) {
                state.isSettingsOpen = true
            }
            return
        }
        
        Task {
            do {
                try await tg.sendText(text)
                state.showToast("Отправлено в Telegram ✈️", icon: "paperplane.fill")
            } catch {
                state.showToast("Ошибка Telegram: \(error.localizedDescription)", icon: "exclamationmark.circle.fill")
            }
        }
    }
}

private struct RealClipRowView: View {
    let clip: RealClipItem
    let isCopied: Bool
    let onTap: () -> Void
    let onSendTelegram: () -> Void
    let onDelete: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 11) {
            // Main clickable content area
            Button(action: onTap) {
                HStack(spacing: 11) {
                    // Type Icon Badge
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(badgeColor)
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: badgeIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(badgeIconColor)
                    }
                    
                    // Text Content
                    VStack(alignment: .leading, spacing: 3) {
                        Text(clip.text)
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(red: 0.87, green: 0.87, blue: 0.89))
                            .lineLimit(1)
                        
                        Text(formattedTime(clip.date))
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.43))
                    }
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Right actions: Copy status chip + Telegram button + Delete button
            HStack(spacing: 6) {
                Button(action: onTap) {
                    HStack(spacing: 5) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        if isCopied {
                            Text("Скопировано")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                    }
                    .foregroundColor(isCopied ? Color(red: 0.63, green: 0.83, blue: 0.7) : Color(red: 0.47, green: 0.47, blue: 0.5))
                    .padding(.horizontal, isCopied ? 10 : 8)
                    .frame(height: 29)
                    .background(isCopied ? Color(red: 0.12, green: 0.21, blue: 0.16) : Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: isCopied ? 11 : 9, style: .continuous))
                }
                .buttonStyle(.plain)
                
                // Telegram forward button
                Button(action: onSendTelegram) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(isHovered ? Color.cyan : Color.white.opacity(0.2))
                        .frame(width: 28, height: 28)
                        .background(isHovered ? Color.cyan.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Отправить эту запись в Telegram на телефон")
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundColor(isHovered ? Color(red: 0.85, green: 0.4, blue: 0.4) : Color.white.opacity(0.2))
                        .frame(width: 28, height: 28)
                        .background(isHovered ? Color.red.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Удалить запись из истории")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 56)
        .background(isHovered ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(red: 0.08, green: 0.08, blue: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { isHovered = $0 }
    }
    
    private var badgeColor: Color {
        switch clip.kind {
        case .text: return Color(red: 0.14, green: 0.14, blue: 0.16)
        case .link: return Color(red: 0.1, green: 0.15, blue: 0.21)
        case .mail: return Color(red: 0.12, green: 0.18, blue: 0.16)
        }
    }
    
    private var badgeIconColor: Color {
        switch clip.kind {
        case .text: return Color(red: 0.65, green: 0.65, blue: 0.7)
        case .link: return Color(red: 0.4, green: 0.65, blue: 0.95)
        case .mail: return Color(red: 0.4, green: 0.8, blue: 0.65)
        }
    }
    
    private var badgeIcon: String {
        switch clip.kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .mail: return "envelope.fill"
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
