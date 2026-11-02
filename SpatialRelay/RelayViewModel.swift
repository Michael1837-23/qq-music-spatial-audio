import AppKit
import Combine
import Foundation
import MediaPlayer

@MainActor
final class RelayViewModel: ObservableObject {
    enum CheckState {
        case ready
        case warning
        case unavailable
    }

    struct Message: Equatable {
        enum Kind {
            case info
            case warning
            case error
        }

        let kind: Kind
        let text: String
    }

    @Published private(set) var sourceDetail = "正在检测播放声音…"
    @Published private(set) var sourceState: CheckState = .warning
    @Published private(set) var outputDetail = "Looking for the current output…"
    @Published private(set) var outputState: CheckState = .warning
    @Published private(set) var message: Message?
    @Published private(set) var isRelaying = false
    @Published private(set) var isProbing = false
    @Published private(set) var isBusy = false
    @Published private(set) var meterLevel: CGFloat = 0
    @Published private(set) var latencyLabel = "~80 ms prebuffer"

    private let coordinator = AudioRelayCoordinator()
    private let startupQueue = DispatchQueue(
        label: "com.shevlfs.SpatialRelay.startup",
        qos: .userInitiated
    )
    private var discovery: RelayDiscovery?
    private var meterTimer: Timer?
    private var healthTick = 0
    private var startupOperationID: UUID?
    private var terminationCleanupIsRunning = false
    private var terminationCompletions: [() -> Void] = []
    private(set) var isReadyToTerminate = false

    deinit {
        MainActor.assumeIsolated {
            meterTimer?.invalidate()
            coordinator.stop()
        }
    }

    var canToggleRelay: Bool {
        if isRelaying { return !isBusy }
        return !isBusy && !isProbing && discovery?.outputDevice != nil
    }

    var canToggleProbe: Bool {
        if isProbing { return !isBusy }
        return !isBusy && !isRelaying && discovery?.outputDevice != nil
    }

    func toggleProbe() {
        guard canToggleProbe else { return }
        if isProbing { stopRelay() } else { start(modeProbe: true) }
    }

    var menuBarSymbolName: String {
        if isBusy { return "ellipsis.circle" }
        if isRelaying { return "waveform.circle.fill" }
        if message?.kind == .error { return "exclamationmark.triangle.fill" }
        return "waveform.circle"
    }

    var menuBarStatusText: String {
        if isBusy { return "Spatial Relay is changing audio state" }
        if isRelaying { return "Spatial Relay is active" }
        if message?.kind == .error { return "Spatial Relay needs attention" }
        return "Spatial Relay is stopped"
    }

    func refresh() {
        // Reopening the menu-bar window calls this view's onAppear again. Do not
        // make the main actor wait on Core Audio while a permission prompt or
        // pipeline startup is already running on the coordinator queue.
        guard !isRelaying, !isProbing, !isBusy else { return }

        do {
            let discovery = try coordinator.discover()
            self.discovery = discovery
            message = nil
            apply(discovery)
        } catch {
            discovery = nil
            sourceDetail = "Unable to inspect audio processes"
            sourceState = .unavailable
            outputDetail = "Unable to inspect the current output"
            outputState = .unavailable
            message = Message(kind: .error, text: error.localizedDescription)
        }
    }

    func toggleRelay() {
        guard canToggleRelay else { return }
        if isRelaying {
            stopRelay()
        } else {
            startRelay()
        }
    }

