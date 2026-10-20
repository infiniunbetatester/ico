import AppKit
import AudioToolbox
import CoreAudio
import Observation
import Synchronization

private struct IslandAudioError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private enum IslandCA {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw IslandAudioError(message: "\(operation): \(status).")
        }
    }

    static func value<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        seed: T
    ) throws -> T {
        var result = seed
        var property = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutablePointer(to: &result) { pointer in
            try check(
                AudioObjectGetPropertyData(object, &property, 0, nil, &size, pointer),
                "Чтение аудиопараметра"
            )
        }
        return result
    }

    static func ids(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> [AudioObjectID] {
        var property = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size),
            "Чтение размера списка"
        )
        guard size > 0 else { return [] }
        var result = [AudioObjectID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        try result.withUnsafeMutableBytes { bytes in
            try check(
                AudioObjectGetPropertyData(object, &property, 0, nil, &size, bytes.baseAddress!),
                "Чтение списка аудиообъектов"
            )
        }
        return Array(result.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    static func string(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) throws -> String {
        var property = address(selector)
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, &result),
            "Чтение имени аудиообъекта"
        )
        guard let result else { return "" }
        return result.takeRetainedValue() as String
    }

    static func layout(
        _ device: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) throws -> [Int] {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size),
            "Чтение аудиоконфигурации"
        )
        guard size >= MemoryLayout<AudioBufferList>.size else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        try check(
            AudioObjectGetPropertyData(device, &property, 0, nil, &size, raw),
            "Чтение аудиобуферов"
        )
        let list = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.map { Int($0.mNumberChannels) }
    }

    static func format(_ stream: AudioStreamID) throws -> AudioStreamBasicDescription {
        try value(
            stream,
            kAudioStreamPropertyVirtualFormat,
            seed: AudioStreamBasicDescription()
        )
    }

    static func isFloat32(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM &&
        format.mBitsPerChannel == 32 &&
        format.mFormatFlags & kAudioFormatFlagIsFloat != 0 &&
        format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
    }
}

private struct IslandAudioChannel: Sendable {
    let buffer: Int
    let channel: Int

    static func locate(_ channel: Int, in layout: [Int]) throws -> IslandAudioChannel {
        var offset = 0
        for (index, count) in layout.enumerated() {
            if channel < offset + count {
                return IslandAudioChannel(buffer: index, channel: channel - offset)
            }
            offset += count
        }
        throw IslandAudioError(message: "Аудиоканал недоступен.")
    }
}

// All mutable DSP state is confined to the HAL callback.
// UI writes only targetGain; UI reads only atomic status.
private final class IslandAudioRenderer: @unchecked Sendable {
    let targetGain: Atomic<UInt32>
    let heartbeat = Atomic<UInt64>(0)
    let invalidLayout = Atomic<Bool>(false)

    private let inputLeft: IslandAudioChannel
    private let inputRight: IslandAudioChannel
    private let outputLeft: IslandAudioChannel
    private let outputRight: IslandAudioChannel?
    private let smoothing: Float
    private var currentGain: Float

    init(
        inputLeft: IslandAudioChannel,
        inputRight: IslandAudioChannel,
        outputLeft: IslandAudioChannel,
        outputRight: IslandAudioChannel?,
        sampleRate: Double,
        gain: Float
    ) {
        self.inputLeft = inputLeft
        self.inputRight = inputRight
        self.outputLeft = outputLeft
        self.outputRight = outputRight
        currentGain = gain
        targetGain = Atomic(gain.bitPattern)
        // Approximately 15 ms gain smoothing.
        smoothing = expf(-1 / (Float(sampleRate) * 0.015))
    }

    func setGain(_ value: Float) {
        targetGain.store(value.bitPattern, ordering: .relaxed)
    }

    @inline(__always)
    private func valid(
        _ channel: IslandAudioChannel,
        _ list: UnsafeMutableAudioBufferListPointer
    ) -> Bool {
        channel.buffer < list.count && channel.channel < Int(list[channel.buffer].mNumberChannels)
    }

    @inline(__always)
    private func frames(_ buffer: AudioBuffer) -> Int {
        let channels = Int(buffer.mNumberChannels)
        guard channels > 0, buffer.mData != nil else { return 0 }
        return Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
    }

    @inline(__always)
    private func read(
        _ channel: IslandAudioChannel,
        frame: Int,
        list: UnsafeMutableAudioBufferListPointer
    ) -> Float {
        let buffer = list[channel.buffer]
        let pointer = buffer.mData!.assumingMemoryBound(to: Float.self)
        return pointer[frame * Int(buffer.mNumberChannels) + channel.channel]
    }

