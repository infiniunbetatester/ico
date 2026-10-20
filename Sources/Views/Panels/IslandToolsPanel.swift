import SwiftUI

public struct IslandToolsPanel: View {
    @Bindable var tools: IslandTools
    
    public init(tools: IslandTools) {
        self.tools = tools
    }
    
    public var body: some View {
        Group {
            switch tools.active {
            case .text:
                IslandTextPanel(model: tools.ocr)
            case .timer:
                IslandTimerPanel(tools: tools)
            case .mixer:
                IslandMixerPanel(model: tools.mixer)
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 24)
        .frame(width: 708)
        .preferredColorScheme(.dark)
    }
}

private struct ToolActionStyle: ButtonStyle {
    var prominent = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 15)
            .frame(height: 34)
            .foregroundStyle(
                prominent ? Color.black : IslandToolsStyle.foreground
            )
            .background(
                prominent ? Color.white : IslandToolsStyle.cell
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(
                IslandToolsStyle.spring,
                value: configuration.isPressed
            )
    }
}

private struct IslandTextPanel: View {
    @Bindable var model: IslandScreenText
    
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Текст с экрана")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(model.isBusy ? "Распознавание…" : "Русский · English")
                    .font(.system(size: 10))
                    .foregroundStyle(IslandToolsStyle.secondary)
            }
            
            ZStack {
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .fill(IslandToolsStyle.cell)
                
                if model.isBusy {
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            model.isSelecting ? "Выделите область на экране" : "Распознаём текст…"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(IslandToolsStyle.secondary)
                    }
                } else if model.text.isEmpty {
                    VStack(spacing: 11) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 30, weight: .light))
                        Text("Выделите текст в любой области экрана")
                            .font(.system(size: 12))
                        Text("Результат появится здесь и в буфере обмена")
                            .font(.system(size: 10))
                            .foregroundStyle(IslandToolsStyle.secondary)
                    }
                } else {
                    TextEditor(text: $model.text)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                }
            }
            .frame(height: model.error == nil ? 178 : 141)
            
            if let error = model.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Доступ") {
                        model.openPermissions()
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.orange.opacity(0.85))
                .frame(minHeight: 24, alignment: .top)
            }
            
            HStack(spacing: 10) {
                Button {
                    model.capture()
                } label: {
                    Label(
                        model.text.isEmpty ? "Выделить область" : "Распознать ещё",
                        systemImage: "viewfinder"
                    )
                }
                .buttonStyle(ToolActionStyle(prominent: true))
                .disabled(model.isBusy)
                
                Button {
                    model.copy()
                } label: {
                    Label(
                        model.didCopy ? "Скопировано" : "Скопировать",
                        systemImage: model.didCopy ? "checkmark" : "doc.on.doc"
                    )
                    .contentTransition(.opacity)
                }
                .buttonStyle(ToolActionStyle())
                .disabled(model.text.isEmpty || model.isBusy)
                
                Spacer()
                Image(systemName: "lock.fill")
                Text("На устройстве")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(IslandToolsStyle.secondary)
        }
    }
}

