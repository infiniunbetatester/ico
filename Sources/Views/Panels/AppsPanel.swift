import SwiftUI
import AppKit

public struct AppsPanel: View {
    @Bindable var state: IslandState
    
    public init(state: IslandState) {
        self.state = state
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Panel Heading
            HStack {
                HStack(spacing: 9) {
                    Text("Запущенные приложения")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.96, green: 0.96, blue: 0.97))
                    
                    Text("\(state.runningApps.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.61, green: 0.61, blue: 0.64))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                
                Spacer()
                
                Button(action: { state.refreshRunningApps() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.53))
                        .frame(width: 24, height: 24)
                        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Обновить список")
            }
            .frame(height: 23)
            
            // Running Apps Grid (real apps on this Mac)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    if state.runningApps.isEmpty {
                        Text("Нет других запущенных приложений")
                            .font(.system(size: 12))
                            .foregroundColor(Color.gray)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ForEach(Array(state.runningApps.enumerated()), id: \.element.id) { index, item in
                            let isSelected = state.activeAppIndex == index
                            Button(action: {
                                state.activateApp(index: index)
                            }) {
                                VStack(spacing: 8) {
                                    // Real App Icon from macOS
                                    Image(nsImage: item.icon)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 52, height: 52)
                                        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                                        .scaleEffect(isSelected ? 1.05 : 1.0)
                                    
                                    Text(item.name)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                        .foregroundColor(isSelected ? Color.white : Color(red: 0.7, green: 0.7, blue: 0.73))
                                        .lineLimit(1)
                                        .frame(width: 82)
                                }
                                .padding(.vertical, 10)
                                .frame(width: 96, height: 118)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isSelected ? Color(red: 0.16, green: 0.16, blue: 0.18) : Color(red: 0.08, green: 0.08, blue: 0.09))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(height: 125)
            
            // Pinned Quick Actions
            HStack {
                Text("Закреплённые утилиты")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.55))
                Spacer()
            }
            .frame(height: 19)
            .padding(.top, 4)
            
            HStack(spacing: 9) {
                QuickAppLauncher(name: "Finder", bundleId: "com.apple.finder", iconName: "folder.fill", color: Color.blue)
                QuickAppLauncher(name: "Safari", bundleId: "com.apple.Safari", iconName: "safari.fill", color: Color.cyan)
                QuickAppLauncher(name: "Терминал", bundleId: "com.apple.Terminal", iconName: "terminal.fill", color: Color.gray)
                QuickAppLauncher(name: "Настройки", bundleId: "com.apple.systempreferences", iconName: "gearshape.fill", color: Color(red: 0.6, green: 0.6, blue: 0.65))
            }
            .frame(height: 52)
            
            // Footer
            HStack {
                if state.activeAppIndex < state.runningApps.count {
                    let active = state.runningApps[state.activeAppIndex]
                    Text("Нажмите, чтобы переключиться на \(active.name)")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.42))
                }
                Spacer()
                Text("Реальные процессы macOS")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.42))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .frame(width: 708)
    }
}

private struct QuickAppLauncher: View {
    let name: String
    let bundleId: String
    let iconName: String
    let color: Color
    
    var body: some View {
        Button(action: {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: iconName)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                    )
                
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.9, green: 0.9, blue: 0.92))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 48)
            .background(Color(red: 0.08, green: 0.08, blue: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