    @inline(__always)
    private func write(
        _ sample: Float,
        channel: IslandAudioChannel,
        frame: Int,
        list: UnsafeMutableAudioBufferListPointer
    ) {
        let buffer = list[channel.buffer]
        let pointer = buffer.mData!.assumingMemoryBound(to: Float.self)
        pointer[frame * Int(buffer.mNumberChannels) + channel.channel] = sample
    }

    func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        for buffer in outputs {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }

        heartbeat.wrappingAdd(1, ordering: .relaxed)

        guard valid(inputLeft, inputs), valid(inputRight, inputs), valid(outputLeft, outputs) else {
            invalidLayout.store(true, ordering: .relaxed)
            return
        }

        if let outputRight, !valid(outputRight, outputs) {
            invalidLayout.store(true, ordering: .relaxed)
            return
        }

        var count = min(
            frames(inputs[inputLeft.buffer]),
            frames(inputs[inputRight.buffer])
        )
        count = min(count, frames(outputs[outputLeft.buffer]))
        if let outputRight {
            count = min(count, frames(outputs[outputRight.buffer]))
        }

        guard count > 0 else { return }

        let target = Float(bitPattern: targetGain.load(ordering: .relaxed))
        var gain = currentGain

        for frame in 0..<count {
            gain = target + (gain - target) * smoothing
            let left = read(inputLeft, frame: frame, list: inputs)
            let right = read(inputRight, frame: frame, list: inputs)

            if let outputRight {
                write(left * gain, channel: outputLeft, frame: frame, list: outputs)
                write(right * gain, channel: outputRight, frame: frame, list: outputs)
            } else {
                write((left + right) * 0.5 * gain, channel: outputLeft, frame: frame, list: outputs)
            }
        }
        currentGain = gain
    }
}

private let islandAudioIOProc: AudioDeviceIOProc = { _, _, input, _, output, _, context in
    guard let context else { return noErr }
    let renderer = Unmanaged<IslandAudioRenderer>
        .fromOpaque(context)
        .takeUnretainedValue()
    renderer.render(input: input, output: output)
    return noErr
}

// Setup happens on a detached worker.
// After publication, lifecycle methods are called only on MainActor.
private final class IslandAudioRoute: @unchecked Sendable {
    let processIDs: [AudioObjectID]
    let outputDevice: AudioDeviceID
    private var tap: AudioObjectID = kAudioObjectUnknown
    private var aggregate: AudioDeviceID = kAudioObjectUnknown
    private var ioProc: AudioDeviceIOProcID?
    private var renderer: IslandAudioRenderer?
    private var retainedContext: UnsafeMutableRawPointer?
    private var started = false

    var previousHeartbeat: UInt64 = 0
    var stalledPolls = 0

    var heartbeat: UInt64 { renderer?.heartbeat.load(ordering: .relaxed) ?? 0 }
    var hasInvalidLayout: Bool { renderer?.invalidLayout.load(ordering: .relaxed) ?? false }

