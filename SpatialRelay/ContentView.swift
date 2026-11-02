import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RelayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            routeCard

            if let message = viewModel.message {
                messageCard(message)
            }

            if viewModel.isRelaying || viewModel.isProbing {
                meter
            }

            if viewModel.isRelaying {
                spatialAudioHint
            } else if viewModel.isProbing {
                probeHint
            } else {
                privacyHint
            }

            Spacer(minLength: 0)
            controls
        }
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { viewModel.refresh() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "airpodspro")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.78, blue: 0.43), Color(red: 0.07, green: 0.58, blue: 0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("空间音频转播")
                    .font(.title.bold())
                Text("使用苹果系统的空间化立体声")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var routeCard: some View {
        VStack(spacing: 0) {
            routeRow(
                icon: "music.note",
                title: "播放声音",
                detail: viewModel.sourceDetail,
                state: viewModel.sourceState
            )

            Divider().padding(.leading, 48)

            routeRow(
                icon: "speaker.wave.2.fill",
                title: "声音输出",
                detail: viewModel.outputDetail,
                state: viewModel.outputState
            )
        }
        .padding(.horizontal, 16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private func routeRow(icon: String, title: String, detail: String, state: RelayViewModel.CheckState) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: state.symbolName)
                .foregroundStyle(state.color)
                .font(.system(size: 16, weight: .semibold))
        }
        .frame(minHeight: 62)
    }

    private func messageCard(_ message: RelayViewModel.Message) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message.kind.symbolName)
                .foregroundStyle(message.kind.color)
                .padding(.top, 1)
            Text(message.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(message.kind.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(viewModel.isProbing ? "正在检测播放声音" : "正在转播播放声音", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                if viewModel.isRelaying {
                    Text(viewModel.latencyLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .mint, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, proxy.size.width * viewModel.meterLevel))
                        .animation(.linear(duration: 0.12), value: viewModel.meterLevel)
                }
            }
            .frame(height: 8)
        }
    }

    private var spatialAudioHint: some View {
        Label {
            Text("在菜单栏的 AirPods 声音菜单中，选择空间化立体声的 **固定**。")
        } icon: {
            Image(systemName: "gyroscope")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var probeHint: some View {
        Label("仅检测音量，不会静音或转播其他应用。", systemImage: "checkmark.shield")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var privacyHint: some View {
        Label {
            Text("首次检测会请求系统音频录制权限。转播时会接管当前输出设备的应用声音，可能包括通知和通话。")
        } icon: {
            Image(systemName: "hand.raised.fill")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.refresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isBusy || viewModel.isRelaying || viewModel.isProbing)

            Menu {
                Button("退出", systemImage: "power") {
                    viewModel.quitApplication()
                }
                .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 0)

            Button {
                viewModel.toggleProbe()
            } label: {
                Text(viewModel.isProbing ? "停止检测" : "安全检测")
            }
            .disabled(!viewModel.canToggleProbe)

            Button {
                viewModel.toggleRelay()
            } label: {
                if viewModel.isBusy {
                    ProgressView().controlSize(.small)
                        .frame(minWidth: 92)
                } else {
                    Text(viewModel.isRelaying ? "立即停止" : "开始转播")
                        .frame(minWidth: 92)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(viewModel.isRelaying ? .red : .accentColor)
            .disabled(!viewModel.canToggleRelay || viewModel.isProbing)
        }
    }
}

private extension RelayViewModel.CheckState {
    var symbolName: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: .green
        case .warning: .orange
        case .unavailable: .red
        }
    }
}

private extension RelayViewModel.Message.Kind {
    var symbolName: String {
        switch self {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}
