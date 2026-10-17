import XCTest
@testable import TeamStats

final class OperationDiagnosticsTests: XCTestCase {
    func testEmissionBudgetSurvivesResetAndReentrantSinkCannotRecurse() async throws {
        let probe = DiagnosticCallbackProbe(), clock = DiagnosticTestClock()
        let recorder = OperationDiagnostics(clock: { clock.value }) { line in probe.emit(line) }
        probe.recorder = recorder
        for expected in 1...32 {
            recorder.begin(.sharedLoad).finish(.failed, failure: .denied)
            for _ in 0..<100 where probe.count < expected { try await Task.sleep(for: .milliseconds(1)) }
            XCTAssertEqual(probe.count, expected)
            try await Task.sleep(for: .milliseconds(1))
        }
        recorder.reset()
        recorder.begin(.session).finish(.failed, failure: .storage)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(probe.count, 32)
        XCTAssertEqual(recorder.snapshot().suppressed, 1)
    }
    @MainActor func testMeasuredRecordingOverhead() {
        let recorder = OperationDiagnostics { _ in }
        for run in 0..<5 {
            let baselineStart = ProcessInfo.processInfo.systemUptime
            for _ in 0..<10_000 { _ = BoxScoreCount("0") }
            let baseline = ProcessInfo.processInfo.systemUptime - baselineStart
            let recordedStart = ProcessInfo.processInfo.systemUptime
            for _ in 0..<10_000 {
                _ = BoxScoreCount("0")
                recorder.begin(.sharedSave).finish(.succeeded)
            }
            let recorded = ProcessInfo.processInfo.systemUptime - recordedStart
            print("TEST ONLY DIAGNOSTIC overhead run=\(run) baselineSeconds=\(baseline) recordedSeconds=\(recorded) count=10000")
            XCTAssertEqual(recorder.snapshot().events.count, 64)
        }
    }
    func testActualEmittedEnvelopeIsClosedAndSinkFailureIsNonfatal() async throws {
        let output = expectation(description: "sanitized output")
        let recorder = OperationDiagnostics { line in
            let json = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            XCTAssertEqual(Set(json.keys), ["category", "outcome", "failure", "durationMS", "attempts"])
            XCTAssertEqual(json["category"] as? String, "sharedSave")
            XCTAssertEqual(json["outcome"] as? String, "unconfirmed")
            XCTAssertEqual(json["failure"] as? String, "unavailable")
            XCTAssertEqual(json["attempts"] as? Int, 1)
            print("TEST ONLY DIAGNOSTIC " + line)
            output.fulfill()
            throw CocoaError(.fileWriteOutOfSpace)
        }
        recorder.begin(.sharedSave).finish(.unconfirmed, failure: .unavailable)
        await fulfillment(of: [output], timeout: 2)
        for _ in 0..<100 where recorder.snapshot().sinkFailures == 0 { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(recorder.snapshot().sinkFailures, 1)
        XCTAssertEqual(recorder.snapshot().events.count, 1)
    }
    func testBoundedConcurrentEventsExpirationAndGenerationFence() async throws {
        let time = DiagnosticTestClock()
        let recorder = OperationDiagnostics(clock: { time.value }) { _ in }
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in recorder.begin(.sharedLoad).finish(.failed, failure: .denied) }
        XCTAssertEqual(recorder.snapshot().events.count, 64)
        XCTAssertEqual(recorder.snapshot().discarded, 936)
        let old = recorder.begin(.sharedSave)
        recorder.reset(); old.finish(.succeeded)
        XCTAssertTrue(recorder.snapshot().events.isEmpty)
        recorder.begin(.authentication, attempts: 100).finish(.cancelled, failure: .cancelled)
        XCTAssertEqual(recorder.snapshot().events.first?.attempts, 3)
        time.advance(900)
        XCTAssertTrue(recorder.snapshot().events.isEmpty)
    }
    func testBlockedSinkDoesNotQueueOrDelayCoreOperations() async throws {
        let started = expectation(description: "blocked sink started")
        let release = DispatchSemaphore(value: 0)
        let recorder = OperationDiagnostics { _ in started.fulfill(); release.wait() }
        recorder.begin(.session).finish(.failed, failure: .storage)
        await fulfillment(of: [started], timeout: 2)
        let start = ProcessInfo.processInfo.systemUptime
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in recorder.begin(.fileTransport).finish(.cancelled, failure: .cancelled) }
        let seconds = ProcessInfo.processInfo.systemUptime - start
        release.signal()
        XCTAssertEqual(recorder.snapshot().events.count, 64)
        print("TEST ONLY DIAGNOSTIC 1000 concurrent events seconds=\(seconds)")
    }
}
private final class DiagnosticTestClock: @unchecked Sendable {
    private let lock = NSLock(); private var time: TimeInterval = 1000
    var value: TimeInterval { lock.withLock { time } }
    func advance(_ seconds: TimeInterval) { lock.withLock { time += seconds } }
}

private final class DiagnosticCallbackProbe: @unchecked Sendable {
    weak var recorder: OperationDiagnostics?
    private let lock = NSLock(); private var emissions = 0
    var count: Int { lock.withLock { emissions } }
    func emit(_ line: String) {
        recorder?.note(.session, outcome: .failed, failure: .storage)
        lock.withLock { emissions += 1 }
    }
}
