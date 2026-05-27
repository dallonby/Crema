import Foundation

/// Generic BLE scale interface — abstracted so the auto-tune flow can read
/// live weight from any future Bookoo / Acaia / Felicita / Difluid integration
/// behind the same API.
///
/// The current shipped implementations are:
/// - `StubScale` — simulates a live shot's weight ramp (sim/dev).
/// - `ManualScale` — a no-op placeholder; the user types the final yield.
///
/// Real `BookooScaleTransport` etc. will land later — their BLE GATT specs
/// need to be captured against actual hardware (different services per brand).
/// Adding them is a matter of conforming to this protocol, not changing
/// callers.
public protocol ScaleTransport: Sendable {
    /// Current weight in grams. `nil` if not connected / not reading yet.
    func currentWeight() async -> Double?

    /// Async stream of (weight in grams) emitted at the scale's natural rate
    /// (~10 Hz for Bookoo Themis Mini). Stream ends when the transport
    /// disconnects.
    func weightStream() -> AsyncStream<Double>

    /// Best-effort tare. Some manual scales obviously don't support this.
    func tare() async

    /// Human-readable name for the connected device, or nil if none.
    var connectedName: String? { get }
}

// MARK: - Stub

/// Simulated scale for use in the simulator and in unit tests. Models a
/// realistic-feeling yield ramp: starts at 0 g, no flow for the first ~6 s
/// (preinfusion), then accelerates, then tapers.
public final class StubScale: ScaleTransport, @unchecked Sendable {
    /// Total grams this stub will report by the end of its simulated shot.
    private let targetG: Double
    /// Total shot duration this stub models.
    private let durationS: Double
    private let startedAt: Date

    public let connectedName: String? = "Sim Scale"

    public init(targetG: Double = 36, durationS: Double = 28) {
        self.targetG = targetG
        self.durationS = durationS
        self.startedAt = Date()
    }

    /// Sigmoidal ramp: gentle start (preinfusion), peak flow mid-shot, taper.
    private func weight(at t: Double) -> Double {
        let frac = max(0, min(1, t / durationS))
        // Smoothstep with bias toward the back half — realistic for espresso.
        let bias = pow(frac, 1.4)
        let smooth = bias * bias * (3 - 2 * bias)
        return targetG * smooth
    }

    public func currentWeight() async -> Double? {
        let t = Date().timeIntervalSince(startedAt)
        return weight(at: t)
    }

    public func weightStream() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                let interval: UInt64 = 100_000_000  // 100 ms
                while !Task.isCancelled {
                    let t = Date().timeIntervalSince(self.startedAt)
                    continuation.yield(self.weight(at: t))
                    if t > self.durationS + 2 { break }
                    try? await Task.sleep(nanoseconds: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func tare() async { /* stub does nothing */ }
}

// MARK: - Manual entry

/// Placeholder transport for users without a BLE scale — the UI will prompt
/// for the final yield by hand. Methods return nothing / empty streams.
public final class ManualScale: ScaleTransport, @unchecked Sendable {
    public let connectedName: String? = nil
    public init() {}
    public func currentWeight() async -> Double? { nil }
    public func weightStream() -> AsyncStream<Double> {
        AsyncStream { $0.finish() }
    }
    public func tare() async {}
}
