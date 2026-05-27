import SwiftUI
import CremaKit

/// The bottom of the Live Shot screen — the primary action surface.
///
/// Replaces the playback-style bar in `.live` mode. Designed for full-screen use
/// on macOS, iOS, iPadOS, and Android (via future Compose port): one obvious next
/// action at any moment, scales from phone-portrait to mac-full-screen without
/// breaking. No hardcoded pixel widths.
///
/// State-driven layout:
/// - **Disconnected / failed** → big "Connect" pill, centered
/// - **Scanning / connecting** → progress indicator with cancel
/// - **Connected · ready**    → connection chip (left) + big "Brew" pill (right)
/// - **Brewing**              → connection chip dimmed + "Abort" pill in danger color
/// - **Done**                 → "Save / Discard / Brew Again" trio
struct BrewActionZone: View {
    @Binding var mode: AppMode
    let liveDriver: LiveDriver
    let replayPlayback: ShotPlayback
    let library: ProfileLibrary
    let history: ShotHistory
    let tipPreferences: TipPreferences
    /// Parent-owned callback to spin up an AutoTuneSession + present its sheet.
    /// Optional so the macOS / iPhone-portrait paths can omit if needed.
    var onAutoTune: (() -> Void)? = nil

    var body: some View {
        Group {
            if mode == .replay {
                ReplayPlaybackBar(playback: replayPlayback)
            } else {
                LiveBrewBar(driver: liveDriver, library: library,
                            history: history, tipPreferences: tipPreferences,
                            onAutoTune: onAutoTune)
            }
        }
        .animation(.smooth(duration: 0.35), value: mode)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        // Floating frosted bar that sits above the chart, with breathing room.
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5)
                )
                .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Auto-tune entry chip