private struct IslandTimerPanel: View {
    @Bindable var tools: IslandTools
    @State private var minutes = 25
    private var timer: IslandCountdown { tools.countdown }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Таймер", systemImage: "timer")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(timer.status)
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        timer.phase == .finished ? IslandToolsStyle.green : IslandToolsStyle.secondary
                    )
            }
            
            VStack(spacing: 7) {
                Text(timer.formattedRemaining)
                    .font(.system(size: 66, weight: .light))
                    .monospacedDigit()
                    .tracking(-2.5)
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(IslandToolsStyle.foreground)
                Text(
                    timer.phase == .finished ? "Можно сделать перерыв" : "Отсчёт остаётся виден в свёрнутом острове"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(IslandToolsStyle.secondary)
            }
            .frame(height: 105)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            timer.phase == .finished ? IslandToolsStyle.green : Color.white.opacity(0.85)
                        )
                        .frame(
                            width: geometry.size.width * timer.progress
                        )
                }
            }
            .frame(height: 3)
            .animation(.linear(duration: 0.25), value: timer.progress)
            
            if timer.phase == .idle {
                HStack(spacing: 8) {
                    ForEach([5, 15, 25, 45], id: \.self) { value in
                        Button("\(value) мин") {
                            minutes = value
                            timer.setDuration(Double(value * 60))
                        }
                        .buttonStyle(ToolActionStyle())
                    }
                    Spacer()
                    TextField(
                        "Мин",
                        value: $minutes,
                        format: .number
                    )
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12))
                    .frame(width: 43, height: 30)
                    .background(IslandToolsStyle.cell)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                    )
                    .onChange(of: minutes) { _, value in
                        timer.setDuration(
                            Double(min(1440, max(1, value)) * 60)
                        )
                    }
                    Text("мин")
                        .font(.system(size: 10.5))
                        .foregroundStyle(IslandToolsStyle.secondary)
                }
            }
            
            HStack(spacing: 10) {
                Spacer()
                switch timer.phase {
                case .idle:
                    Button {
                        tools.startTimer(
                            seconds: Double(
                                min(1440, max(1, minutes)) * 60
                            )
                        )
                    } label: {
                        Label("Запустить", systemImage: "play.fill")
                    }
                    .buttonStyle(ToolActionStyle(prominent: true))
                case .running:
                    Button {
                        timer.pause()
                    } label: {
                        Label("Пауза", systemImage: "pause.fill")
                    }
                    .buttonStyle(ToolActionStyle(prominent: true))
                    Button("Сбросить") {
                        tools.resetTimer()
                    }
                    .buttonStyle(ToolActionStyle())
                case .paused:
                    Button {
                        timer.resume()
                    } label: {
                        Label("Продолжить", systemImage: "play.fill")
                    }
                    .buttonStyle(ToolActionStyle(prominent: true))
                    Button("Сбросить") {
                        tools.resetTimer()
                    }
                    .buttonStyle(ToolActionStyle())
                case .finished:
                    Button("Ещё раз") {
                        tools.startTimer(seconds: timer.duration)
                    }
                    .buttonStyle(ToolActionStyle(prominent: true))
                    Button("Готово") {
                        tools.resetTimer()
                    }
                    .buttonStyle(ToolActionStyle())
                }
                Spacer()
            }
        }
        .onAppear {
            minutes = max(1, Int(timer.duration / 60))
        }
    }
}

private struct IslandMixerPanel: View {
    @Bindable var model: IslandAppMixer
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Громкость приложений")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .foregroundStyle(IslandToolsStyle.secondary)
                .help("Обновить")
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if model.apps.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 27, weight: .light))
                            Text("Запустите звук в приложении")
                                .font(.system(size: 12))
                            Text("Оно появится здесь")
                                .font(.system(size: 10.5))
                                .foregroundStyle(IslandToolsStyle.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 185)
                    }
                    ForEach(model.apps) { app in
                        mixerRow(app)
                    }
                }
            }
            .frame(height: model.error == nil ? 224 : 168)
            
            if let error = model.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                    Button {
                        model.error = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 10))
                .foregroundStyle(.orange.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack {
                Image(systemName: "hifispeaker.fill")
                Text(model.outputName)
                    .lineLimit(1)
                Spacer()
                Button("Сбросить уровни") {
                    model.reset()
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 10))
            .foregroundStyle(IslandToolsStyle.secondary)
        }
        .task {
            model.startMonitoring()
        }
    }
    
    private func mixerRow(_ app: IslandMixerApp) -> some View {
        let gain = model.gain(for: app.id)
        let busy = model.connecting.contains(app.id)
        
        return HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 31, height: 31)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Text(
                    busy ? "Подключение…" : app.isPlaying ? "Воспроизводится" : "Ожидание"
                )
                .font(.system(size: 9))
                .foregroundStyle(IslandToolsStyle.secondary)
            }
            .frame(width: 155, alignment: .leading)
            
            Button {
                model.toggleMute(app.id)
            } label: {
                Image(
                    systemName: gain < 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill"
                )
                .font(.system(size: 12))
                .frame(width: 27, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                gain < 0.001 ? IslandToolsStyle.secondary : Color.white.opacity(0.8)
            )
            
            Slider(
                value: Binding(
                    get: { model.gain(for: app.id) },
                    set: { model.setGain($0, for: app.id) }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .tint(.white.opacity(0.9))
            .accessibilityLabel("Громкость \(app.name)")
            
            ZStack {
                if busy {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text("\(Int((gain * 100).rounded()))%")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(IslandToolsStyle.secondary)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 37)
        }
        .padding(.horizontal, 12)
        .frame(height: 59)
        .background(IslandToolsStyle.cell)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }
}
