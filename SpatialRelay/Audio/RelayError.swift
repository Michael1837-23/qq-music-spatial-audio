import Foundation

enum RelayError: LocalizedError {
    case unsupportedMac
    case noOutputDevice
    case unsupportedTapFormat(String)
    case rendererFailed(String)
    case captureFailed(String)
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedMac:
            "Spatial Audio on Mac requires Apple silicon."
        case .noOutputDevice:
            "macOS has no default audio output device."
        case .unsupportedTapFormat(let detail):
            "捕获的音频格式无法处理（\(detail)）。"
        case .rendererFailed(let detail):
            "空间音频渲染已停止（\(detail)）；程序已尝试恢复各应用原声。"
        case .captureFailed(let detail):
            "音频捕获失败（\(detail)）。"
        case .cleanupFailed(let detail):
            "音频捕获未能完全释放（\(detail)）。程序已尝试恢复原声；请退出应用后再试。"
        }
    }
}
