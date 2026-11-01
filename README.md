# QQ Music Spatial Audio

让 Apple 芯片 Mac 上的 QQ 音乐通过 AirPods 使用 macOS 的**空间化立体声**。程序在菜单栏运行，可以选择系统提供的“固定”或“头部追踪”模式。

这是基于 [Spatial Relay](https://github.com/shevlfs/spatial-relay) 的 QQ 音乐适配版。感谢原作者 [shevlfs](https://github.com/shevlfs)；本项目保留上游的 MIT 许可证和版权声明，与腾讯和苹果均无官方关联。

## 工作方式

程序只匹配 QQ 音乐 Mac 客户端的主进程，使用 Core Audio process tap 捕获双声道声音，再通过苹果的 `AVSampleBufferAudioRenderer` 请求系统进行立体声空间化，输出到当前设备。

```text
QQ 音乐 → Core Audio 进程捕获 → 苹果系统空间化播放 → AirPods
```

这处理的是 QQ 音乐输出的立体声，不会为普通歌曲添加杜比全景声源文件。系统和耳机可能根据内容、设备及用户设置选择不同的效果；不能保证与 Apple Music 逐样本一致。

## 设备要求

- 搭载 Apple 芯片、运行 macOS 14.2 或更新版本的 Mac。
- 已安装并播放歌曲的 QQ 音乐 Mac 客户端。
- 已连接并设为系统输出、支持空间音频的 AirPods；其他设备能否使用取决于 macOS 和设备。
- 构建源码需要 Xcode 16.4 或更新版本。

当前版本只匹配 QQ 音乐的 `com.tencent.QQMusicMac` 主进程；如果未来 QQ 音乐改用其他进程输出，本程序可能无法检测到声音。

## 使用

可在 [Releases](https://github.com/Michael1837-23/qq-music-spatial-audio/releases) 查看可用版本，也可以按下文从源码构建。测试版使用临时签名，**未经 Apple 公证**，macOS 可能阻止直接打开；请勿为了运行它而关闭系统安全保护。

1. 将 AirPods 连接到 Mac，并设为系统声音输出。
2. 在 QQ 音乐里播放歌曲，然后打开“QQ 音乐空间音频”。
3. 点击菜单栏的波形图标，选择“安全检测”，确认程序检测到声音；检测不会静音原声。
4. 停止检测，选择“开始转播”。首次使用时按系统提示授予音频录制权限。
5. 在菜单栏的 AirPods 声音菜单中，按需要选择空间音频的“固定”。不同播放会话可能使系统菜单显示不同状态。

关闭控制窗口后程序继续在菜单栏运行。点击“立即停止”可结束转播并尝试恢复直接播放；面板中的“…”菜单可以退出程序。切换音频输出设备前建议先停止转播。

## 隐私与音频恢复

捕获目标在代码中限定为 QQ 音乐主进程。音频在本机内存中缓冲和处理，不保存为文件；源码中没有上传音频的功能。macOS 授予的是系统音频录制权限，权限本身可能允许应用读取其他程序的声音，可以在系统设置中撤销。

转播期间 QQ 音乐的原始输出会被临时静音，由程序重新输出。正常停止和已处理的失败路径会尝试恢复原声，但异常退出或设备变化仍可能造成短暂无声。如果无声，先点“立即停止”或退出程序，再检查系统声音输出是否为 AirPods。

## 从源码构建

```bash
git clone https://github.com/Michael1837-23/qq-music-spatial-audio.git
cd qq-music-spatial-audio
xcodebuild -project SpatialRelay.xcodeproj -scheme SpatialRelay \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

应用位于 `build/DerivedData/Build/Products/Release/SpatialRelay.app`。临时签名构建仅供测试；若要分发经过 Apple 公证的版本，需要自行准备开发者签名和公证流程。

运行单元测试：

```bash
xcodebuild -project SpatialRelay.xcodeproj -scheme SpatialRelay \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test
```

自动化测试不能代替对系统录制权限、真实耳机、声音恢复和空间音频菜单的实机验证。

## 许可证

本项目按 [MIT License](LICENSE) 发布，保留原项目版权声明。QQ 音乐、AirPods、macOS 和 Apple 等名称及商标归各自权利人所有。
