import SwiftUI
import CremaKit

// MARK: - 1. Bean step

/// Bean name + roast picker + drink type picker. Two grid pickers because the
/// user is making categorical choices — cards beat dropdowns for tappability.
struct AutoTuneBeanStep: View {
    @Bindable var session: AutoTuneSession

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("BEAN") {
                        TextField("Name this bean (e.g. Cartwheel Decaf)",
                                  text: $session.inputs.beanName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(CremaColor.cream)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(CremaColor.surface.opacity(0.6))
                            )
                    }

                    section("ROAST LEVEL") {
                        HStack(spacing: 10) {
                            ForEach(RoastLevel.allCases, id: \.self) { level in
                                RoastCard(
                                    level: level,
                                    selected: session.inputs.roast == level,
                                    onTap: {
                                        withAnimation(.snappy(duration: 0.18)) {
                                            session.inputs.roast = level
                                        }
                                    }
                                )
                            }
                        }
                    }

                    section("DRINK TYPE") {
                        HStack(spacing: 10) {
                            ForEach(DrinkType.allCases, id: \.self) { drink in
                                DrinkCard(
                                    drink: drink,
                                    selected: session.inputs.drink == drink,
                                    onTap: {
                                        withAnimation(.snappy(duration: 0.18)) {
                                            session.inputs.drink = drink
                                        }
                                    }
                                )
                            }
                        }
                    }

