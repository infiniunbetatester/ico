import SwiftUI

public struct HeaderTabBar: View {
    @Bindable var state: IslandState
    @State private var tools = IslandTools.shared
    @Namespace private var selection

    public init(state: IslandState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button {
                if tools.active != nil {
                    tools.back()
                } else {
                    state.togglePin()
                }
            } label: {
                Image(systemName: tools.active != nil ? "chevron.left" : state.isPinnedOpen ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        state.isPinnedOpen || tools.active != nil ? Color.white.opacity(0.85) : Color.white.opacity(0.45)
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        state.isPinnedOpen ? Color.white.opacity(0.09) : Color.clear
                    )
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(tools.active != nil ? "Назад к основным разделам" : "Закрепить раскрытый остров")

            Spacer(minLength: 2)

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
                            selected: state.mode == mode
                        ) {
                            tools.leaveTools()
                            withAnimation(IslandToolsStyle.spring) {
                                state.setMode(mode)
                            }
                        }
                    }
                }
            }
            .frame(height: 34)
            .background(Color.white.opacity(0.035))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )

            Spacer(minLength: 2)

            Menu {
                Section("Инструменты") {
                    Button {
                        tools.captureText()
                    } label: {
                        Label(
                            "Текст с экрана",
                            systemImage: "text.viewfinder"
                        )
                    }

                    Button {
                        tools.show(.qr)
                    } label: {
                        Label(
                            "QR-код (сканер и генератор)",
                            systemImage: "qrcode"
                        )
                    }

                    Button {
                        tools.show(.timer)
                    } label: {
                        Label("Таймер", systemImage: "timer")
                    }

                    Button {
                        tools.show(.mixer)
                    } label: {
                        Label(
                            "Громкость приложений",
                            systemImage: "speaker.wave.2"
                        )
                    }
                }

                Divider()

                Section("Размер свёрнутого острова") {
                    ForEach(CompactStyle.allCases) { style in
                        Button {
                            state.setCompactStyle(style)
                        } label: {
                            if state.compactStyle == style {
                                Label(
                                    style.rawValue,
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(style.rawValue)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28, height: 28)
            .help("Инструменты и настройки")

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
        .padding(.horizontal, 28)
        .frame(height: 34)
        .animation(IslandToolsStyle.spring, value: tools.active)
    }

    private func tab(
        title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(
                selected ? Color.white.opacity(0.96) : Color.white.opacity(0.45)
            )
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background {
                if selected {
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.09))
                    .matchedGeometryEffect(
                        id: "selected-tab",
                        in: selection
                    )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
