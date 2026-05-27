import Foundation

// MARK: - Bean inputs

/// Roast level influences extraction time and starting grind size. Light roasts
/// are denser and benefit from longer extractions; dark roasts are more soluble
/// and extract faster.
public enum RoastLevel: String, Codable, CaseIterable, Sendable {
    case light, medium, dark

    public var display: String {
        switch self {
        case .light:  return "Light"
        case .medium: return "Medium"
        case .dark:   return "Dark"
        }
    }

    /// Recommended brew temperature in °C — light roasts pull better hotter.
    public var brewTempC: Double {
        switch self {
        case .light:  return 95.0
        case .medium: return 93.0
        case .dark:   return 91.0
        }
    }

    /// Target extraction time *window* (seconds, including preinfusion).
    /// Wider window = more forgiveness in early shots.
    public var targetTimeWindow: ClosedRange<Double> {
        switch self {
        case .light:  return 28...34
        case .medium: return 25...32
        case .dark:   return 22...28
        }
    }

    /// Initial grind size guess in microns.
    public var initialGrindMicrons: UInt8 {
        switch self {
        case .light:  return 72
        case .medium: return 80
        case .dark:   return 90
        }
    }
}

/// Drink type — affects target yield ratio and pressure curve.
public enum DrinkType: String, Codable, CaseIterable, Sendable {
    case espresso, milkBased

    public var display: String {
        switch self {
        case .espresso:  return "Espresso"
        case .milkBased: return "Milk drink"
        }
    }

    /// Default ratio (yield ÷ dose). Espresso = 1:2, milk drinks shorter so
    /// the espresso shines through the milk.
    public var defaultRatio: Double {
        switch self {
        case .espresso:  return 2.0
        case .milkBased: return 1.6
        }
    }

    /// Default peak pressure for the extraction stage.
    public var extractionPressureBar: Double {
        switch self {
        case .espresso:  return 9.0
        case .milkBased: return 9.5
        }
    }
}

// MARK: - Session inputs

/// Everything the user told us up-front. Drives initial recommendation.
public struct AutoTuneInputs: Sendable, Equatable {
    public var beanName: String
    public var roast: RoastLevel
    public var drink: DrinkType
    public var dose: Double          // grams in the basket
    public var targetYield: Double   // grams (≈ mL) out of the spout
    public var targetBrewTimeS: Double  // total shot time the final saved profile should hit
    public var maxShots: Int

    public init(
        beanName: String = "",
        roast: RoastLevel = .medium,
        drink: DrinkType = .espresso,
        dose: Double = 18,
        targetYield: Double = 36,
        targetBrewTimeS: Double = 30,
        maxShots: Int = 3
    ) {
        self.beanName = beanName
        self.roast = roast
        self.drink = drink
        self.dose = dose
        self.targetYield = targetYield
        self.targetBrewTimeS = targetBrewTimeS
        self.maxShots = maxShots
    }

    public var ratioString: String {
        String(format: "1 : %.1f", targetYield / max(dose, 0.1))
    }

    /// Total beans you'll burn through if we go the distance.
    public var maxBeanBudgetG: Double { dose * Double(maxShots) }
}

// MARK: - Shot result

/// Outcome of a single brew during the auto-tune session.
public struct AutoTuneShotResult: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let shotNumber: Int
    public let profile: BrewProfile
    public let grindMicrons: UInt8
    public let actualYieldG: Double
    public let actualTimeS: Double
    public let verdict: Verdict
    public let scoreOutOf100: Int

    public init(
        id: UUID = UUID(),
        shotNumber: Int,
        profile: BrewProfile,
        grindMicrons: UInt8,
        actualYieldG: Double,
        actualTimeS: Double,
        verdict: Verdict,
        scoreOutOf100: Int
    ) {
        self.id = id
        self.shotNumber = shotNumber
        self.profile = profile
        self.grindMicrons = grindMicrons
        self.actualYieldG = actualYieldG
        self.actualTimeS = actualTimeS
        self.verdict = verdict
        self.scoreOutOf100 = scoreOutOf100
    }

    public enum Verdict: String, Sendable, Equatable {
        case dialed             // within target time + yield ±15%
        case ranTooFast         // gushed; under-extracted, grind finer
        case ranTooSlow         // choked; over-extracted, grind coarser
        case yieldTooHigh       // ratio overshot (timing OK, but too much liquid)
        case yieldTooLow        // ratio undershot
    }

    /// Letter grade derived from score. Cosmetic.
    public var grade: String {
        switch scoreOutOf100 {
        case 95...:  return "A+"
        case 90...:  return "A"
        case 85...:  return "A-"
        case 80...:  return "B+"
        case 75...:  return "B"
        case 70...:  return "B-"
        case 60...:  return "C"
        case 50...:  return "D"
        default:     return "F"
        }
    }
}

// MARK: - Recommendation

/// What the auto-tuner is suggesting for the next shot.
public struct AutoTuneRecommendation: Sendable, Equatable {
    public let profile: BrewProfile
    public let grindMicrons: UInt8
    public let advice: String          // user-facing one-liner explaining the change
    public let changeSummary: String   // short delta like "Grind 5 µm finer"
    public let confidence: Confidence  // how sure we are this'll dial it in

    public enum Confidence: String, Sendable {
        case low, medium, high
    }

    public init(profile: BrewProfile, grindMicrons: UInt8,
                advice: String, changeSummary: String, confidence: Confidence) {
        self.profile = profile
        self.grindMicrons = grindMicrons
        self.advice = advice
        self.changeSummary = changeSummary
        self.confidence = confidence
    }
}
