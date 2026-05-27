import SwiftUI
import CremaKit

/// Full-screen wizard for the bean auto-tune flow. Owns no state directly —
/// drives off `AutoTuneSession` which is held by the parent view so it
/// survives sheet recreation. Renders the right step view + shared chrome
/// (progress dots, navigation footer, animated transitions).
struct AutoTuneSheet: View {
    @Bindable var session: AutoTuneSession
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // Backdrop: warm gradient with the same DNA as the main app.
            CremaColor.bg.ignoresSafeArea()
            CremaGradient.appBackground.ignoresSafeArea().opacity(0.7)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    .safeAreaPadding(.top)

                AutoTuneProgressBar(currentStep: session.step)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)

                // Step content — geometry reader gives child views the room
                // they need to do hero-illustration layouts.
                GeometryReader { _ in
                    currentStepView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .leading) .combined(with: .opacity)
                        ))
                        .id(session.step)
                }
                .animation(.smooth(duration: 0.35), value: session.step)
            }
            .preferredColorScheme(.dark)

            // Confetti rains down on completion — fixed to chart layer so it
            // doesn't push surrounding content.
            if session.step == .complete {
                AutoTuneConfetti()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-tune")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                Text(stepBlurb)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
            }
            Spacer()
            Button(action: {
                session.cancel()
                onClose()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CremaColor.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(CremaColor.surface.opacity(0.6)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var stepBlurb: String {
        switch session.step {
        case .bean:     return "Tell us about the bean"
        case .recipe:   return "Set dose & target yield"
        case .prep:     return "Grind, distribute, tamp, load"
        case .brewing:  return "Brewing shot \(session.history.count + 1) of \(session.inputs.maxShots)"
        case .measure:  return "How much landed in the cup?"
        case .suggest:  return "Refinement \(session.history.count) of \(session.inputs.maxShots)"
        case .complete: return "Dialed in"
        }
    }

    // MARK: - Step routing

    @ViewBuilder
    private var currentStepView: some View {
        switch session.step {
        case .bean:     AutoTuneBeanStep(session: session)
        case .recipe:   AutoTuneRecipeStep(session: session)
        case .prep:     AutoTunePrepStep(session: session)
        case .brewing:  AutoTuneBrewingStep(session: session)
        case .measure:  AutoTuneMeasureStep(session: session)
        case .suggest:  AutoTuneSuggestStep(session: session)
        case .complete: AutoTuneCompleteStep(session: session, onClose: onClose)
        }
    }
}

// MARK: - Progress dots

/// Seven-step indicator across the top of the wizard. Filled dots = completed,
/// pulsing crema dot = current, hollow = upcoming. Lines between dots fill as
/// you progress so the bar reads as a continuous journey.
struct AutoTuneProgressBar: View {
    let currentStep: AutoTuneSession.Step

    private static let icons: [(label: String, icon: String)] = [
        ("Bean",     "leaf.fill"),
        ("Recipe",   "drop.fill"),
        ("Prep",     "hand.raised.fill"),
        ("Brew",     "cup.and.heat.waves.fill"),
        ("Measure",  "scalemass.fill"),
        ("Refine",   "sparkles"),
        ("Done",     "checkmark.seal.fill"),
    ]

    var body: some View {
        let currentIdx = currentStep.indexForProgress
        HStack(spacing: 4) {
            ForEach(Array(Self.icons.enumerated()), id: \.offset) { idx, item in
                StepDot(
                    icon: item.icon,
                    label: item.label,
                    state: dotState(for: idx, current: currentIdx)
                )
                if idx < Self.icons.count - 1 {
                    Rectangle()
                        .fill(idx < currentIdx
                              ? CremaColor.crema.opacity(0.7)
                              : CremaColor.hairline.opacity(0.5))
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        .animation(.smooth(duration: 0.4), value: currentIdx)
                }
            }
        }
    }

    private func dotState(for idx: Int, current: Int) -> StepDot.DotState {
        if idx < current  { return .complete }
        if idx == current { return .current }
        return .upcoming
    }
}

private struct StepDot: View {
    let icon: String
    let label: String
    let state: DotState
    @State private var pulse = false

    enum DotState { case upcoming, current, complete }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 28, height: 28)
                if state == .current {
                    Circle()
                        .stroke(CremaColor.crema, lineWidth: 1.5)
                        .frame(width: pulse ? 38 : 32, height: pulse ? 38 : 32)
                        .opacity(pulse ? 0 : 0.6)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
                        .onAppear { pulse = true }
                }
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(state == .upcoming ? CremaColor.secondary.opacity(0.5) : CremaColor.secondary)
        }
    }

    private var fillColor: Color {
        switch state {
        case .upcoming: return CremaColor.surface.opacity(0.4)
        case .current:  return CremaColor.crema.opacity(0.25)
        case .complete: return CremaColor.crema.opacity(0.8)
        }
    }
    private var iconColor: Color {
        switch state {
        case .upcoming: return CremaColor.secondary.opacity(0.4)
        case .current:  return CremaColor.crema
        case .complete: return CremaColor.bg
        }
    }
}

