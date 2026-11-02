import CoreAudio
import CoreMedia
import XCTest
@testable import SpatialRelay

final class CoreLogicTests: XCTestCase {
    func testSystemTapIncludesSpecifiedProcessesAndProbeDoesNotMute() {
        let output = OutputDeviceInfo(id: 1, uid: "test-output", name: "Test", sampleRate: 48_000)
        let tap = AudioHardwareClient.systemAudioTapDescription(processes: [42], outputDevice: output, muted: true)
        XCTAssertFalse(tap.isExclusive)
        XCTAssertEqual(tap.processes, [42])
        XCTAssertEqual(tap.deviceUID, output.uid)
        XCTAssertEqual(tap.muteBehavior, .mutedWhenTapped)
        let probe = AudioHardwareClient.systemAudioTapDescription(processes: [42], outputDevice: output, muted: false)
        XCTAssertEqual(probe.muteBehavior, .unmuted)
    }

    func testAirPodsOutputDetectionIsCaseInsensitive() {
        let airPods = OutputDeviceInfo(
            id: 1,
            uid: "airpods",
            name: "TEST AIRPODS PRO",
            sampleRate: 48_000
        )
        let speakers = OutputDeviceInfo(
            id: 2,
            uid: "speakers",
            name: "MacBook Pro Speakers",
            sampleRate: 48_000
        )

        XCTAssertTrue(airPods.isLikelySpatialAudioHeadphones)
        XCTAssertFalse(speakers.isLikelySpatialAudioHeadphones)
    }

    func testOSStatusDescriptionShowsFourCharacterCode() {
        let status = OSStatus(bitPattern: 0x666D743F) // 'fmt?'
        XCTAssertEqual(CoreAudioFailure.describe(status), "'fmt?' / 1718449215")
        XCTAssertEqual(CoreAudioFailure.describe(-50), "-50")
    }

    func testRendererRecoveryRebasesAtLatestValidOutputTime() {
        let timescale: CMTimeScale = 48_000
        let currentTime = CMTime(value: 96_000, timescale: timescale)

        XCTAssertEqual(
            RendererRecoveryTimeline.restartFrame(
                currentTime: currentTime,
                suggestedFlushTime: CMTime(value: 72_000, timescale: timescale),
                timescale: timescale,
                fallbackFrame: 150_000
            ),
            96_000,
            "Flushed renderer timestamps must not force the live timeline backwards"
        )
        XCTAssertEqual(
            RendererRecoveryTimeline.restartFrame(
                currentTime: currentTime,
                suggestedFlushTime: CMTime(value: 120_000, timescale: timescale),
                timescale: timescale,
                fallbackFrame: 150_000
            ),
            120_000,
            "A later automatic-flush timestamp must remain eligible as the restart anchor"
        )
        XCTAssertEqual(
            RendererRecoveryTimeline.restartFrame(
                currentTime: .invalid,
                suggestedFlushTime: nil,
                timescale: timescale,
                fallbackFrame: 150_000
            ),
            150_000
        )
    }

    func testOutputReconfigurationGraceIncludesFiveSecondBoundary() {
        let start: UInt64 = 10_000
        XCTAssertTrue(
            OutputReconfigurationGrace.contains(
                startUptimeNanoseconds: start,
                nowUptimeNanoseconds: start + OutputReconfigurationGrace.durationNanoseconds
            )
        )
        XCTAssertFalse(
            OutputReconfigurationGrace.contains(
                startUptimeNanoseconds: start,
                nowUptimeNanoseconds: start + OutputReconfigurationGrace.durationNanoseconds + 1
            )
        )
    }

    func testCaptureRingPreservesStereoFramesAndConsumesPeak() throws {
        let bridge = SRAudioCaptureBridge()
        let input: [Float] = [0.25, -0.5, 0.75, -0.125, -0.2, 0.4]
        let data = input.withUnsafeBytes { Data($0) }

        bridge.debugEnqueueInterleavedFloat(data)

        XCTAssertEqual(bridge.availableFrameCount, 3)
        XCTAssertEqual(bridge.capturedFrameCount, 3)
        XCTAssertEqual(bridge.peakLevel, 0.75, accuracy: 0.0001)
        XCTAssertEqual(bridge.peakLevel, 0, accuracy: 0.0001)

        let firstChunk = try XCTUnwrap(bridge.dequeueChunk(withMaximumFrameCount: 2))
        XCTAssertEqual(firstChunk.frameCount, 2)
        XCTAssertEqual(floatArray(from: firstChunk.data), Array(input.prefix(4)))

        let secondChunk = try XCTUnwrap(bridge.dequeueChunk(withMaximumFrameCount: 8))
        XCTAssertEqual(secondChunk.frameCount, 1)
        XCTAssertEqual(floatArray(from: secondChunk.data), Array(input.suffix(2)))
        XCTAssertEqual(bridge.availableFrameCount, 0)
    }

    func testCaptureRingBoundsOverflowAndReportsDroppedFrames() {
        let bridge = SRAudioCaptureBridge()
        let capacity = 524_288
        let extraFrames = 17
        let input = [Float](repeating: 0.1, count: (capacity + extraFrames) * 2)

        bridge.debugEnqueueInterleavedFloat(input.withUnsafeBytes { Data($0) })

        XCTAssertEqual(bridge.availableFrameCount, UInt32(capacity))
        XCTAssertEqual(bridge.capturedFrameCount, UInt64(capacity))
        XCTAssertEqual(bridge.droppedFrameCount, UInt64(extraFrames))

        bridge.reset()
        XCTAssertEqual(bridge.availableFrameCount, 0)
        XCTAssertEqual(bridge.capturedFrameCount, 0)
        XCTAssertEqual(bridge.droppedFrameCount, 0)
    }

    func testCaptureRingPreservesOrderAcrossStorageWrap() throws {
        let bridge = SRAudioCaptureBridge()
        let capacity = 524_288
        let initialFrameCount = capacity - 2
        var initial = [Float]()
        initial.reserveCapacity(initialFrameCount * 2)
        for frame in 0..<initialFrameCount {
            initial.append(Float(frame))
            initial.append(-Float(frame))
        }
        bridge.debugEnqueueInterleavedFloat(initial.withUnsafeBytes { Data($0) })

        _ = try XCTUnwrap(
            bridge.dequeueChunk(withMaximumFrameCount: UInt32(initialFrameCount - 2))
        )

        let wrapped: [Float] = [
            1_000_001, -1_000_001,
            1_000_002, -1_000_002,
            1_000_003, -1_000_003,
            1_000_004, -1_000_004,
            1_000_005, -1_000_005,
            1_000_006, -1_000_006
        ]
        bridge.debugEnqueueInterleavedFloat(wrapped.withUnsafeBytes { Data($0) })

        let output = try XCTUnwrap(bridge.dequeueChunk(withMaximumFrameCount: 8))
        let expected = Array(initial.suffix(4)) + wrapped
        XCTAssertEqual(output.frameCount, 8)
        XCTAssertEqual(floatArray(from: output.data), expected)
    }

    func testApplicationBundleContainsStablePrivacyIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "local.codex.qq-spatial-relay")
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription"))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundlePackageType") as? String, "APPL")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }

    private func floatArray(from data: Data) -> [Float] {
        data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
    }
}
