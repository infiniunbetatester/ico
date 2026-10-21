import SwiftUI

public struct WidgetsPanel: View {
    @Bindable var state: IslandState
    @State private var manager = WidgetManager.shared
    @State private var selectedTab: WidgetTab = .installed
    @State private var reloadToken: UUID = UUID()
    
    private enum WidgetTab {
        case installed
        case store
    }
    
    public init(state: IslandState) {
        self.state = state
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            if manager.isViewingWidget, let active = manager.installedWidgets.first(where: { $0.id == manager.activeWidgetId }) {
                // Running Widget Screen
                VStack(spacing: 8) {
                    // Control Header
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(IslandToolsStyle.spring) {
                                manager.isViewingWidget = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Каталог")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundColor(Color.white.opacity(0.85))
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Вернуться к каталогу и магазину виджетов")
                        
                        HStack(spacing: 6) {
                            Image(systemName: active.iconName)
                                .font(.system(size: 11.5))
                            Text(active.name)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        
                        Spacer()
                        
                        Button {
                            reloadToken = UUID()
                            state.showToast("Виджет перезагружен", icon: "arrow.clockwise")
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Перезагрузить код виджета")
                        
                        Button {
                            manager.openWidgetCode(id: active.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "curlybraces")
                                    .font(.system(size: 10.5))
                                Text("Код")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color.white.opacity(0.8))
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Открыть папку с HTML/JS кодом этого виджета")
                    }
                    .frame(height: 28)
                    
                    // Widget Canvas without any distracting footers
                    WidgetWebView(url: active.htmlURL, reloadToken: reloadToken)
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
            } else {
                // Catalog / Store Screen
                VStack(spacing: 12) {
                    // Top Bar
                    HStack {
                        // Tab Selector (Installed vs Store)
                        HStack(spacing: 3) {
                            catalogTabButton(
                                title: "Мои виджеты (\(manager.installedWidgets.count))",
                                icon: "square.grid.2x2.fill",
                                isSelected: selectedTab == .installed
                            ) {
                                selectedTab = .installed
                            }
                            
                            catalogTabButton(
                                title: "Магазин виджетов",
                                icon: "sparkles",
                                isSelected: selectedTab == .store
                            ) {
                                selectedTab = .store
                            }
                        }
                        .padding(2)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        
                        Spacer()
                        
                        Button {
                            manager.createCustomTemplate()
                            state.showToast("Шаблон создан в Finder", icon: "sparkles")
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Свой виджет")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Создать новый шаблон и открыть в Finder")
                        
                        Button {
                            manager.openWidgetsFolderInFinder()
                        } label: {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Открыть общую папку ~/.ico/widgets")
                    }
                    .frame(height: 30)
                    
                    // Tab Content Area
                    if selectedTab == .installed {
                        installedWidgetsView
                    } else {
                        storeWidgetsView
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(width: 640)
        .onAppear {
            manager.reloadWidgets()
        }
    }
    
    // MARK: - Installed View
    
    private var installedWidgetsView: some View {
        Group {
            if manager.installedWidgets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(Color.white.opacity(0.3))
                    
                    Text("У вас пока нет установленных виджетов")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.75))
                    
                    HStack(spacing: 10) {
                        Button {
                            selectedTab = .store
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                Text("Выбрать в Магазине")
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 13)
                            .frame(height: 32)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            manager.createCustomTemplate()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                Text("Создать свой")
                            }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 13)
                            .frame(height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(Color(red: 0.07, green: 0.07, blue: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(manager.installedWidgets) { widget in
                            installedWidgetCard(widget)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 240)
            }
        }
    }
    
    private func installedWidgetCard(_ widget: CustomWidgetInfo) -> some View {
        Button {
            withAnimation(IslandToolsStyle.spring) {
                manager.activeWidgetId = widget.id
                manager.isViewingWidget = true
                reloadToken = UUID()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: widget.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(Color.white.opacity(0.9))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(widget.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(widget.description)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color.white.opacity(0.5))
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Button {
                        manager.openWidgetCode(id: widget.id)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.45))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Открыть папку с файлами виджета")
                    
                    Button {
                        manager.uninstallWidget(id: widget.id)
                        state.showToast("Виджет удален", icon: "trash")
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(Color.red.opacity(0.65))
                            .frame(width: 24, height: 24)
                            .background(Color.red.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Удалить виджет")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Store View
    
    private var storeWidgetsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 9) {
                ForEach(manager.availableStoreWidgets) { item in
                    let isInstalled = manager.installedWidgets.contains(where: { $0.id == item.id })
                    
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: item.iconName)
                                .font(.system(size: 20))
                                .foregroundColor(Color.white.opacity(0.95))
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text(item.category)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.55))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            
                            Text(item.description)
                                .font(.system(size: 10.5))
                                .foregroundColor(Color.white.opacity(0.55))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if isInstalled {
                            Button {
                                withAnimation(IslandToolsStyle.spring) {
                                    manager.activeWidgetId = item.id
                                    manager.isViewingWidget = true
                                    reloadToken = UUID()
                                }
                            } label: {
                                Text("Открыть")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 11)
                                    .frame(height: 28)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                manager.installStoreWidget(item)
                                state.showToast("Виджет установлен!", icon: "sparkles")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Установить")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 11)
                                .frame(height: 28)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(11)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 240)
    }
    
    private func catalogTabButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .black : Color.white.opacity(0.75))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isSelected ? Color.white : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
