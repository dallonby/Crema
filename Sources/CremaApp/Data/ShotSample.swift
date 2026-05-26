import Foundation
import CremaKit

/// One BLE telemetry sample from the machine (~3.4 Hz).
struct ShotSample: Sendable, Hashable {
    /// Seconds since the *start of the brew* (coil 150 ON), not since recording started.
    /// Samples captured before brew start carry `t = 0` and live in the warmup phase.
    let t: Double
    let pressureBar: Double
    let flowMlPerSec: Double
    let volumeMl: Double
    let brewTempC: Double
}

extension ShotSample {
    /// Bridge a CremaKit `LiveTelemetry` snapshot into a chart-ready sample.
    /// Flow is intentionally zero here — the playback engine recomputes it from
    /// dV/dt over a lookback window so the live and replay traces look identical
    /// (and reg 1422's flow value isn't trustworthy anyway — see PROTOCOL.md).
    init(from telemetry: LiveTelemetry) {
        self.init(
            t: telemetry.elapsedSeconds,
            pressureBar: telemetry.pressureBar,
            flowMlPerSec: 0,
            volumeMl: Double(telemetry.totalVolumeMl),
            brewTempC: telemetry.brewBoilerTempC
        )
    }
}

/// Parses the recorder CSV format from `record_brew.py`.
/// Columns: `t_ms,elapsed_brew_ms,pressure_bar,flow_ml_s,volume_ml,shot_time_s,progress_pct,brew_temp_c,steam_temp_c,raw_regs,event_hex`
enum BrewCSVLoader {
    static func load(resource: String, withExtension ext: String = "csv") throws -> [ShotSample] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            throw LoadError.notFound(resource)
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
        return parse(raw)
    }

    static func parse(_ raw: String) -> [ShotSample] {
        // First pass: parse the raw rows. Flow is *not* taken from reg 1422 —
        // see the second pass below.
        struct Row { let t: Double; let p: Double; let v: Double; let bT: Double }
        var rows: [Row] = []
        var firstBrewT: Double? = nil
        for (i, line) in raw.split(whereSeparator: \.isNewline).enumerated() {
            if i == 0 { continue }  // header
            let cols = splitCSV(String(line))
            guard cols.count >= 9 else { continue }
            let elapsedBrewMs = Double(cols[1])
            let pressure = Double(cols[2]) ?? 0
            let volume   = Double(cols[4]) ?? 0
            let brewT    = Double(cols[7]) ?? 0

            guard let ems = elapsedBrewMs else { continue }
            if firstBrewT == nil { firstBrewT = ems }
            let t = (ems - (firstBrewT ?? 0)) / 1000.0
            rows.append(Row(t: t, p: pressure, v: volume, bT: brewT))
        }

        // Second pass: derive flow from dV/dt of the volume column.
        //
        // Important: this is *pump flow into the puck*, not yield out of the spout.
        // Reg 1411 ("volume_ml") is the machine's count of mL the pump has pushed
        // through, not what landed in the cup. True yield (g/s out) needs a BLE
        // scale (Bookoo, Acaia, etc.) — that's a future series, drawn separately
        // and shown diverging below this curve as puck retention.
        //
        // Why dV/dt and not reg 1422: the recorded "flow_ml_s" register doesn't
        // line up with the volume integral on any clean scaling — its ratio to
        // dV/dt varies 0.97×–2.09× across bloom/soak/extract within a single shot.
        // It looks like a smoothed pressure/motor-current estimate of pump flow,
        // not direct pulse-counted throughput. The volume column is the truth for
        // pump-side mL — and dV/dt of the truth IS pump flow rate.
        //
        // 7-sample centered window soaks up the 1 mL quantization. The chart's
        // own pre-filter smooths further before rendering. Live mode will switch
        // to a lookback-only window since future samples won't be available.
        let window = 7
        let h = window / 2
        var out: [ShotSample] = []
        out.reserveCapacity(rows.count)
        for i in 0..<rows.count {
            let lo = Swift.max(0, i - h)
            let hi = Swift.min(rows.count - 1, i + h)
            let dv = rows[hi].v - rows[lo].v
            let dt = rows[hi].t - rows[lo].t
            let flow = dt > 0 ? dv / dt : 0
            out.append(ShotSample(
                t: rows[i].t,
                pressureBar: rows[i].p,
                flowMlPerSec: flow,
                volumeMl: rows[i].v,
                brewTempC: rows[i].bT
            ))
        }
        return out
    }

    /// Lightweight CSV split that respects double-quoted fields.
    private static func splitCSV(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == "," && !inQuotes {
                out.append(cur); cur = ""
            } else {
                cur.append(ch)
            }
        }
        out.append(cur)
        return out
    }

    enum LoadError: Error { case notFound(String) }
}
