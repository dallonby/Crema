import SwiftUI

extension Array where Element == CGPoint {
    /// Centered boxcar moving average on the y-axis only. X-coordinates preserved.
    /// Used as a pre-filter before spline interpolation to wash out the 0.1-bar and
    /// 1-mL quantization steps from the LITA's telemetry. The cursor dot stays on
    /// the raw sample so users still see the true reading; only the rendered curve
    /// becomes the "line of best fit through the noise."
    func ySmoothed(window: Int) -> [CGPoint] {
        guard window > 1, count > window else { return self }
        let h = window / 2
        var out = [CGPoint]()
        out.reserveCapacity(count)
        for i in 0..<count {
            let lo = Swift.max(0, i - h)
            let hi = Swift.min(count - 1, i + h)
            var sum: CGFloat = 0
            for j in lo...hi { sum += self[j].y }
            out.append(CGPoint(x: self[i].x, y: sum / CGFloat(hi - lo + 1)))
        }
        return out
    }
}

extension Path {
    /// Monotone cubic Hermite interpolation through the given points (Fritsch-Carlson).
    /// Renders each segment as a cubic Bézier whose tangents are chosen so the curve
    /// passes exactly through every input point AND never overshoots them — flat runs
    /// stay genuinely flat, and monotonic stretches (like cumulative volume) stay
    /// monotonic. The cursor dot still lands on the raw sample values.
    ///
    /// Why we need this here: telemetry comes off the LITA at ~3.4 Hz and is quantized
    /// to 0.1 bar / 0.1 mL/s on the wire. Drawing straight lines exposes every step as
    /// a tiny staircase. Vanilla Catmull-Rom smooths that out but ripples on flat runs
    /// and overshoots cumulative-volume samples. Fritsch-Carlson fixes both.
    static func smoothLine(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        let n = points.count
        if n == 1 { return path }
        if n == 2 { path.addLine(to: points[1]); return path }

        // Secant slopes between consecutive points
        var d = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = points[i + 1].x - points[i].x
            d[i] = dx == 0 ? 0 : (points[i + 1].y - points[i].y) / dx
        }

        // Initial tangents = average of adjacent secants; corner cases use the secant.
        var m = [CGFloat](repeating: 0, count: n)
        m[0]     = d[0]
        m[n - 1] = d[n - 2]
        for i in 1..<(n - 1) {
            // If sign changes (peak/trough) OR either secant is zero (flat), force flat
            // tangent. This is what kills ripples on quantized telemetry.
            if d[i - 1] * d[i] <= 0 { m[i] = 0 }
            else                    { m[i] = (d[i - 1] + d[i]) / 2 }
        }

        // Enforce monotonicity (Fritsch-Carlson): if the tangents are too steep relative
        // to the secant, scale them down so the cubic stays within [y_i, y_{i+1}].
        for i in 0..<(n - 1) {
            if d[i] == 0 { m[i] = 0; m[i + 1] = 0; continue }
            let alpha = m[i]     / d[i]
            let beta  = m[i + 1] / d[i]
            let s = alpha * alpha + beta * beta
            if s > 9 {
                let tau = 3 / s.squareRoot()
                m[i]     = tau * alpha * d[i]
                m[i + 1] = tau * beta  * d[i]
            }
        }

        // Hermite → Bézier: control points sit 1/3 of the segment along each tangent.
        for i in 0..<(n - 1) {
            let dx = points[i + 1].x - points[i].x
            let c1 = CGPoint(
                x: points[i].x + dx / 3,
                y: points[i].y + dx * m[i] / 3
            )
            let c2 = CGPoint(
                x: points[i + 1].x - dx / 3,
                y: points[i + 1].y - dx * m[i + 1] / 3
            )
            path.addCurve(to: points[i + 1], control1: c1, control2: c2)
        }
        return path
    }
}