    func prepareForTermination(completion: @escaping () -> Void) {
        if isReadyToTerminate {
            completion()
            return
        }

        terminationCompletions.append(completion)
        guard !terminationCleanupIsRunning else { return }
        terminationCleanupIsRunning = true

        startupOperationID = nil
        meterTimer?.invalidate()
        meterTimer = nil
        isRelaying = false
        isProbing = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        isBusy = true
        meterLevel = 0

        // The serial startup queue gives cleanup strict ordering after a tap
        // creation that may still be waiting for the privacy prompt. AppKit's
        // terminate-later reply keeps the process alive, while leaving the main
        // actor and menu responsive until source audio has been safely unmuted.
        let coordinator = coordinator
        startupQueue.async { [weak self] in
            _ = coordinator.stop()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isBusy = false
                    self.isReadyToTerminate = true
                    self.terminationCleanupIsRunning = false
                    let completions = self.terminationCompletions
                    self.terminationCompletions.removeAll()
                    completions.forEach { $0() }
                }
            }
        }
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    private func startRelay() {
        start(modeProbe: false)
    }

    private func start(modeProbe: Bool) {
        isBusy = true
        message = nil
        let operationID = UUID()
        startupOperationID = operationID
        let coordinator = coordinator

        // Tap creation can wait for Core Audio or a privacy prompt. Keep it off
        // the main actor so the window and progress indicator stay responsive.
        startupQueue.async { [weak self] in
            let result: Result<RelayDiscovery, Error>
            do {
                let onFailure: @Sendable (Error) -> Void = { [weak self] error in
                    Task { @MainActor in
                        self?.handlePipelineFailure(error)
                    }
                }
                let discovery = try modeProbe
                    ? coordinator.startProbe(onFailure: onFailure)
                    : coordinator.start(onFailure: onFailure)
                result = .success(discovery)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.completeStart(result, operationID: operationID, modeProbe: modeProbe)
                }
            }
        }
    }

    private func completeStart(
        _ result: Result<RelayDiscovery, Error>,
        operationID: UUID,
        modeProbe: Bool
    ) {
        guard startupOperationID == operationID else { return }
        startupOperationID = nil
        isBusy = false

        switch result {
        case .success(let discovery):
            self.discovery = discovery
            apply(discovery)
            isRelaying = !modeProbe
            isProbing = modeProbe
            if modeProbe {
                message = Message(kind: .info, text: "安全检测中：各应用原声保持播放，不进行空间化或输出音频。")
                startMetering()
                return
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: "空间音频转播",
                MPNowPlayingInfoPropertyPlaybackRate: 1.0
            ]
            MPNowPlayingInfoCenter.default().playbackState = .playing
            if let output = discovery.outputDevice, !output.isLikelySpatialAudioHeadphones {
                message = Message(
                    kind: .warning,
                    text: "Relay active, but \(output.name) does not look like Spatial Audio-capable AirPods. Choose your AirPods as the Mac's output, then restart the relay."
                )
            } else {
                message = Message(
                    kind: .info,
                    text: "转播已开启；请在系统声音菜单中检查空间音频并选择固定。"
                )
            }
            startMetering()
        case .failure(let error):
            let cleanupFailure = coordinator.stop()
            isRelaying = false
            isProbing = false
            message = Message(
                kind: .error,
                text: startFailureMessage(cleanupFailure ?? error)
            )
        }
    }

    private func stopRelay() {
        startupOperationID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        isBusy = true
        meterTimer?.invalidate()
        meterTimer = nil
        let cleanupFailure = coordinator.stop()
        isRelaying = false
        isProbing = false
        meterLevel = 0
        isBusy = false
        message = cleanupFailure.map {
            Message(kind: .error, text: $0.localizedDescription)
        } ?? Message(kind: .info, text: "已停止处理，各应用应恢复直接播放。")
        refreshRouteRowsPreservingMessage()
    }

    private func handlePipelineFailure(_ error: Error) {
        startupOperationID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        meterTimer?.invalidate()
        meterTimer = nil
        isRelaying = false
        isProbing = false
        isBusy = false
        meterLevel = 0
        message = Message(kind: .error, text: error.localizedDescription)
        refreshRouteRowsPreservingMessage()
    }

    private func startMetering() {
        meterTimer?.invalidate()
        healthTick = 0
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRelaying || self.isProbing else { return }

                let metrics = self.coordinator.metrics()
                let shapedPeak = CGFloat(pow(max(0, min(1, metrics.peakLevel)), 0.45))
                self.meterLevel = max(shapedPeak, self.meterLevel * 0.72)
                self.latencyLabel = metrics.droppedFrameCount == 0
                    ? "~80 ms prebuffer"
                    : "\(metrics.droppedFrameCount) frames dropped"

                self.healthTick += 1
                if self.healthTick >= 8 {
                    self.healthTick = 0
                    if let failure = self.coordinator.healthFailure() {
                        let cleanupFailure = self.coordinator.stop()
                        self.handlePipelineFailure(cleanupFailure ?? failure)
                    }
                }
            }
        }
    }

    private func apply(_ discovery: RelayDiscovery) {
        if discovery.audioProcesses.isEmpty {
            sourceDetail = "等待应用播放声音"
            sourceState = .warning
        } else {
            let activeCount = discovery.audioProcesses.filter(\.isRunningOutput).count
            sourceDetail = activeCount > 0
                ? "检测到音频进程正在输出"
                : "等待应用播放声音"
            sourceState = activeCount > 0 ? .ready : .warning
        }

        if let output = discovery.outputDevice {
            outputDetail = "\(output.name) · \(Int(output.sampleRate.rounded())) Hz"
            outputState = output.isLikelySpatialAudioHeadphones ? .ready : .warning
        } else {
            outputDetail = "No default output device"
            outputState = .unavailable
        }

        guard message == nil || message?.kind != .error else { return }

        #if !arch(arm64)
        message = Message(kind: .error, text: RelayError.unsupportedMac.localizedDescription)
        #else
        if let output = discovery.outputDevice, !output.isLikelySpatialAudioHeadphones {
            message = Message(kind: .warning, text: "The current output does not look like Spatial Audio-capable AirPods. Connect AirPods before starting the relay.")
        } else if !isRelaying {
            message = nil
        }
        #endif
    }

    private func refreshRouteRowsPreservingMessage() {
        let savedMessage = message
        do {
            let discovery = try coordinator.discover()
            self.discovery = discovery
            apply(discovery)
        } catch {
            discovery = nil
            sourceDetail = "Unable to inspect audio processes"
            sourceState = .unavailable
            outputDetail = "Unable to inspect the current output"
            outputState = .unavailable
        }
        message = savedMessage
    }

    private func startFailureMessage(_ error: Error) -> String {
        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("permission") ||
            description.localizedCaseInsensitiveContains("denied") ||
            description.localizedCaseInsensitiveContains("operation not permitted") ||
            description.localizedCaseInsensitiveContains("'perm'") ||
            description.contains("560492391") ||
            description.localizedCaseInsensitiveContains("!hog") {
            return "\(description) Allow Spatial Relay in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch it."
        }
        return description
    }
}
