import Foundation

enum RelayError: LocalizedError {
    case unsupportedMac
    case qqMusicNotRunning
    case qqMusicNotProducingAudio
    case noOutputDevice
    case unsupportedTapFormat(String)
    case rendererFailed(String)
    case captureFailed(String)
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedMac:
            "Spatial Audio on Mac requires Apple silicon."
        case .qqMusicNotRunning:
            "没有找到 QQ 音乐的音频进程。请先播放歌曲，然后刷新。"
        case .qqMusicNotProducingAudio:
            "QQ 音乐尚未输出声音，请播放歌曲后重试。"
        case .noOutputDevice:
            "macOS has no default audio output device."
        case .unsupportedTapFormat(let detail):
            "QQ 音乐的音频格式无法处理（\(detail)）。"
        case .rendererFailed(let detail):
            "空间音频渲染已停止（\(detail)）；程序已尝试恢复 QQ 音乐原声。"
        case .captureFailed(let detail):
            "QQ 音乐音频捕获失败（\(detail)）。"
        case .cleanupFailed(let detail):
            "音频捕获未能完全释放（\(detail)）。程序已尝试恢复原声；请退出应用后再试。"
        }
    }
}
