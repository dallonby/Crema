import SwiftUI
import CremaKit

/// Sheet/modal for managing paired machines and discovering new ones.
///
/// Two sections:
/// - **Paired** — machines the user has explicitly remembered. Primary is
///   pinned to the top with a star. Tap to set as primary + connect.
///   Swipe (or X) to forget.
/// - **Discovered** — peripherals seen during a scan that aren't paired yet.
///   Tap to pair + connect.
///
/// The scan runs whenever this view is mounted; it stops when dismissed.
struct MachinesView: View {
    @Bindable var driver: LiveDriver
    @Environment(\.dismiss) private var dismiss

    @State private var scanning: Bool = false
    @State private var renamingMachine: PairedMachine?
    @State private var renameText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
                .safeAreaPadding(.top)   // iPhone Dynamic Island / notch
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    pairedSection
                    discoveredSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            footer
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480, idealHeight: 580)
        #endif
        .background(CremaColor.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { startScan() }
        .onDisappear { driver.stopScan() }
        .alert("Rename machine", isPresented: Binding(
            get: { renamingMachine != nil },
            set: { if !$0 { renamingMachine = nil } }
        ), presenting: renamingMachine) { machine in
            #if os(iOS)
            TextField("Nickname", text: $renameText)
                .textInputAutocapitalization(.words)
            #else
            TextField("Nickname", text: $renameText)
            #endif
            Button("Save") {
                driver.registry.rename(machine.id, to: renameText)
                renamingMachine = nil
            }
            Button("Reset to default", role: .destructive) {
                driver.registry.rename(machine.id, to: nil)
                renamingMachine = nil
            }
            Button("Cancel", role: .cancel) { renamingMachine = nil }
        } message: { machine in
            Text("Give “\(machine.prettyAdvertisedName)” a friendly name like “Kitchen Lita” or “Saturday Espresso”.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Machines")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(CremaColor.crema)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)         // 44pt min tap target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var pairedSection: some View {
        SectionLabel("Paired")
        if driver.registry.machines.isEmpty {
            EmptyHint(text: "No machines yet. Scan below to find your LITA.",
                      systemImage: "wave.3.right")
        } else {
            VStack(spacing: 8) {
                ForEach(driver.registry.sorted) { machine in
                    PairedRow(
                        machine: machine,
                        isPrimary: machine.id == driver.registry.primaryID,
                        isConnected: isConnected(machine),
                        onTap: { driver.connect(to: machine.id) },
                        onSetPrimary: { driver.registry.setPrimary(machine.id) },
                        onRename: {
                            renameText = machine.nickname ?? ""
                            renamingMachine = machine
                        },
                        onForget: { driver.registry.forget(machine.id) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var discoveredSection: some View {
        HStack(spacing: 8) {
            SectionLabel(scanning ? "Discovering ⋯" : "Nearby")
            Spacer()
            if scanning {
                ProgressView().controlSize(.small).tint(CremaColor.crema)
            }
        }
        let unpaired = driver.discovered.filter { d in
            !driver.registry.machines.contains(where: { $0.id == d.identifier })
        }
        if unpaired.isEmpty {
            EmptyHint(
                text: scanning ? "Looking for nearby LITAs…" : "Tap “Scan again” to look for machines.",
                systemImage: "antenna.radiowaves.left.and.right"
            )
        } else {
            VStack(spacing: 8) {
                ForEach(unpaired) { peer in
                    DiscoveredRow(peer: peer) { driver.pair(peer, setAsPrimary: driver.registry.isEmpty) }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: { scanning ? stopScan() : startScan() }) {
                HStack(spacing: 6) {
                    Image(systemName: scanning ? "stop.fill" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text(scanning ? "Stop" : "Scan again")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(CremaColor.cream)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
            Spacer()
            if let err = driver.lastError {
                Text(err)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CremaColor.danger)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(CremaColor.surface.opacity(0.7))
    }

    // MARK: - Helpers

    private func startScan() {
        scanning = true
        driver.startScan(timeout: 12)
        // Mark scanning false when state leaves .scanning. Cheap polling via Task.
        Task {
            for await s in driver.transport.stateChanges() {
                if case .scanning = s { continue }
                self.scanning = false
                return
            }
        }
    }

    private func stopScan() {
        scanning = false
        driver.stopScan()
    }

    private func isConnected(_ machine: PairedMachine) -> Bool {
        if case .connected(let name) = driver.state {
            return name == machine.advertisedName || name == machine.id
        }
        return false
    }
}

// MARK: - Rows

private struct PairedRow: View {
    let machine: PairedMachine
    let isPrimary: Bool
    let isConnected: Bool
    let onTap: () -> Void
    let onSetPrimary: () -> Void
    let onRename: () -> Void
    let onForget: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isConnected ? CremaColor.connected : CremaColor.secondary.opacity(0.4))
                        .frame(width: 9, height: 9)
                    if isConnected {
                        Circle()
                            .fill(CremaColor.connected.opacity(0.45))
                            .frame(width: 16, height: 16).blur(radius: 3)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isPrimary {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(CremaColor.crema)
                        }
                        Text(machine.displayName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(CremaColor.cream)
                    }
                    HStack(spacing: 6) {
                        Text(machine.advertisedName)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CremaColor.secondary)
                        Text("·").foregroundStyle(CremaColor.secondary)
                        Text(relativeDateText)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(CremaColor.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Rename", systemImage: "pencil", action: onRename)
                    if !isPrimary {
                        Button("Set as primary", systemImage: "star", action: onSetPrimary)
                    }
                    Divider()
                    Button("Forget machine", systemImage: "trash", role: .destructive, action: onForget)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CremaColor.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isPrimary ? CremaColor.crema.opacity(0.4) : CremaColor.hairline.opacity(0.5),
                                       lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private var relativeDateText: String {
        guard let lc = machine.lastConnected else { return "never connected" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lc, relativeTo: Date())
    }
}

private struct DiscoveredRow: View {
    let peer: DiscoveredPeripheral
    let onPair: () -> Void

    var body: some View {
        Button(action: onPair) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(CremaColor.crema)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PairedMachine.prettify(peer.name))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.cream)
                    HStack(spacing: 6) {
                        Text(peer.name)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CremaColor.secondary.opacity(0.7))
                            .lineLimit(1)
                        if let rssi = peer.rssi {
                            Text("·")
                                .foregroundStyle(CremaColor.secondary.opacity(0.5))
                            SignalBars(rssi: rssi)
                        }
                    }
                }
                Spacer()
                Text("Pair")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CremaColor.crema)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(CremaColor.crema.opacity(0.16)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small bits

/// 4-bar signal strength visualization. RSSI in dBm → bars filled.
/// Replaces raw "-54 dBm" which is too technical for non-power-users.
private struct SignalBars: View {
    let rssi: Int

    private var filledBars: Int {
        switch rssi {
        case (-50)...:   return 4  // excellent
        case (-65)...:   return 3  // good
        case (-80)...:   return 2  // fair
        default:         return 1  // weak
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4) { i in
                let height = 3 + CGFloat(i) * 2
                Capsule()
                    .fill(i < filledBars
                          ? CremaColor.cream.opacity(0.85)
                          : CremaColor.secondary.opacity(0.25))
                    .frame(width: 2.5, height: height)
            }
        }
        .frame(height: 9, alignment: .bottom)
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded).smallCaps())
            .tracking(0.6)
            .foregroundStyle(CremaColor.secondary)
    }
}

private struct EmptyHint: View {
    let text: String
    let systemImage: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(CremaColor.secondary)
            Text(text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CremaColor.hairline.opacity(0.4), lineWidth: 0.5)
        )
    }
}