    init(
        processIDs: [AudioObjectID],
        outputDevice: AudioDeviceID,
        gain: Float
    ) throws {
        self.processIDs = processIDs
        self.outputDevice = outputDevice
        do {
            try start(gain: gain)
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
    }

    func setGain(_ gain: Float) {
        renderer?.setGain(gain)
    }

    private func start(gain: Float) throws {
        guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") as? String,
              !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IslandAudioError(message: "Добавьте NSAudioCaptureUsageDescription в Info.plist.")
        }

        guard !processIDs.isEmpty else {
            throw IslandAudioError(message: "Нет аудиопроцессов.")
        }

        for process in processIDs {
            let pid: pid_t = try IslandCA.value(process, kAudioProcessPropertyPID, seed: pid_t(0))
            guard pid != getpid() else {
                throw IslandAudioError(message: "Нельзя перехватывать собственный аудиовывод.")
            }
        }

        let deviceClass: AudioClassID = try IslandCA.value(outputDevice, kAudioObjectPropertyClass, seed: AudioClassID(0))
        guard deviceClass != kAudioAggregateDeviceClassID else {
            throw IslandAudioError(message: "Для этой версии выберите обычный аудиовыход вместо Aggregate/Multi-Output.")
        }

        let uid = try IslandCA.string(outputDevice, kAudioDevicePropertyDeviceUID)
        let physicalInputStreams = try IslandCA.ids(
            outputDevice,
            kAudioDevicePropertyStreams,
            scope: kAudioObjectPropertyScopeInput
        )

        let description = CATapDescription(stereoMixdownOfProcesses: processIDs)
        description.uuid = UUID()
        description.name = "Island application volume"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        try IslandCA.check(
            AudioHardwareCreateProcessTap(description, &tap),
            "Не удалось подключить захват звука"
        )

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Island Volume",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]

        try IslandCA.check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate),
            "Не удалось создать аудиомаршрут"
        )

        // HAL can publish a newly created aggregate asynchronously.
        // This loop runs on the setup worker, never the audio callback.
        var ready = false
        for _ in 0..<40 {
            if let streams = try? IslandCA.ids(
                aggregate,
                kAudioDevicePropertyStreams,
                scope: kAudioObjectPropertyScopeOutput
            ), !streams.isEmpty {
                ready = true
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        guard ready else {
            throw IslandAudioError(message: "Аудиоустройство не успело подключиться.")
        }

        let outputStreams = try IslandCA.ids(aggregate, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        let inputStreams = try IslandCA.ids(aggregate, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)

        guard inputStreams.count > physicalInputStreams.count, !outputStreams.isEmpty else {
            throw IslandAudioError(message: "Не найден поток захваченного звука.")
        }

        let outputFormats = try outputStreams.map { try IslandCA.format($0) }
        guard outputFormats.allSatisfy(IslandCA.isFloat32),
              let firstOutputFormat = outputFormats.first,
              firstOutputFormat.mSampleRate > 0 else {
            throw IslandAudioError(message: "Выход должен поддерживать Float32 PCM.")
        }

        let tapStreams = inputStreams.dropFirst(physicalInputStreams.count)
        let inputFormats = try tapStreams.map { try IslandCA.format($0) }
        guard inputFormats.allSatisfy(IslandCA.isFloat32),
              inputFormats.allSatisfy({ abs($0.mSampleRate - firstOutputFormat.mSampleRate) < 1 }) else {
            throw IslandAudioError(message: "Формат или частота захвата не совпадают с аудиовыходом.")
        }

        let inputs = try IslandCA.layout(aggregate, scope: kAudioObjectPropertyScopeInput)
        let outputs = try IslandCA.layout(aggregate, scope: kAudioObjectPropertyScopeOutput)

        let inputChannels = inputs.reduce(0, +)
        let outputChannels = outputs.reduce(0, +)

        guard inputChannels >= 2, outputChannels == 1 || outputChannels == 2 else {
            throw IslandAudioError(message: "Эта версия поддерживает моно- и стереовыходы.")
        }

        // Aggregate input order: physical inputs, followed by the tap.
        let renderer = IslandAudioRenderer(
            inputLeft: try IslandAudioChannel.locate(inputChannels - 2, in: inputs),
            inputRight: try IslandAudioChannel.locate(inputChannels - 1, in: inputs),
            outputLeft: try IslandAudioChannel.locate(0, in: outputs),
            outputRight: outputChannels == 2 ? try IslandAudioChannel.locate(1, in: outputs) : nil,
            sampleRate: firstOutputFormat.mSampleRate,
            gain: gain
        )
        self.renderer = renderer

        let context = Unmanaged.passRetained(renderer).toOpaque()
        retainedContext = context

        try IslandCA.check(
            AudioDeviceCreateIOProcID(aggregate, islandAudioIOProc, context, &ioProc),
            "Не удалось подключить обработчик звука"
        )

        // Do not enable the physical device's microphone streams.
        if !physicalInputStreams.isEmpty {
            try disablePhysicalInputs(
                streamCount: inputStreams.count,
                physicalCount: physicalInputStreams.count
            )
        }

        try IslandCA.check(
            AudioDeviceStart(aggregate, ioProc),
            "Не удалось запустить обработку звука"
        )
        started = true
    }

    private func disablePhysicalInputs(streamCount: Int, physicalCount: Int) throws {
        guard let ioProc, let offset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) else {
            throw IslandAudioError(message: "Не удалось настроить входные потоки.")
        }

        let byteCount = max(
            MemoryLayout<AudioHardwareIOProcStreamUsage>.size,
            offset + streamCount * MemoryLayout<UInt32>.size
        )
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment
        )
        defer { raw.deallocate() }

        raw.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(ioProc, to: UnsafeMutableRawPointer.self)
        usage.pointee.mNumberStreams = UInt32(streamCount)

        let flags = raw.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
        for index in 0..<streamCount {
            flags[index] = index >= physicalCount ? 1 : 0
        }

        var property = IslandCA.address(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
        try IslandCA.check(
            AudioObjectSetPropertyData(aggregate, &property, 0, nil, UInt32(byteCount), raw),
            "Не удалось исключить микрофон из аудиомаршрута"
        )
    }

    func stop() {
        var canReleaseContext = ioProc == nil
        if aggregate != kAudioObjectUnknown {
            if started {
                AudioDeviceStop(aggregate, ioProc)
                started = false
            }
            if let ioProc {
                let result = AudioDeviceDestroyIOProcID(aggregate, ioProc)
                canReleaseContext = result == noErr
                self.ioProc = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = kAudioObjectUnknown
        }

        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = kAudioObjectUnknown
        }

        if let retainedContext {
            if canReleaseContext {
                Unmanaged<IslandAudioRenderer>.fromOpaque(retainedContext).release()
            }
            self.retainedContext = nil
        }
        renderer = nil
    }
}

