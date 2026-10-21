import SwiftUI

public struct HeaderTabBar: View {
    @Bindable var state: IslandState
    @State private var tools = IslandTools.shared
    @Namespace private var selection

    public init(state: IslandState) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            // Absolute Center: Adaptive Tabs or Tools or Settings
            HStack(spacing: 2) {
                if tools.active != nil {
                    ForEach(IslandTool.allCases) { tool in
                        tab(
                            title: tool.title,
                            icon: tool.icon,
                            selected: tools.active == tool
                        ) {
                            tools.show(tool)
                        }
                    }
                } else {
                    ForEach(IslandMode.allCases) { mode in
                        tab(
                            title: mode.title,
                            icon: mode.iconName,
                            selected: (!state.isSettingsOpen && state.mode == mode)
                        ) {
                            tools.leaveTools()
                            state.isSettingsOpen = false
                            withAnimation(IslandToolsStyle.spring) {
                                state.setMode(mode)
                            }
                        }
                    }
                }
            }
            .frame(height: 34)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Side Controls (Left Pin/Back & Right Tools/Settings/Collapse)
            HStack {
                // Left Action
                Button {
                    if state.isSettingsOpen {
                        withAnimation(IslandToolsStyle.spring) {
                            state.isSettingsOpen = false
                        }
                    } else if tools.active != nil {
                        tools.back()
                    } else {
                        state.togglePin()
                    }
                } label: {
                    Image(systemName: (state.isSettingsOpen || tools.active != nil) ? "chevron.left" : "pin.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            (state.isPinnedOpen || tools.active != nil || state.isSettingsOpen) ? Color.white.opacity(0.9) : Color.white.opacity(0.35)
                        )
                        .frame(width: 28, height: 28)
                        .background(
                            (state.isPinnedOpen || state.isSettingsOpen) ? Color.white.opacity(0.12) : Color.white.opacity(0.04)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(state.isSettingsOpen ? "Назад к разделам" : tools.active != nil ? "Назад к разделам" : "Закрепить раскрытый остров")

                Spacer()

                // Right Group
                HStack(spacing: 6) {
                    Menu {
                        Section("Инструменты") {
                            Button { tools.captureText() } label: { Label("Текст с экрана", systemImage: "text.viewfinder") }
                            Button { tools.show(.qr) } label: { Label("QR-код", systemImage: "qrcode") }
                            Button { tools.show(.timer) } label: { Label("Таймер", systemImage: "timer") }
                            Button { tools.show(.mixer) } label: { Label("Микшер громкости", systemImage: "speaker.wave.2") }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tools.active != nil ? Color.white : Color.white.opacity(0.5))
                            .frame(width: 28, height: 28)
                            .background(tools.active != nil ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28, height: 28)
                    .help("Инструменты")

                    Button {
                        withAnimation(IslandToolsStyle.spring) {
                            tools.leaveTools()
                            state.isSettingsOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(state.isSettingsOpen ? Color.white : Color.white.opacity(0.5))
                            .frame(width: 28, height: 28)
                            .background(state.isSettingsOpen ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Настройки")

                    Button {
                        withAnimation(IslandToolsStyle.spring) {
                            state.collapse()
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Свернуть · Esc")
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 34)
    }

    private func tab(
        title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                
                if selected {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)),
                            removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading))
                        ))
                }
            }
            .foregroundStyle(
                selected ? Color.white.opacity(0.96) : Color.white.opacity(0.45)
            )
            .padding(.horizontal, selected ? 11 : 9)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.12))
                    .matchedGeometryEffect(
                        id: "selected-tab",
                        in: selection
                    )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