// MARK: - Shared chrome

/// Big primary CTA used as the bottom action on most step views.
struct AutoTunePrimaryButton: View {
    let title: String
    var icon: String? = nil
    var subtitle: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                VStack(spacing: 0) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(CremaColor.bg.opacity(0.7))
                    }
                }
            }
            .foregroundStyle(CremaColor.bg)
            .padding(.horizontal, 28)
            .frame(minHeight: 54)
            .background(
                Capsule().fill(LinearGradient(
                    colors: [CremaColor.cremaBright, CremaColor.crema],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            )
            .overlay(
                Capsule().strokeBorder(CremaColor.cream.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: CremaColor.crema.opacity(disabled ? 0 : 0.5), radius: 12, y: 4)
            .opacity(disabled ? 0.4 : 1)
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(.snappy(duration: 0.12), value: pressed)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onLongPressGesture(minimumDuration: 0.01, perform: {}, onPressingChanged: { pressed = $0 })
    }
}

/// Secondary text button — back / skip / cancel actions.
struct AutoTuneSecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(CremaColor.secondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Confetti

/// Cosmetic celebration when the user dials in. Coffee-bean-themed particles
/// fall + rotate; respects reduce-motion accessibility setting.
struct AutoTuneConfetti: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private let pieceCount = 36

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<pieceCount, id: \.self) { i in
                    let seed = Double(i)
                    let xStart = CGFloat.random(in: 0...geo.size.width)
                    let xDrift = CGFloat.random(in: -80...80)
                    let delay = Double(i) * 0.04
                    let duration = 1.8 + Double(i % 5) * 0.2
                    let color = [
                        CremaColor.crema,
                        CremaColor.cremaBright,
                        CremaColor.matcha,
                        CremaColor.cream,
                    ][i % 4]
                    ConfettiPiece(color: color, seed: seed)
                        .position(
                            x: animate ? xStart + xDrift : xStart,
                            y: animate ? geo.size.height + 40 : -40
                        )
                        .opacity(animate ? 0 : 1)
                        .animation(
                            reduceMotion ? .linear(duration: 0.01)
                                          : .easeIn(duration: duration).delay(delay),
                            value: animate
                        )
                }
            }
        }
        .onAppear { animate = true }
    }
}

private struct ConfettiPiece: View {
    let color: Color
    let seed: Double
    @State private var spin: Double = 0

    var body: some View {
        Image(systemName: "circle.fill")
            .resizable()
            .frame(width: 8, height: 8)
            .foregroundStyle(color)
            .rotationEffect(.degrees(spin))
            .onAppear {
                withAnimation(.linear(duration: 1.5 + seed.truncatingRemainder(dividingBy: 1))
                    .repeatForever(autoreverses: false)) {
                    spin = 360
                }
            }
    }
}