public struct IslandMixerApp: Identifiable {
    public let id: String
    public let name: String
    public let icon: NSImage
    public var processIDs: [AudioObjectID]
    public var isPlaying: Bool
}

@MainActor
@Observable
public final class IslandAppMixer {
    public private(set) var apps: [IslandMixerApp] = []
    public private(set) var gains: [String: Double] = [:]
    public private(set) var connecting: Set<String> = []
    public private(set) var outputName = "Аудиовыход"
    public var error: String?

    @ObservationIgnored private var routes: [String: IslandAudioRoute] = [:]
    @ObservationIgnored private var requests: [String: UUID] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastAudible: [String: Double] = [:]
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private var outputDevice: AudioDeviceID = kAudioObjectUnknown
    private var outputSignature = ""
    private var sleeping = false
    private var terminated = false

    public init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = true
                self?.stopRoutes(clearGains: false)
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = false
            }
        })
    }

    public func startMonitoring() {
        guard monitor == nil, !terminated else { return }
        refresh()
        monitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 750_000_000)
                } catch {
                    return
                }
                self?.refresh()
            }
        }
    }

    public func gain(for id: String) -> Double {
        gains[id] ?? 1
    }

    public func setGain(_ value: Double, for id: String) {
        guard value.isFinite, !terminated else { return }
        let value = min(1, max(0, value))
        gains[id] = value
        error = nil
        if value > 0 {
            lastAudible[id] = value
        }
        if value >= 0.999 {
            disconnect(id)
            return
        }
        if let route = routes[id] {
            route.setGain(Float(value))
        } else if let app = apps.first(where: { $0.id == id }) {
            connect(app)
        }
    }

    public func toggleMute(_ id: String) {
        let current = gain(for: id)
        if current > 0 {
            lastAudible[id] = current
            setGain(0, for: id)
        } else {
            setGain(lastAudible[id] ?? 1, for: id)
        }
    }

    public func reset() {
        stopRoutes(clearGains: true)
        error = nil
    }

    public func shutdown() {
        terminated = true
        monitor?.cancel()
        monitor = nil
        stopRoutes(clearGains: true)
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    public func refresh() {
        guard !sleeping, !terminated else { return }
        do {
            let system = AudioObjectID(kAudioObjectSystemObject)
            let output: AudioDeviceID = try IslandCA.value(
                system,
                kAudioHardwarePropertyDefaultOutputDevice,
                seed: AudioDeviceID(kAudioObjectUnknown)
            )
            guard output != kAudioObjectUnknown else {
                throw IslandAudioError(message: "Аудиовыход не подключён.")
            }

            let streams = try IslandCA.ids(
                output,
                kAudioDevicePropertyStreams,
                scope: kAudioObjectPropertyScopeOutput
            )
            let formats = try streams.map { try IslandCA.format($0) }
            let signature = ([String(output)] + formats.map {
                "\($0.mSampleRate):\($0.mChannelsPerFrame):\($0.mFormatFlags):\($0.mBitsPerChannel)"
            }).joined(separator: "|")

            if outputSignature != signature {
                stopRoutes(clearGains: false)
                outputSignature = signature
                outputDevice = output
            }

            outputName = (try? IslandCA.string(output, kAudioObjectPropertyName)) ?? "Аудиовыход"

            let running = NSWorkspace.shared.runningApplications
            let regular = running.filter { $0.activationPolicy == .regular }
            let objects = try IslandCA.ids(system, kAudioHardwarePropertyProcessObjectList)

            var grouped: [String: IslandMixerApp] = [:]

            for object in objects {
                guard let pid: pid_t = try? IslandCA.value(object, kAudioProcessPropertyPID, seed: pid_t(0)),
                      pid != getpid() else { continue }

                let bundle = (try? IslandCA.string(object, kAudioProcessPropertyBundleID)) ?? ""
                let direct = NSRunningApplication(processIdentifier: pid)
                let owner = regular
                    .filter { app in
                        guard let identifier = app.bundleIdentifier else { return false }
                        return app.processIdentifier == pid || bundle == identifier || bundle.hasPrefix(identifier + ".")
                    }
                    .max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) } ?? direct

                let id = owner?.bundleIdentifier ?? (bundle.isEmpty ? "pid:\(pid)" : bundle)
                let name = owner?.localizedName ?? (bundle.isEmpty ? "Процесс \(pid)" : bundle)
                let active: UInt32 = (try? IslandCA.value(object, kAudioProcessPropertyIsRunningOutput, seed: UInt32(0))) ?? 0

                if var existing = grouped[id] {
                    existing.processIDs.append(object)
                    existing.isPlaying = existing.isPlaying || active != 0
                    grouped[id] = existing
                } else {
                    let fallback = NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 32, height: 32))
                    grouped[id] = IslandMixerApp(
                        id: id,
                        name: name,
                        icon: owner?.icon ?? fallback,
                        processIDs: [object],
                        isPlaying: active != 0
                    )
                }
            }

            apps = grouped.values
                .filter { $0.isPlaying || gain(for: $0.id) < 0.999 }
                .map {
                    var item = $0
                    item.processIDs.sort()
                    return item
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let liveIDs = Set(apps.map(\.id))
            for id in Array(routes.keys) where !liveIDs.contains(id) {
                disconnect(id)
            }

            for app in apps {
                if let route = routes[app.id] {
                    let heartbeat = route.heartbeat
                    if route.hasInvalidLayout {
                        disconnect(app.id)
                        gains[app.id] = 1
                        error = "Формат аудиоустройства изменился. Обычный звук восстановлен."
                        continue
                    }
                    if app.isPlaying && heartbeat == route.previousHeartbeat {
                        route.stalledPolls += 1
                    } else {
                        route.stalledPolls = 0
                    }
                    route.previousHeartbeat = heartbeat
                    if route.stalledPolls >= 4 {
                        disconnect(app.id)
                        gains[app.id] = 1
                        error = "Аудиомаршрут остановился. Проверьте доступ к системному аудио."
                        continue
                    }
                    if route.processIDs != app.processIDs {
                        disconnect(app.id)
                    }
                }
                if gain(for: app.id) < 0.999, routes[app.id] == nil, requests[app.id] == nil {
                    connect(app)
                }
            }
        } catch {
            stopRoutes(clearGains: true)
            self.error = error.localizedDescription
        }
    }

    private func connect(_ app: IslandMixerApp) {
        guard requests[app.id] == nil, outputDevice != kAudioObjectUnknown, !terminated, !sleeping else { return }
        let request = UUID()
        let id = app.id
        let processIDs = app.processIDs
        let device = outputDevice
        let signature = outputSignature
        let initialGain = Float(gain(for: id))
        requests[id] = request
        connecting.insert(id)

        tasks[id] = Task { @MainActor [weak self] in
            do {
                let route = try await Task.detached(priority: .userInitiated) {
                    try IslandAudioRoute(
                        processIDs: processIDs,
                        outputDevice: device,
                        gain: initialGain
                    )
                }.value

                guard let self else {
                    route.stop()
                    return
                }

                guard !Task.isCancelled,
                      !self.terminated,
                      !self.sleeping,
                      self.requests[id] == request,
                      self.outputSignature == signature,
                      self.apps.first(where: { $0.id == id })?.processIDs == processIDs,
                      self.gain(for: id) < 0.999 else {
                    route.stop()
                    if self.requests[id] == request {
                        self.requests[id] = nil
                        self.tasks[id] = nil
                        self.connecting.remove(id)
                    }
                    return
                }

                route.setGain(Float(self.gain(for: id)))
                self.routes[id] = route
                self.requests[id] = nil
                self.tasks[id] = nil
                self.connecting.remove(id)
            } catch {
                guard let self, self.requests[id] == request else { return }
                self.requests[id] = nil
                self.tasks[id] = nil
                self.connecting.remove(id)
                self.gains[id] = 1
                self.error = error.localizedDescription + " Проверьте разрешение на захват системного аудио."
            }
        }
    }

    private func disconnect(_ id: String) {
        requests[id] = nil
        tasks.removeValue(forKey: id)?.cancel()
        connecting.remove(id)
        routes.removeValue(forKey: id)?.stop()
    }

    private func stopRoutes(clearGains: Bool) {
        let ids = Set(routes.keys).union(requests.keys)
        for id in ids {
            disconnect(id)
        }
        if clearGains {
            gains.removeAll()
        }
    }
}