                    factCard
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
            }

            footer
        }
    }

    @ViewBuilder
    private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.7)
                .foregroundStyle(CremaColor.secondary)
            content()
        }
    }

    /// Rotating coffee facts — gives the user something delightful to read.
    private var factCard: some View {
        let fact = CoffeeFacts.fact(for: session.inputs.roast)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11))
                .foregroundStyle(CremaColor.crema)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Did you know?")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(CremaColor.secondary)
                Text(fact)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(CremaColor.cream.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CremaColor.hairline.opacity(0.4), lineWidth: 0.5))
        )
        .id(session.inputs.roast)
        .transition(.opacity)
        .animation(.smooth(duration: 0.25), value: session.inputs.roast)
    }

    private var footer: some View {
        HStack {
            Spacer()
            AutoTunePrimaryButton(title: "Next", icon: "arrow.right") {
                session.goNext()
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }
}

private struct RoastCard: View {
    let level: RoastLevel
    let selected: Bool
    let onTap: () -> Void

    private var beanColor: Color {
        switch level {
        case .light:  return Color(red: 0.78, green: 0.58, blue: 0.32)
        case .medium: return Color(red: 0.55, green: 0.35, blue: 0.18)
        case .dark:   return Color(red: 0.28, green: 0.18, blue: 0.10)
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Three beans, color matches roast — visual cue for the level.
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(beanColor)
                            .frame(width: 9, height: 14)
                            .rotationEffect(.degrees(-15))
                    }
                }
                Text(level.display)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                Text("\(Int(level.brewTempC))°C · \(Int(level.targetTimeWindow.lowerBound))-\(Int(level.targetTimeWindow.upperBound))s")
                    .font(.system(size: 9, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? CremaColor.crema.opacity(0.20) : CremaColor.surface.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? CremaColor.crema : CremaColor.hairline.opacity(0.5),
                                          lineWidth: selected ? 1.5 : 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DrinkCard: View {
    let drink: DrinkType
    let selected: Bool
    let onTap: () -> Void

    private var icon: String {
        drink == .espresso ? "cup.and.saucer.fill" : "mug.fill"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(selected ? CremaColor.crema : CremaColor.secondary)
                Text(drink.display)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                Text(drink.defaultRatio == 2.0 ? "1 : 2 ratio" : "1 : 1.6 ratio")
                    .font(.system(size: 9, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? CremaColor.crema.opacity(0.20) : CremaColor.surface.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? CremaColor.crema : CremaColor.hairline.opacity(0.5),
                                          lineWidth: selected ? 1.5 : 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 2. Recipe step

/// Dose + target yield. Live ratio readout updates with every slider tick.
struct AutoTuneRecipeStep: View {
    @Bindable var session: AutoTuneSession

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ratioHero
                    sliderRow(label: "Dose", value: $session.inputs.dose,
                              range: 12...22, step: 0.5,
                              format: { String(format: "%.1f g", $0) },
                              accent: CremaColor.crema)
                    sliderRow(label: "Target yield in cup", value: $session.inputs.targetYield,
                              range: session.inputs.dose ... session.inputs.dose * 5,
                              step: 1,
                              format: { String(format: "%.0f g", $0) },
                              accent: CremaColor.matcha)
                    sliderRow(label: "Target brew time", value: $session.inputs.targetBrewTimeS,
                              range: 15 ... 60, step: 1,
                              format: { String(format: "%.0f s", $0) },
                              accent: CremaColor.cream)
                    Text("The saved profile's extract stage will be trimmed to hit this total time. During tuning the extract runs open-ended so you can stop based on cup weight.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(CremaColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    beanBudgetCard
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
            }

            HStack {
                AutoTuneSecondaryButton(title: "Back", icon: "arrow.left") { session.goBack() }
                Spacer()
                AutoTunePrimaryButton(title: "Next", icon: "arrow.right") { session.goNext() }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }

    private var ratioHero: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(String(format: "%.1f", session.inputs.dose))
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.crema)
                Text("dose g")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(CremaColor.secondary)
            }
            Text("→")
                .font(.system(size: 28, weight: .thin, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
            VStack(spacing: 0) {
                Text(String(format: "%.0f", session.inputs.targetYield))
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.matcha)
                Text("yield g")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(CremaColor.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(session.inputs.ratioString)
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.cream)
                Text("ratio")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(CremaColor.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
        )
    }

    private func sliderRow(label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double,
                           format: @escaping (Double) -> String,
                           accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.system(size: 13, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
            }
            Slider(value: value, in: range, step: step).tint(accent)
        }
    }

    private var beanBudgetCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "scalemass.fill")
                .font(.system(size: 13))
                .foregroundStyle(CremaColor.crema)
            Text("Up to **\(Int(session.inputs.maxBeanBudgetG))g** of beans needed for \(session.inputs.maxShots) shots")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(CremaColor.cream.opacity(0.9))
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CremaColor.hairline.opacity(0.4), lineWidth: 0.5))
        )
    }
}

// MARK: - 3. Prep step

/// "Grind X g, distribute, tamp, load." Hero illustration of a portafilter.
struct AutoTunePrepStep: View {
    @Bindable var session: AutoTuneSession
    @State private var animate = false
    @State private var grinderSent = false
    @State private var grinderSending = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    portafilterIllustration
                        .padding(.top, 8)

                    if let rec = session.currentRecommendation {
                        recommendedCard(rec: rec)
                    }

                    checklist
                    scaleHint

                    if session.history.isEmpty {
                        Text("Your machine and grinder are pre-armed with these settings — just grind into the basket and load the portafilter.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(CremaColor.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
            }

            HStack(spacing: 10) {
                AutoTuneSecondaryButton(title: "Back", icon: "arrow.left") { session.goBack() }
                Spacer()
                if session.recommendationHasGrinder {
                    setGrinderButton
                }
                AutoTunePrimaryButton(
                    title: session.history.isEmpty ? "Brew first shot" : "Brew shot \(session.history.count + 1)",
                    icon: "play.fill",
                    subtitle: session.canBrew ? nil : "Machine not ready",
                    disabled: !session.canBrew
                ) { session.goNext() }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        // Reset the "sent" badge each time the prep step appears — e.g. after
        // returning from a brew with a new (different) grinder size.
        .onAppear {
            grinderSent = false
        }
    }

    /// Secondary CTA next to "Brew first shot" — pushes the recommended grind
    /// size + RPM to the grinder via the machine's FF55 channel. Only rendered
    /// when the recommendation actually has grinder settings (it always does
    /// for auto-tune, but the check is honest in case that ever changes).
    /// After a successful send, swaps to a green "Sent" pill for ~2 s.
    private var setGrinderButton: some View {
        Button(action: {
            guard !grinderSending else { return }
            grinderSending = true
            Task { @MainActor in
                _ = await session.sendGrinderForCurrentRecommendation()
                grinderSending = false
                grinderSent = true
                // Light haptic — successful "thing happened" feedback.
                #if os(iOS)
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
                #endif
            }
        }) {
            HStack(spacing: 6) {
                if grinderSending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(CremaColor.matchaBright)
                } else if grinderSent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Image(systemName: "dial.high.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(grinderSending ? "Sending…"
                     : (grinderSent ? "Grinder set" : "Set grinder"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(grinderSent ? CremaColor.matchaBright : CremaColor.matcha)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill((grinderSent ? CremaColor.matcha : CremaColor.matcha).opacity(0.18))
                    .overlay(Capsule().strokeBorder(
                        (grinderSent ? CremaColor.matchaBright : CremaColor.matcha).opacity(0.45),
                        lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .disabled(grinderSending)
        .animation(.smooth(duration: 0.2), value: grinderSent)
        .animation(.smooth(duration: 0.2), value: grinderSending)
    }

    private var portafilterIllustration: some View {
        // Stylized portafilter: handle on the left, basket on the right,
        // beans falling in. Pure SF Symbols + shapes, animates on entry.
        ZStack {
            // Handle
            Capsule()
                .fill(LinearGradient(colors: [
                    CremaColor.cream.opacity(0.6),
                    CremaColor.cream.opacity(0.3),
                ], startPoint: .leading, endPoint: .trailing))
                .frame(width: 100, height: 16)
                .offset(x: -60)
            // Basket
            Circle()
                .fill(CremaColor.surface.opacity(0.8))
                .overlay(Circle().strokeBorder(CremaColor.cream.opacity(0.5), lineWidth: 1.5))
                .frame(width: 110, height: 110)
                .offset(x: 30)
            // Coffee grounds
            Circle()
                .fill(LinearGradient(colors: [
                    Color(red: 0.45, green: 0.28, blue: 0.15),
                    Color(red: 0.30, green: 0.18, blue: 0.08),
                ], startPoint: .top, endPoint: .bottom))
                .frame(width: 90, height: 90)
                .offset(x: 30)
                .scaleEffect(animate ? 1 : 0.4)
                .opacity(animate ? 1 : 0)
                .animation(.smooth(duration: 0.45).delay(0.15), value: animate)
            // Falling beans
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Color(red: 0.55, green: 0.35, blue: 0.18))
                    .frame(width: 9, height: 14)
                    .rotationEffect(.degrees(-15))
                    .offset(x: 30 + CGFloat(i - 1) * 14,
                            y: animate ? -10 : -130)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeIn(duration: 0.7).delay(Double(i) * 0.12), value: animate)
            }
        }
        .frame(height: 150)
        .onAppear { animate = true }
    }

    private func recommendedCard(rec: AutoTuneRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12))
                    .foregroundStyle(CremaColor.crema)
                Text("RECOMMENDED FOR THIS SHOT")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.7)
                    .foregroundStyle(CremaColor.secondary)
            }
            HStack(spacing: 20) {
                statTile(value: "\(rec.grindMicrons)", unit: "µm", label: "Grind")
                statTile(value: String(format: "%.1f", session.inputs.dose), unit: "g", label: "Dose")
                statTile(value: String(format: "%.1f", rec.profile.stages.first(where: { $0.label == "Extract" })?.pressureBar ?? 9.0), unit: "bar", label: "Peak P")
                statTile(value: "\(Int(rec.profile.totalDuration))", unit: "s", label: "Time")
            }
            Text(rec.advice)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(CremaColor.cream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CremaColor.crema.opacity(0.3), lineWidth: 0.5))
        )
    }

    private func statTile(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.cream)
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.6)
                .foregroundStyle(CremaColor.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            checklistRow(icon: "1.circle.fill",
                         text: "Grind **\(String(format: "%.1f g", session.inputs.dose))** of beans into your basket")
            checklistRow(icon: "2.circle.fill",
                         text: "Distribute evenly · tamp level · firm pressure")
            checklistRow(icon: "3.circle.fill",
                         text: "Lock the portafilter into the group head")
            checklistRow(icon: "4.circle.fill",
                         text: "Place your cup on the scale (or under the spout)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CremaColor.surface.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CremaColor.hairline.opacity(0.4), lineWidth: 0.5))
        )
    }

    private func checklistRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(CremaColor.crema)
            Text(text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(CremaColor.cream.opacity(0.9))
            Spacer()
        }
    }

    @ViewBuilder
    private var scaleHint: some View {
        if let name = session.scaleName {
            HStack(spacing: 8) {
                Image(systemName: "scalemass")
                    .font(.system(size: 11))
                    .foregroundStyle(CremaColor.matchaBright)
                Text("Reading from **\(name)**")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                Spacer()
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold, design: .rounded).smallCaps())
                    .tracking(0.7)
                    .foregroundStyle(CremaColor.matchaBright)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CremaColor.matcha.opacity(0.25)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CremaColor.matcha.opacity(0.10))
            )
        } else {
            HStack(spacing: 8) {
                Image(systemName: "hand.point.right.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(CremaColor.secondary)
                Text("No scale paired — we'll ask for the final weight after the shot")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - 4. Brewing step

/// Live shot in progress. Mini chart + live yield readout + circular timer.
/// Tap "abort" to bail; otherwise it auto-advances when brew completes.
struct AutoTuneBrewingStep: View {
    @Bindable var session: AutoTuneSession
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    elapsedDial
                    liveMetricRow
                    miniChart
                    targetReminder
                    pumpVolumeNote
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
            }
            stopButton
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
        // Auto-stop the moment a connected scale reads the target weight.
        .onChange(of: session.liveWeightG ?? 0) { _, newWeight in
            if newWeight >= session.inputs.targetYield,
               session.liveDriver.brewState == .brewing {
                session.liveDriver.abort()
            }
        }
    }

    /// Primary action when brewing: stop when the cup hits target. Far more
    /// prominent than the old "abort" link — for non-scale users this IS the
    /// expected action mid-shot (machine's pump-volume metering won't stop
    /// the shot at the right point on its own).
    private var stopButton: some View {
        let weight = session.liveWeightG
        let target = session.inputs.targetYield
        let progress = weight.map { min(1, max(0, $0 / target)) } ?? 0
        let scaleConnected = session.scaleName != nil
        return Button(action: {
            if session.liveDriver.brewState == .brewing {
                session.liveDriver.abort()
            }
        }) {
            ZStack {
                Capsule()
                    .fill(LinearGradient(
                        colors: [CremaColor.cremaBright, CremaColor.crema],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                if scaleConnected, progress < 1 {
                    // Subtle fill that tracks weight — only meaningful with a scale.
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: geo.size.width * CGFloat(progress))
                    }
                    .clipShape(Capsule())
                }
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .semibold))
                    if scaleConnected {
                        Text(progress >= 1 ? "Auto-stopping…" :
                            String(format: "Stop  ·  %.1f / %.0f g", weight ?? 0, target))
                    } else {
                        Text("Stop — when cup hits \(Int(target)) g")
                    }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(CremaColor.bg)
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .overlay(Capsule().strokeBorder(CremaColor.cream.opacity(0.2), lineWidth: 0.5))
            .shadow(color: CremaColor.crema.opacity(0.5), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var targetReminder: some View {
        HStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 12))
                .foregroundStyle(CremaColor.crema)
            Text("Target: **\(Int(session.inputs.targetYield)) g** in your cup")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CremaColor.surface.opacity(0.4))
        )
    }

    /// Explain to the user WHY they have to watch the cup, not the machine.
    /// First-time auto-tuners will absolutely otherwise wonder why the chart
    /// shows 36 mL pumped while their cup has 5 g in it.
    private var pumpVolumeNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(CremaColor.secondary)
                .padding(.top, 1)
            Text("The machine's mL reading is pump throughput, *before* the puck. A lot of water soaks into the grounds — what lands in the cup is much less. Watch your cup, not the chart.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CremaColor.surface.opacity(0.25))
        )
    }

    private var elapsedDial: some View {
        let elapsed = session.liveDriver.playback.t
        let target = session.currentRecommendation.map { $0.profile.totalDuration } ?? 28
        let frac = min(1, elapsed / max(target, 1))
        return ZStack {
            Circle()
                .stroke(CremaColor.hairline.opacity(0.4), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(frac))
                .stroke(LinearGradient(
                    colors: [CremaColor.crema, CremaColor.cremaBright],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: frac)
            VStack(spacing: 0) {
                Text(String(format: "%05.1f", elapsed))
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.cream)
                Text("seconds")
                    .font(.system(size: 9, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(CremaColor.secondary)
            }
        }
        .frame(width: 130, height: 130)
    }

    private var liveMetricRow: some View {
        let p = session.liveDriver.playback.currentSample?.pressureBar ?? 0
        let f = session.liveDriver.playback.currentSample?.flowMlPerSec ?? 0
        let weight = session.liveWeightG
        return HStack(spacing: 10) {
            metricTile(title: "Pressure", value: String(format: "%.1f", p), unit: "bar",
                       color: CremaColor.crema)
            metricTile(title: "Flow", value: String(format: "%.1f", f), unit: "mL/s",
                       color: CremaColor.matcha)
            if let w = weight {
                metricTile(title: "Live weight", value: String(format: "%.1f", w), unit: "g",
                           color: CremaColor.cream)
            } else {
                let mlReported = Double(session.liveDriver.playback.currentSample?.volumeMl ?? 0)
                metricTile(title: "Machine mL", value: String(format: "%.0f", mlReported), unit: "mL",
                           color: CremaColor.cream.opacity(0.7))
            }
        }
    }

    private func metricTile(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
            }
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.6)
                .foregroundStyle(CremaColor.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var miniChart: some View {
        Group {
            if let rec = session.currentRecommendation {
                ShotChart(
                    samples: session.liveDriver.playback.emitted,
                    profile: rec.profile,
                    playhead: session.liveDriver.playback.t,
                    totalDuration: max(rec.profile.totalDuration,
                                       session.liveDriver.playback.t + 1)
                )
                .frame(height: 180)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CremaColor.bg.opacity(0.6))
                )
            }
        }
    }
}

