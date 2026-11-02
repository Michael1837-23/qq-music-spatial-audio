import AppKit
import SwiftUI

@MainActor
private final class SpatialRelayApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: RelayViewModel?
    private var terminationReplyIsPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel else { return .terminateNow }
        guard !viewModel.isReadyToTerminate else { return .terminateNow }

        if !terminationReplyIsPending {
            terminationReplyIsPending = true
            viewModel.prepareForTermination {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

@main
struct SpatialRelayApp: App {
    @NSApplicationDelegateAdaptor(SpatialRelayApplicationDelegate.self) private var appDelegate
    @StateObject private var viewModel: RelayViewModel

    init() {
        let viewModel = RelayViewModel()
        _viewModel = StateObject(wrappedValue: viewModel)
        appDelegate.viewModel = viewModel
    }

    var body: some Scene {
        WindowGroup("空间音频转播") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 500, minHeight: 560)
        }

        MenuBarExtra {
            ContentView(viewModel: viewModel)
                .frame(width: 500, height: 540)
        } label: {
            Image(systemName: viewModel.menuBarSymbolName)
                .symbolRenderingMode(.monochrome)
                .accessibilityLabel(viewModel.menuBarStatusText)
        }
        .menuBarExtraStyle(.window)
    }
}
