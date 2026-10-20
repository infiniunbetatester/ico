import SwiftUI

public struct WidgetsPanel: View {
    @Bindable var state: IslandState
    @State private var manager = WidgetManager.shared
    @State private var reloadToken: UUID = UUID()
    
    public init(state: IslandState) {
        self.state = state
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header: Installed Widgets bar & Folder tools
            HStack(spacing: 8) {
                // Widget switcher pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(manager.installedWidgets) { widget in
                            let isSelected = manager.activeWidgetId == widget.id
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    manager.activeWidgetId = widget.id
                                    reloadToken = UUID()
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: widget.iconName)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(widget.name)
                                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .foregroundColor(isSelected ? Color.black : Color(red: 0.8, green: 0.8, blue: 0.84))
                                .background(isSelected ? Color.white : Color(red: 0.1, green: 0.1, blue: 0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Spacer(minLength: 4)
                
                // Actions: Reload, Add Template, Open Folder
                HStack(spacing: 5) {
                    Button {
                        reloadToken = UUID()
                        state.showToast("Виджет обновлен", icon: "arrow.clockwise")
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.75))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Перезагрузить текущий виджет")
                    
                    Button {
                        manager.createSampleWidget()
                        state.showToast("Создан шаблон виджета", icon: "sparkles")
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.75))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Создать новый шаблон виджета")
                    
                    Button {
                        manager.openWidgetsFolderInFinder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                            Text("Папка")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundColor(Color.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Открыть папку ~/.ico/widgets в Finder")
                }
            }
            .frame(height: 30)
            
            // Active Widget Content View
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.08))
                
                if let active = manager.installedWidgets.first(where: { $0.id == manager.activeWidgetId }) {
                    WidgetWebView(url: active.htmlURL, reloadToken: reloadToken)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(Color.white.opacity(0.35))
                        
                        Text("Нет установленных виджетов")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.7))
                        
                        Button {
                            manager.createSampleWidget()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                Text("Создать первый виджет")
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Color.black)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 236)
            
            // Footer Info
            HStack {
                if let active = manager.installedWidgets.first(where: { $0.id == manager.activeWidgetId }) {
                    Text(active.description)
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.49))
                }
                
                Spacer()
                
                Text("HTML · CSS · JS · window.ico API")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.43))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .frame(width: 640)
        .onAppear {
            manager.reloadWidgets()
        }
    }
}