// MARK: - 5. Measure step

/// Brew ended; enter yield (auto-filled from scale or estimated from machine
/// mL). Big input + verdict preview.
struct AutoTuneMeasureStep: View {
    @Bindable var session: AutoTuneSession

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    summaryRow

                    measurementInput

                    verdictPreview
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
            }

            HStack(spacing: 10) {
                AutoTuneSecondaryButton(title: "Discard shot", icon: "trash") {
                    session.discardCurrentShot()
                }
                Spacer()
                AutoTunePrimaryButton(title: "Confirm yield", icon: "checkmark") {
                    session.goNext()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(String(format: "%.1f", session.lastShotElapsedS))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.cream)
                Text("seconds at stop")
                    .font(.system(size: 9, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(CremaColor.secondary)
            }
            Spacer()
            // Pump volume is shown for context only — small, dim, labelled as
            // pump-not-yield so the user doesn't confuse it with cup weight.
            VStack(spacing: 2) {
                Text("\(Int(session.lastShotMlReportedByMachine))")
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.secondary)
                Text("pumped mL (pre-puck)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(CremaColor.secondary.opacity(0.7))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var measurementInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.scaleName != nil ? "FROM \(session.scaleName!.uppercased())" : "WEIGH YOUR CUP")
                .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.7)
                .foregroundStyle(CremaColor.secondary)
            HStack(spacing: 0) {
                TextField("0",
                          value: $session.manualYieldEntryG,
                          format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.cream)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                Text("g")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(CremaColor.crema.opacity(0.4), lineWidth: 1))
            )
            // Quick-add chips for common cup tares
            HStack(spacing: 6) {
                ForEach([2.0, 5.0, 10.0, 20.0], id: \.self) { add in
                    Button(action: { session.manualYieldEntryG += add }) {
                        Text("+\(Int(add))g")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(CremaColor.cream)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(CremaColor.surface.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: { session.manualYieldEntryG = 0 }) {
                    Text("Reset")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Live verdict preview — updates as the user adjusts the yield input so
    /// they can see whether they're in the dialed zone before confirming.
    private var verdictPreview: some View {
        let verdict = AutoTuneRecommender.verdict(
            actualTimeS: session.lastShotElapsedS,
            actualYieldG: session.manualYieldEntryG,
            inputs: session.inputs
        )
        let blurb: String = switch verdict {
        case .dialed:       "Looking dialed in — confirm to lock it in."
        case .ranTooFast:   "Shot ran faster than the target window — we'll suggest a finer grind."
        case .ranTooSlow:   "Shot ran slower than the target window — we'll suggest a coarser grind."
        case .yieldTooHigh: "Ratio overshot — we'll tighten the extraction."
        case .yieldTooLow:  "Ratio undershot — we'll lengthen the extraction."
        }
        let color: Color = verdict == .dialed ? CremaColor.matchaBright : CremaColor.crema
        return HStack(spacing: 10) {
            Image(systemName: verdict == .dialed ? "checkmark.seal.fill" : "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(blurb)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 0.5))
        )
    }
}

// MARK: - 6. Suggest step

/// Verdict card + change summary + "brew again" CTA. Or, if dialed in:
/// "Looks like we got it!" with a "Save & finish" CTA.
struct AutoTuneSuggestStep: View {
    @Bindable var session: AutoTuneSession
    @State private var flip = false
    @State private var grinderSent = false
    @State private var grinderSending = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    verdictCard
                        .rotation3DEffect(.degrees(flip ? 0 : 90),
                                          axis: (x: 1, y: 0, z: 0),
                                          perspective: 0.4)
                        .opacity(flip ? 1 : 0)
                        .onAppear {
                            withAnimation(.smooth(duration: 0.5).delay(0.05)) { flip = true }
                        }
                    if let rec = session.currentRecommendation {
                        recommendationCard(rec: rec)
                    } else {
                        dialedInCard
                    }
                    if session.history.count >= 2 { shotTimeline }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
            }

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
    }

    private var verdictCard: some View {
        let shot = session.history.last!
        return VStack(spacing: 12) {
            Text("SHOT \(shot.shotNumber) GRADE")
                .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.7)
                .foregroundStyle(CremaColor.secondary)
            Text(shot.grade)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(
                    colors: shot.scoreOutOf100 >= 80
                        ? [CremaColor.matchaBright, CremaColor.matcha]
                        : [CremaColor.cremaBright, CremaColor.crema],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Text("\(shot.scoreOutOf100) / 100")
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(CremaColor.cream)
            HStack(spacing: 22) {
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", shot.actualTimeS))
                        .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(CremaColor.cream)
                    Text("seconds").font(.system(size: 9, design: .rounded)).foregroundStyle(CremaColor.secondary)
                }
                VStack(spacing: 0) {
                    Text(String(format: "%.1f g", shot.actualYieldG))
                        .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(CremaColor.cream)
                    Text("yield").font(.system(size: 9, design: .rounded)).foregroundStyle(CremaColor.secondary)
                }
                VStack(spacing: 0) {
                    Text(String(format: "1:%.1f", shot.actualYieldG / max(session.inputs.dose, 0.1)))
                        .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(CremaColor.cream)
                    Text("ratio").font(.system(size: 9, design: .rounded)).foregroundStyle(CremaColor.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
        )
    }

    private func recommendationCard(rec: AutoTuneRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(CremaColor.crema)
                Text("FOR NEXT SHOT")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.7)
                    .foregroundStyle(CremaColor.secondary)
            }
            Text(rec.changeSummary)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Text(rec.advice)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(CremaColor.cream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            // Apply the new grinder setting immediately so the user can grind
            // their next dose before navigating to the prep step.
            if rec.profile.grinder != nil {
                inlineSetGrinderButton
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CremaColor.crema.opacity(0.3), lineWidth: 0.5))
        )
    }

    /// Compact inline Set Grinder pill — same write path as the prep step's
    /// button, surfaced here so the user can act on the suggestion the moment
    /// they read it ("grind 18 µm finer" without a way to apply that is poor
    /// UX). Visual state mirrors the prep step's button.
    private var inlineSetGrinderButton: some View {
        Button(action: {
            guard !grinderSending else { return }
            grinderSending = true
            Task { @MainActor in
                _ = await session.sendGrinderForCurrentRecommendation()
                grinderSending = false
                grinderSent = true
                #if os(iOS)
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
                #endif
            }
        }) {
            HStack(spacing: 5) {
                if grinderSending {
                    ProgressView().controlSize(.small).tint(CremaColor.matchaBright)
                } else if grinderSent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Image(systemName: "dial.high.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(grinderSending ? "Sending…"
                     : (grinderSent ? "Grinder set" : "Set grinder now"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(grinderSent ? CremaColor.matchaBright : CremaColor.matcha)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(CremaColor.matcha.opacity(0.18))
                    .overlay(Capsule().strokeBorder(
                        (grinderSent ? CremaColor.matchaBright : CremaColor.matcha).opacity(0.45),
                        lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .disabled(grinderSending)
        .animation(.smooth(duration: 0.2), value: grinderSent)
        .animation(.smooth(duration: 0.2), value: grinderSending)
    }

    private var dialedInCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundStyle(CremaColor.matchaBright)
            Text("That's a dialed shot.")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Text("This recipe is ready to save and brew. Tap Finish to lock it into your library.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(CremaColor.cream.opacity(0.85))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CremaColor.matcha.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CremaColor.matcha.opacity(0.5), lineWidth: 0.5))
        )
    }

    private var shotTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR JOURNEY")
                .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.7)
                .foregroundStyle(CremaColor.secondary)
            HStack(spacing: 8) {
                ForEach(session.history) { shot in
                    VStack(spacing: 4) {
                        Text(shot.grade)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(CremaColor.cream)
                        Text("#\(shot.shotNumber)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(CremaColor.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CremaColor.surface.opacity(0.5))
                    )
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                if session.currentRecommendation != nil
                    && session.history.count < session.inputs.maxShots {
                    AutoTuneSecondaryButton(title: "I'm happy — finish", icon: "checkmark") {
                        // Force-complete even though recommender wants more.
                        session.currentRecommendation = nil
                        session.goNext()
                    }
                }
                Spacer()
                if session.currentRecommendation == nil
                    || session.history.count >= session.inputs.maxShots {
                    AutoTunePrimaryButton(title: "Finish", icon: "checkmark.seal.fill") {
                        session.goNext()
                    }
                } else {
                    AutoTunePrimaryButton(
                        title: "Brew shot \(session.history.count + 1)",
                        icon: "play.fill"
                    ) { session.goNext() }
                }
            }
            // Quiet "discard this shot" link — for when the user realises the
            // shot they just confirmed was botched (basket fell off, knocked
            // the cup, hit Brew without setting up). Pops the last history
            // entry, restores the prior recommendation, returns to prep.
            HStack {
                Spacer()
                Button(action: { session.discardLastRecordedShot() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                        Text("Discard this shot — re-brew shot \(session.history.count)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(CremaColor.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }
}

// MARK: - 7. Complete step

/// Celebration. Best-shot grade, recipe summary, save-as-profile rename, done.
struct AutoTuneCompleteStep: View {
    @Bindable var session: AutoTuneSession
    let onClose: () -> Void
    @State private var profileName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    headline
                    bestShotCard
                    nameField
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
            }

            HStack {
                AutoTuneSecondaryButton(title: "Don't save") {
                    onClose()
                }
                Spacer()
                AutoTunePrimaryButton(title: "Save & use", icon: "tray.and.arrow.down.fill") {
                    session.saveTunedProfile(named: profileName)
                    onClose()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .onAppear {
            profileName = session.inputs.beanName.isEmpty
                ? "Auto · \(session.inputs.roast.display)"
                : session.inputs.beanName
        }
    }

    private var headline: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(CremaColor.matcha.opacity(0.20))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(CremaColor.matchaBright)
            }
            Text("Dialed in!")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Text(session.inputs.beanName.isEmpty
                 ? "We've tuned a recipe for your bean."
                 : "We've tuned a recipe for \(session.inputs.beanName).")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var bestShotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(CremaColor.crema)
                Text("BEST SHOT")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.7)
                    .foregroundStyle(CremaColor.secondary)
            }
            if let best = session.bestShot {
                HStack(alignment: .firstTextBaseline) {
                    Text(best.grade)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(CremaColor.matchaBright)
                    Spacer()
                    Text("Shot #\(best.shotNumber) of \(session.history.count)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(CremaColor.secondary)
                }
                Divider().overlay(CremaColor.hairline.opacity(0.4))
                statRow("Time",  String(format: "%.1f s", best.actualTimeS))
                statRow("Yield", String(format: "%.1f g", best.actualYieldG))
                statRow("Ratio", String(format: "1 : %.1f",
                                         best.actualYieldG / max(session.inputs.dose, 0.1)))
                statRow("Grind", "\(best.grindMicrons) µm")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CremaColor.matcha.opacity(0.3), lineWidth: 0.5))
        )
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(CremaColor.cream)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SAVE AS")
                .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.7)
                .foregroundStyle(CremaColor.secondary)
            TextField("Profile name", text: $profileName)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(CremaColor.cream)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CremaColor.surface.opacity(0.6))
                )
        }
    }
}

// MARK: - Coffee facts

private enum CoffeeFacts {
    static func fact(for roast: RoastLevel) -> String {
        let lightFacts = [
            "Light roasts retain more chlorogenic acid — that's where the bright, citrus-like flavours come from.",
            "Lighter roasts are actually denser and tend to need a finer grind than darker beans.",
            "Origin character dominates light roasts — Ethiopian florals, Kenyan blackcurrant, Colombian caramel.",
        ]
        let mediumFacts = [
            "Medium roasts hit the sweet spot between origin clarity and developed body.",
            "First crack happens around 196 °C — medium roasts are pulled shortly after.",
            "Most café espresso blends sit in this range — forgiving and flexible.",
        ]
        let darkFacts = [
            "Dark roasts develop after second crack at ~225 °C — oils begin to migrate to the bean surface.",
            "More soluble = faster extraction. Dark roasts often want lower pressure and shorter times.",
            "The bitterness of darker roasts is largely from quinic acid formed during prolonged roasting.",
        ]
        let pool = switch roast {
            case .light:  lightFacts
            case .medium: mediumFacts
            case .dark:   darkFacts
        }
        return pool.randomElement() ?? pool[0]
    }
}
