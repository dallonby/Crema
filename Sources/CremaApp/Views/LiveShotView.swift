import SwiftUI
import CremaKit

/// Hero composition: header → chart → metric HUD → stage timeline → playback bar.
/// The chart auto-advances using a `TimelineView(.animation)` so the playhead glides
/// at display refresh (60/120Hz) even though the underlying data is 3.4Hz.
struct LiveShotView: View {
    @Binding var mode: AppMode
    @State var replayPlayback: ShotPlayback
    @State var liveDriver: LiveDriver
    @Bindable var library: ProfileLibrary
    @Bindable var history: ShotHistory
    @Bindable var tipPreferences: TipPreferences
    @Bindable var session: SignedInUser

    @State private var showLibrary = false
    @State private var showHistory = false
    @State private var autoTuneSession: AutoTuneSession?

    /// Whichever engine is currently driving the chart.
    private var playback: ShotPlayback {
        switch mode {
        case .replay: return replayPlayback
        case .live:   return liveDriver.playback
        }
    }

    var body: some View {
        // `.animation` schedule only fires WHILE animations are active, which
        // makes it unreliable here — we need a continuous tick. `.periodic`
        // is guaranteed to fire at the requested cadence.
        //
        // CRITICAL: the advance() call MUST be deferred outside the view
        // builder. Mutating @State (lastTick) or @Observable state
        // (playback.t) during view evaluation is a hard SwiftUI rule
        // violation — the mutations were being dropped silently, which is
        // why the chart never moved despite isPlaying=true. Dispatching
        // back to the main queue puts the mutation after the current view
        // update completes.
        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
            // Multiple statements + content view → use explicit return so the
            // ViewBuilder can infer the result type.
            let date = timeline.date
            DispatchQueue.main.async { advance(to: date) }
            return content
        }
    }

    @State private var lastTick: Date = .now

    /// Spin up a fresh AutoTuneSession with a scale-of-the-day. Today that's
    /// `StubScale` everywhere (simulated weight ramp) — a real Bookoo / Acaia
    /// BLE transport will plug in here later. The user can also fall back to
    /// `ManualScale()` if they explicitly want manual-only entry.
    @MainActor
    private func startAutoTune() {
        #if targetEnvironment(simulator)
        let scale: ScaleTransport = StubScale(
            targetG: 36, durationS: 28
        )
        #else
        // No real BLE scale wired up yet — manual entry only on device.
        let scale: ScaleTransport = ManualScale()
        #endif
        autoTuneSession = AutoTuneSession(
            liveDriver: liveDriver,
            library: library,
            scale: scale
        )
    }

    @MainActor
    private func advance(to date: Date) {
        let dt = date.timeIntervalSince(lastTick)
        lastTick = date
        if playback.isPlaying, dt > 0, dt < 0.5 {
            playback.advance(by: dt)
        }
    }

    private var content: some View {
        ZStack {
            // Background: warm radial glow upper-right fading into near-black.
            // Feels like crema crowning at the top of a freshly-pulled cup.
            CremaColor.bg.ignoresSafeArea()
            CremaGradient.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .padding(.bottom, 14)
                    .opacity(playback.isPlaying ? 0.4 : 1.0)
                    .animation(.easeInOut(duration: 0.6), value: playback.isPlaying)

                ShotChart(
                    samples: playback.emitted,
                    profile: playback.profile,
                    playhead: playback.t,
                    totalDuration: playback.totalDuration
                )
                .padding(.horizontal, 22)
                .frame(maxHeight: .infinity)

                MetricHUD(
                    pressure: playback.currentSample?.pressureBar ?? 0,
                    flow:     playback.currentSample?.flowMlPerSec ?? 0,
                    volume:   playback.currentSample?.volumeMl ?? 0,
                    elapsed:  playback.t
                )
                .padding(.horizontal, 22)
                .padding(.top, 12)

                StageTimeline(profile: playback.profile, playhead: playback.t)
                    .frame(height: 56)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)

                BrewActionZone(
                    mode: $mode,
                    liveDriver: liveDriver,
                    replayPlayback: replayPlayback,
                    library: library,
                    history: history,
                    tipPreferences: tipPreferences,
                    onAutoTune: { startAutoTune() }
                )
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }

            // Subtle vignette to focus the eye on the chart
            CremaGradient.vignette
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Dim scrim when a modal sheet is up. iPad form-sheet presentation
            // applies a very faint system dim; this adds enough additional
            // darkness to clearly focus attention on the modal. On iPhone the
            // sheet covers the screen anyway, so the scrim has no visible
            // effect there. On macOS dialogs sit over a single window — this
            // scrim makes the focus shift obvious.
            Color.black
                .opacity(showLibrary ? 0.45 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.25), value: showLibrary)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLibrary) {
            ProfilesView(library: library, session: session)
        }
        #if os(iOS)
        .fullScreenCover(item: $autoTuneSession) { session in
            AutoTuneSheet(session: session, onClose: { autoTuneSession = nil })
        }
        #else
        .sheet(item: $autoTuneSession) { session in
            AutoTuneSheet(session: session, onClose: { autoTuneSession = nil })
                .frame(minWidth: 700, minHeight: 720)
        }
        #endif
        .sheet(isPresented: $showHistory) {
            ShotHistoryView(history: history)
        }
    }

    // MARK: - Header

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var headerSizeClass
    #endif

    private var isCompactHeader: Bool {
        #if os(iOS)
        return headerSizeClass == .compact
        #else
        return false
        #endif
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            ZStack {
                Circle()
                    .fill(CremaColor.crema.opacity(0.25))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(CremaColor.crema)
                    .frame(width: 8, height: 8)
            }
            Button(action: { showLibrary = true }) {
                HStack(spacing: 4) {
                    Text(playback.profile.name)
                        .font(CremaFont.headerTitle)
                        .foregroundStyle(CremaColor.cream)
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CremaColor.secondary)
                }
            }
            .buttonStyle(.plain)
            // iPhone portrait drops the dose / ratio meta — there's no room.
            if !isCompactHeader {
                Text("·")
                    .foregroundStyle(CremaColor.secondary)
                Text("18.0 g → 36.0 g")
                    .font(CremaFont.headerMeta)
                    .foregroundStyle(CremaColor.secondary)
                Text("·")
                    .foregroundStyle(CremaColor.secondary)
                Text("ratio 1 : 2.0")
                    .font(CremaFont.headerMeta)
                    .foregroundStyle(CremaColor.secondary)
            }
            Spacer()
            historyButton
            modePill
            Text(String(format: "%05.2f s", playback.t))
                .font(.system(size: 13, weight: .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(CremaColor.secondary)
                .fixedSize()
        }
    }

    private var historyButton: some View {
        Button(action: { showHistory = true }) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CremaColor.secondary)
                .frame(width: 44, height: 44)   // proper hit target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Tiny mode switcher in the header — a dev affordance, NOT a primary
    /// control. The primary actions (connect, brew) live in `BrewActionZone`.
    /// Just flips the data source; doesn't auto-connect or auto-brew, those
    /// are explicit user actions in their own zone.
    private var modePill: some View {
        HStack(spacing: 0) {
            modeChip(label: "Live", active: mode == .live) {
                mode = .live
                replayPlayback.pause()
            }
            modeChip(label: "Demo", active: mode == .replay) {
                mode = .replay
                liveDriver.stop()
                replayPlayback.reset()
                replayPlayback.play()
            }
        }
        .padding(2)
        .background(
            Capsule().fill(CremaColor.surface.opacity(0.5))
                .overlay(Capsule().strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
        )
        .opacity(0.7)
    }

    private func modeChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(active ? CremaColor.cream : CremaColor.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(active ? CremaColor.hairline.opacity(0.8) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playback bar (prototype-only — replaced by physical brew controls later)

    private var playbackBar: some View {
        HStack(spacing: 22) {
            Button(action: {
                playback.reset()
                if mode == .live { liveDriver.brew() }
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(CremaColor.secondary)
                    .frame(width: 36, height: 36)
                    .cremaGlass(in: Circle())
            }
            .buttonStyle(.plain)

            Button(action: {
                if mode == .live {
                    if !playback.isPlaying { liveDriver.brew() }
                } else {
                    playback.toggle()
                }
            }) {
                ZStack {
                    // Soft halo behind the play button
                    Circle()
                        .fill(CremaColor.crema.opacity(0.25))
                        .frame(width: 64, height: 64)
                        .blur(radius: 14)
                    Circle()
                        .fill(LinearGradient(
                            colors: [CremaColor.cremaBright, CremaColor.crema],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle().strokeBorder(CremaColor.cream.opacity(0.25), lineWidth: 0.5)
                        )
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CremaColor.bg)
                        .contentTransition(.symbolEffect(.replace))
                        .offset(x: playback.isPlaying ? 0 : 2)  // optical center for play triangle
                }
            }
            .buttonStyle(.plain)

            // Scrubber
            GeometryReader { geo in
                let frac = playback.t / max(0.001, playback.totalDuration)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CremaColor.hairline)
                        .frame(height: 3)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [CremaColor.crema, CremaColor.cremaBright],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(frac), height: 3)
                    Circle()
                        .fill(CremaColor.cream)
                        .frame(width: 14, height: 14)
                        .shadow(color: CremaColor.crema.opacity(0.55), radius: 6)
                        .offset(x: geo.size.width * CGFloat(frac) - 7)
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let f = max(0, min(1, v.location.x / geo.size.width))
                            playback.scrub(to: f * playback.totalDuration)
                        }
                )
            }
            .frame(height: 14)

            // Speed
            Menu {
                ForEach([0.5, 1.0, 1.5, 2.0, 4.0], id: \.self) { s in
                    Button(speedString(s)) {
                        playback.speed = s
                    }
                }
            } label: {
                Text(speedLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.cream)
                    .frame(width: 40, height: 28)
                    .cremaGlass(in: Capsule())
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func speedString(_ s: Double) -> String {
        if s == 1.0 { return "1×" }
        if s.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(s))×" }
        return String(format: "%.1f×", s)
    }
    private var speedLabel: String { speedString(playback.speed) }
}