/// Compact secondary action that sits beside the Brew button when the machine
/// is ready. Subtle sparkle treatment to signal "smart, novel feature" without
/// shouting over the primary Brew action.
private struct AutoTuneChip: View {
    let action: () -> Void
    @State private var glimmer = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating, value: glimmer)
                Text("Auto-tune")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(CremaColor.crema)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(
                Capsule().fill(CremaColor.crema.opacity(0.16))
                    .overlay(Capsule().strokeBorder(CremaColor.crema.opacity(0.4), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .onAppear { glimmer = true }
    }
}

// MARK: - Live brew bar (state-driven)

private struct LiveBrewBar: View {
    @Bindable var driver: LiveDriver
    let library: ProfileLibrary
    @Bindable var history: ShotHistory
    @Bindable var tipPreferences: TipPreferences
    var onAutoTune: (() -> Void)? = nil
    @State private var showMachines = false
    @State private var showFeedback = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    #else
    private var isCompact: Bool { false }
    #endif

    var body: some View {
        Group {
            switch phase {
            case .needsSetup:
                VStack(spacing: 10) {
                    CenterPrimaryButton(
                        label: "Set up your machine",
                        systemImage: "wave.3.right",
                        tint: .crema,
                        action: { showMachines = true }
                    )
                    Text("Pair your Wendougee over Bluetooth to brew. The curve above is your selected recipe — tap its name to switch.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(CremaColor.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .primaryDisconnected(let name):
                ResponsiveTwoSlot(
                    isCompact: isCompact,
                    leading: { MachinesMenuButton(driver: driver, showSheet: $showMachines) },
                    trailing: {
                        PrimaryPill(label: "Connect to \(name)",
                                    systemImage: "wave.3.right",
                                    tint: .crema, pulsing: true,
                                    action: { driver.connectToPrimary() })
                    }
                )
            case .scanning(let msg):
                ProgressRow(text: msg, onCancel: { driver.stop() })
            case .readyToBrew(let name):
                ResponsiveTwoSlot(
                    isCompact: isCompact,
                    leading: {
                        ConnectionChip(name: name, active: true, isDimmed: false,
                                       onTap: { showMachines = true })
                    },
                    trailing: {
                        HStack(spacing: 10) {
                            if let onAutoTune {
                                AutoTuneChip(action: onAutoTune)
                            }
                            if driver.playback.profile.grinder != nil {
                                GrinderPill(driver: driver)
                            }
                            PrimaryPill(label: "Brew",
                                        systemImage: "drop.fill",
                                        tint: .crema, pulsing: true,
                                        action: { driver.brew() })
                        }
                    }
                )
            case .brewing(let name):
                ResponsiveTwoSlot(
                    isCompact: isCompact,
                    leading: {
                        ConnectionChip(name: name, active: true, isDimmed: true, onTap: nil)
                    },
                    trailing: {
                        PrimaryPill(label: "Abort",
                                    systemImage: "stop.fill",
                                    tint: .danger, pulsing: false,
                                    action: { driver.abort() })
                    }
                )
            case .done(let name):
                if isCompact {
                    VStack(spacing: 10) {
                        ConnectionChip(name: name, active: true, isDimmed: false,
                                       onTap: { showMachines = true })
                        HStack(spacing: 8) {
                            SecondaryPill(label: "Discard", systemImage: "trash",
                                          action: { driver.clearShot() })
                            SecondaryPill(label: "Brew again", systemImage: "arrow.clockwise",
                                          action: { driver.clearShot(); driver.brew() })
                        }
                        PrimaryPill(label: "Save & Suggest",
                                    systemImage: "square.and.arrow.down",
                                    tint: .crema, pulsing: false,
                                    action: { showFeedback = true })
                    }
                } else {
                    HStack(spacing: 12) {
                        ConnectionChip(name: name, active: true, isDimmed: false,
                                       onTap: { showMachines = true })
                        Spacer(minLength: 8)
                        SecondaryPill(label: "Discard", systemImage: "trash",
                                      action: { driver.clearShot() })
                        SecondaryPill(label: "Brew again", systemImage: "arrow.clockwise",
                                      action: { driver.clearShot(); driver.brew() })
                        PrimaryPill(label: "Save & Suggest",
                                    systemImage: "square.and.arrow.down",
                                    tint: .crema, pulsing: false,
                                    action: { showFeedback = true })
                    }
                }
            case .failed(let reason):
                if isCompact {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            StatusGlyph(systemImage: "exclamationmark.triangle.fill", tint: .danger)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connection failed")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(CremaColor.cream)
                                Text(reason)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(CremaColor.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            SecondaryPill(label: "Machines", systemImage: "antenna.radiowaves.left.and.right",
                                          action: { showMachines = true })
                            PrimaryPill(label: "Retry", systemImage: "arrow.clockwise",
                                        tint: .crema, pulsing: false,
                                        action: { driver.connectToPrimary() })
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        StatusGlyph(systemImage: "exclamationmark.triangle.fill", tint: .danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connection failed")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(CremaColor.cream)
                            Text(reason)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(CremaColor.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        SecondaryPill(label: "Machines", systemImage: "antenna.radiowaves.left.and.right",
                                      action: { showMachines = true })
                        PrimaryPill(label: "Retry", systemImage: "arrow.clockwise",
                                    tint: .crema, pulsing: false,
                                    action: { driver.connectToPrimary() })
                    }
                }
            }
        }
        .sheet(isPresented: $showMachines) {
            MachinesView(driver: driver)
        }
        .sheet(isPresented: $showFeedback) {
            ShotFeedbackSheet(
                profile: driver.playback.profile,
                actualTimeS: driver.playback.t,
                curve: capturedCurve,
                history: history,
                tipPreferences: tipPreferences,
                library: library
            )
        }
    }

    /// Snapshot the playback's samples as the persisted curve for history.
    private var capturedCurve: [ShotLog.Sample] {
        driver.playback.samples.map {
            ShotLog.Sample(t: $0.t, pressureBar: $0.pressureBar, volumeMl: $0.volumeMl)
        }
    }

    // MARK: phase derivation

    private enum Phase: Hashable {
        case needsSetup
        case primaryDisconnected(String)
        case scanning(String)
        case readyToBrew(String)
        case brewing(String)
        case done(String)
        case failed(String)
    }

    private var phase: Phase {
        if let err = driver.lastError, case .idle = driver.state {
            return .failed(err)
        }
        switch driver.state {
        case .idle:
            if let primary = driver.registry.primary {
                return .primaryDisconnected(primary.displayName)
            }
            return .needsSetup
        case .scanning:
            return .scanning("Scanning for nearby machines…")
        case .discovered(let name, _):
            return .scanning("Found \(name) — connecting…")
        case .connecting(let name):
            return .scanning("Connecting to \(prettyName(name))…")
        case .disconnecting:
            return .scanning("Disconnecting…")
        case .failed(let reason):
            return .failed(reason)
        case .connected(let name):
            let pretty = displayNameForConnected(name)
            switch driver.brewState {
            case .ready:   return .readyToBrew(pretty)
            case .brewing: return .brewing(pretty)
            case .done:    return .done(pretty)
            }
        }
    }

    /// Prefer the registry's nickname/displayName over the raw advertised name
    /// (e.g. "Sunday Lita" instead of "WDG · AB071169…").
    private func displayNameForConnected(_ advertisedName: String) -> String {
        if let m = driver.registry.machines.first(where: { $0.advertisedName == advertisedName }) {
            return m.displayName
        }
        return prettyName(advertisedName)
    }

    private func prettyName(_ s: String) -> String {
        if let after = s.split(separator: "_").last {
            return "WDG · \(after.prefix(8))…"
        }
        return s
    }
}

/// Small "···" button that opens the Machines sheet — used when we're not yet
/// connected so the user can swap primary / scan for new ones.
private struct MachinesMenuButton: View {
    let driver: LiveDriver
    @Binding var showSheet: Bool

    var body: some View {
        Button(action: { showSheet = true }) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .medium))
                Text("Machines")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(CremaColor.secondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .cremaGlass(in: Capsule())
        }
        .buttonStyle(PressDownStyle())
    }
}

// MARK: - Replay playback bar (unchanged behavior, extracted)

private struct ReplayPlaybackBar: View {
    @Bindable var playback: ShotPlayback

    var body: some View {
        HStack(spacing: 22) {
            Button(action: { playback.reset() }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(CremaColor.secondary)
                    .frame(width: 36, height: 36)
                    .cremaGlass(in: Circle())
            }
            .buttonStyle(.plain)

            Button(action: { playback.toggle() }) {
                ZStack {
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
                        .overlay(Circle().strokeBorder(CremaColor.cream.opacity(0.25), lineWidth: 0.5))
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CremaColor.bg)
                        .contentTransition(.symbolEffect(.replace))
                        .offset(x: playback.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                let frac = playback.t / max(0.001, playback.totalDuration)
                ZStack(alignment: .leading) {
                    Capsule().fill(CremaColor.hairline).frame(height: 3)
                    Capsule()
                        .fill(LinearGradient(colors: [CremaColor.crema, CremaColor.cremaBright],
                                              startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(frac), height: 3)
                    Circle().fill(CremaColor.cream).frame(width: 14, height: 14)
                        .shadow(color: CremaColor.crema.opacity(0.55), radius: 6)
                        .offset(x: geo.size.width * CGFloat(frac) - 7)
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { v in
                        let f = max(0, min(1, v.location.x / geo.size.width))
                        playback.scrub(to: f * playback.totalDuration)
                    }
                )
            }
            .frame(height: 14)

            Menu {
                ForEach([0.5, 1.0, 1.5, 2.0, 4.0], id: \.self) { s in
                    Button(s == 1.0 ? "1×" : (s.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(s))×" : "\(s)×")) {
                        playback.speed = s
                    }
                }
            } label: {
                Text(playback.speed == 1.0 ? "1×" :
                     (playback.speed.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(playback.speed))×" : String(format: "%.1f×", playback.speed)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.cream)
                    .frame(width: 40, height: 28)
                    .cremaGlass(in: Capsule())
            }
            .menuStyle(.borderlessButton)
        }
    }
}

// MARK: - Building blocks

private enum PillTint { case crema, danger }
private extension PillTint {
    var fill: LinearGradient {
        switch self {
        case .crema:  return LinearGradient(colors: [CremaColor.cremaBright, CremaColor.crema],
                                            startPoint: .topLeading, endPoint: .bottomTrailing)
        case .danger: return LinearGradient(colors: [CremaColor.danger, CremaColor.danger.opacity(0.85)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    var halo: Color {
        switch self {
        case .crema:  return CremaColor.crema.opacity(0.35)
        case .danger: return CremaColor.danger.opacity(0.35)
        }
    }
}

/// Big primary action — used for Brew, Abort, Connect, Retry, Brew again.
/// Adaptive width: at narrow widths it stretches; at wide widths it caps at 280pt
/// so it looks like a deliberate CTA, not a stretched-out bar.
private struct PrimaryPill: View {
    let label: String
    let systemImage: String
    let tint: PillTint
    let pulsing: Bool
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tracking(0.3)
            }
            .foregroundStyle(CremaColor.bg)
            .frame(maxWidth: 280, minHeight: 48)
            .frame(maxWidth: .infinity)        // grow on narrow widths
            .padding(.horizontal, 22)
            .background {
                Capsule().fill(tint.fill)
                    .overlay(Capsule().strokeBorder(CremaColor.cream.opacity(0.2), lineWidth: 0.5))
            }
            .background {
                if pulsing {
                    Capsule().fill(tint.halo)
                        .blur(radius: 18)
                        .scaleEffect(pulse ? 1.08 : 1.0)
                        .opacity(pulse ? 0.0 : 0.9)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
                }
            }
        }
        .buttonStyle(PressDownStyle())
        .frame(maxWidth: 280)               // hard cap on wide layouts
        .onAppear { if pulsing { pulse = true } }
    }
}

private struct SecondaryPill: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(CremaColor.cream)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .cremaGlass(in: Capsule())
        }
        .buttonStyle(PressDownStyle())
    }
}

/// Connection state pill — `●  Sunday Lita ⋯` style. Tap to manage machines.
private struct ConnectionChip: View {
    let name: String
    let active: Bool
    let isDimmed: Bool
    let onTap: (() -> Void)?

    var body: some View {
        let chip = HStack(spacing: 8) {
            Circle()
                .fill(active ? CremaColor.connected : CremaColor.secondary)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().fill(active ? CremaColor.connected.opacity(0.45) : .clear)
                        .frame(width: 14, height: 14)
                        .blur(radius: 3)
                )
            Text(name)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            if onTap != nil {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundStyle(CremaColor.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .cremaGlass(in: Capsule())
        .opacity(isDimmed ? 0.55 : 1.0)

        if let onTap {
            Button(action: onTap) { chip }.buttonStyle(.plain)
        } else {
            chip
        }
    }
}

/// Centered primary button — used as the standalone "Connect" CTA when nothing
/// else is going on. Same `PrimaryPill` look but centered with `Spacer`s.
private struct CenterPrimaryButton: View {
    let label: String
    let systemImage: String
    let tint: PillTint
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            PrimaryPill(label: label, systemImage: systemImage,
                        tint: tint, pulsing: true, action: action)
            Spacer()
        }
    }
}

private struct ProgressRow: View {
    let text: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .tint(CremaColor.crema)
            Text(text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
            SecondaryPill(label: "Cancel", systemImage: "xmark", action: onCancel)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
    }
}

private struct StatusGlyph: View {
    let systemImage: String
    let tint: PillTint
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint == .danger ? CremaColor.danger : CremaColor.crema)
            .frame(width: 36, height: 36)
    }
}

/// Two-slot layout (status on the left, primary action on the right) that
/// becomes a vertical stack on compact width so labels never get clipped.
/// Used by all the "[status]  ←spacer→  [BREW / CONNECT / ABORT]" rows.
private struct ResponsiveTwoSlot<Leading: View, Trailing: View>: View {
    let isCompact: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        if isCompact {
            VStack(spacing: 10) {
                leading()
                trailing()
            }
        } else {
            HStack(spacing: 16) {
                leading()
                Spacer(minLength: 12)
                trailing()
            }
        }
    }
}

/// Secondary action button shown next to Brew when the active profile carries
/// grinder settings. Tap pushes the FF55 grinder command and shows a brief
/// "✓ Sent" confirmation so the user knows it landed (since the firmware
/// doesn't produce a parseable ack for this write).
private struct GrinderPill: View {
    let driver: LiveDriver
    @State private var justSent = false

    var body: some View {
        Button(action: {
            driver.sendGrinderSettings()
            justSent = true
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                justSent = false
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: justSent ? "checkmark" : "circle.hexagongrid.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(justSent ? "Sent" : "Set grinder")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .contentTransition(.identity)
            }
            .foregroundStyle(CremaColor.cream)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(
                        justSent ? CremaColor.connected.opacity(0.7) : CremaColor.hairline.opacity(0.6),
                        lineWidth: 0.5))
            }
        }
        .buttonStyle(PressDownStyle())
        .animation(.snappy(duration: 0.22), value: justSent)
    }
}

/// Press-down feedback — scale + slight opacity dip. Same feel on mac and iOS.
private struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
