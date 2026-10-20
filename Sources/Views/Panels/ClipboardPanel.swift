import SwiftUI

public struct ClipboardPanel: View {
    @Bindable var state: IslandState
    
    public init(state: IslandState) {
        self.state = state
    }
    
    public var body: some View {
        VStack(spacing: 13) {
            // Search Bar & Count
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.44))
                    
                    TextField("Поиск в буфере", text: $state.clipQuery)
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
                Text("Нажмите на фрагмент, чтобы скопировать обратно")
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
        .frame(width: 604)
    }
}

private struct RealClipRowView: View {
    let clip: RealClipItem
    let isCopied: Bool
    let onTap: () -> Void
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
            
            // Right actions: Copy status chip + Delete button
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
        case .mail: return Color(red: 0.19, green: 0.15, blue: 0.11)
        }
    }
    
    private var badgeIconColor: Color {
        switch clip.kind {
        case .text: return Color(red: 0.67, green: 0.66, blue: 0.73)
        case .link: return Color(red: 0.52, green: 0.69, blue: 0.88)
        case .mail: return Color(red: 0.85, green: 0.71, blue: 0.55)
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
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
