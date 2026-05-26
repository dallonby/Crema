import Foundation
import SwiftUI
import CremaKit

/// Owns the shot timeline as the chart sees it — the list of `ShotSample`s and
/// the current playhead `t`. Two operating modes:
///
/// - **Replay**: samples are loaded up-front from a CSV, `advance(by:)` drives
///   the playhead. The chart animates as if the machine were brewing in real
///   time.
/// - **Live**: samples are empty at start and appended as the machine pushes
///   telemetry. The playhead `t` tracks the latest sample's timestamp.
///   `advance(by:)` is a no-op — wall-clock comes from the machine itself.
///
/// The same view code renders both. The `LiveDriver` class wires up the
/// transport in live mode.
@MainActor
@Observable
final class ShotPlayback {
    private(set) var samples: [ShotSample]
    let profile: BrewProfile
    let isLiveDriven: Bool

    /// Playhead in seconds (since brew start).
    private(set) var t: Double = 0
    private(set) var isPlaying = false
    var speed: Double = 1.0

    /// All samples up to and including the playhead — what the chart renders as the live trace.
    var emitted: ArraySlice<ShotSample> {
        guard !samples.isEmpty else { return [][...] }
        var upper = samples.count
        for i in samples.indices where samples[i].t > t {
            upper = i
            break
        }
        return samples[..<upper]
    }

    /// Linearly-interpolated current sample at `t` (replay), or the most recent
    /// raw sample (live — interpolating between samples that arrive in real time
    /// would lag by half a sample period and hide reality).
    var currentSample: ShotSample? {
        if isLiveDriven { return samples.last }
        guard let first = samples.first else { return nil }
        if t <= first.t { return first }
        guard let last = samples.last else { return nil }
        if t >= last.t { return last }
        for i in 1..<samples.count {
            let a = samples[i - 1]
            let b = samples[i]
            if b.t >= t {
                let span = b.t - a.t
                let f = span > 0 ? (t - a.t) / span : 0
                return ShotSample(
                    t: t,
                    pressureBar: lerp(a.pressureBar, b.pressureBar, f),
                    flowMlPerSec: lerp(a.flowMlPerSec, b.flowMlPerSec, f),
                    volumeMl: lerp(a.volumeMl, b.volumeMl, f),
                    brewTempC: lerp(a.brewTempC, b.brewTempC, f)
                )
            }
        }
        return last
    }

    var totalDuration: Double {
        max(profile.totalDuration, samples.last?.t ?? 0)
    }

    var hasEnded: Bool { t >= totalDuration }

    /// Replay-mode initializer — preloaded samples drive a virtual playback.
    init(samples: [ShotSample], profile: BrewProfile) {
        self.samples = samples
        self.profile = profile
        self.isLiveDriven = false
    }

    /// Live-mode initializer — samples start empty and accumulate as the machine
    /// pushes telemetry. `LiveDriver` is the orchestrator.
    init(liveProfile profile: BrewProfile) {
        self.samples = []
        self.profile = profile
        self.isLiveDriven = true
    }

    func play()  { isPlaying = true }
    func pause() { isPlaying = false }
    func toggle() { isPlaying.toggle() }
    func reset() {
        t = 0
        isPlaying = false
        if isLiveDriven { samples.removeAll(keepingCapacity: true) }
    }
    func scrub(to newT: Double) {
        guard !isLiveDriven else { return }   // can't scrub a live shot
        t = max(0, min(totalDuration, newT))
    }

    /// Advance the playhead — replay mode only. Live mode drives `t` from sample
    /// timestamps.
    func advance(by dt: Double) {
        guard !isLiveDriven, isPlaying else { return }
        t += dt * speed
        if t >= totalDuration {
            t = totalDuration
            isPlaying = false
        }
    }

    /// Live mode: a new telemetry sample arrived. Append it, advance `t` to
    /// match, and recompute the flow series via dV/dt over a lookback window
    /// so the curve matches what the recorder produces in replay mode.
    func appendLive(_ sample: ShotSample) {
        guard isLiveDriven else { return }
        samples.append(sample)
        t = sample.t
        if !isPlaying { isPlaying = true }
        recomputeRecentFlow()
    }

    /// Update the trailing N samples' `flowMlPerSec` using a lookback-only
    /// centered window over the volume column. Same algorithm as the replay-mode
    /// CSV loader, adapted for the live "no future samples" constraint.
    private func recomputeRecentFlow() {
        let lookback = 7
        guard samples.count >= 2 else { return }
        let start = Swift.max(0, samples.count - lookback - 1)
        for i in start..<samples.count {
            let lo = Swift.max(0, i - lookback / 2)
            let hi = i  // no future
            let dv = samples[hi].volumeMl - samples[lo].volumeMl
            let dt = samples[hi].t - samples[lo].t
            let flow = dt > 0 ? dv / dt : 0
            samples[i] = ShotSample(
                t: samples[i].t,
                pressureBar: samples[i].pressureBar,
                flowMlPerSec: flow,
                volumeMl: samples[i].volumeMl,
                brewTempC: samples[i].brewTempC
            )
        }
    }

    private func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double {
        a + (b - a) * f
    }
}
