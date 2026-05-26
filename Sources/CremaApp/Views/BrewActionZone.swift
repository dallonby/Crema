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

    var body: some View {
        Group {
            if mode == .replay {
                ReplayPlaybackBar(playback: replayPlayback)
            } else {
                LiveBrewBar(driver: liveDriver)
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

// MARK: - Live brew bar (state-driven)

private struct LiveBrewBar: View {
    @Bindable var driver: LiveDriver
    @State private var showMachines = false

    var body: some View {
        Group {
            switch phase {
            case .needsSetup:
                CenterPrimaryButton(
                    label: "Set up your machine",
                    systemImage: "wave.3.right",
                    tint: .crema,
                    action: { showMachines = true }
                )
            case .primaryDisconnected(let name):
                HStack(spacing: 16) {
                    MachinesMenuButton(driver: driver, showSheet: $showMachines)
                    Spacer(minLength: 12)
                    PrimaryPill(label: "Connect to \(name)",
                                systemImage: "wave.3.right",
                                tint: .crema, pulsing: true,
                                action: { driver.connectToPrimary() })
                }
            case .scanning(let msg):
                ProgressRow(text: msg, onCancel: { driver.stop() })
            case .readyToBrew(let name):
                HStack(spacing: 16) {
                    ConnectionChip(name: name, active: true, isDimmed: false,
                                   onTap: { showMachines = true })
                    Spacer(minLength: 12)
                    PrimaryPill(label: "Brew",
                                systemImage: "drop.fill",
                                tint: .crema, pulsing: true,
                                action: { driver.brew() })
                }
            case .brewing(let name):
                HStack(spacing: 16) {
                    ConnectionChip(name: name, active: true, isDimmed: true,
                                   onTap: nil)
                    Spacer(minLength: 12)
                    PrimaryPill(label: "Abort",
                                systemImage: "stop.fill",
                                tint: .danger, pulsing: false,
                                action: { driver.abort() })
                }
            case .done(let name):
                HStack(spacing: 12) {
                    ConnectionChip(name: name, active: true, isDimmed: false,
                                   onTap: { showMachines = true })
                    Spacer(minLength: 8)
                    SecondaryPill(label: "Save",    systemImage: "square.and.arrow.down",
                                  action: { /* TODO: save shot */ })
                    SecondaryPill(label: "Discard", systemImage: "trash",
                                  action: { driver.clearShot() })
                    PrimaryPill(label: "Brew again",
                                systemImage: "arrow.clockwise",
                                tint: .crema, pulsing: false,
                                action: { driver.clearShot(); driver.brew() })
                }
            case .failed(let reason):
                HStack(spacing: 12) {
                    StatusGlyph(systemImage: "exclamationmark.triangle.fill", tint: .danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connection failed").font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(CremaColor.cream)
                        Text(reason).font(.system(size: 11, design: .rounded))
                            .foregroundStyle(CremaColor.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    SecondaryPill(label: "Machines", systemImage: "ellipsis",
                                  action: { showMachines = true })
                    PrimaryPill(label: "Retry", systemImage: "arrow.clockwise",
                                tint: .crema, pulsing: false,
                                action: { driver.connectToPrimary() })
                }
            }
        }
        .sheet(isPresented: $showMachines) {
            MachinesView(driver: driver)
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

/// Press-down feedback — scale + slight opacity dip. Same feel on mac and iOS.
private struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
