import Foundation

enum FilmStock: String, Codable, CaseIterable, Identifiable {
    case daylight, amber, chrome, silver, meadow, coast, dusk, faded, sepia, noir
    var id: String { rawValue }
    var name: String {
        switch self { case .daylight: return "DAYLIGHT 200"; case .amber: return "AMBER 400"
        case .chrome: return "CHROME 100"; case .silver: return "SILVER 400"
        case .meadow: return "MEADOW 160"; case .coast: return "COAST 100"
        case .dusk: return "DUSK 800"; case .faded: return "FADED 100"
        case .sepia: return "SEPIA 200"; case .noir: return "NOIR 1600" }
    }
    var note: String {
        switch self {
        case .daylight: return "Soft contrast · warm skin · gentle grain"
        case .amber: return "Golden highlights · cool shadows · stronger grain"
        case .chrome: return "Rich color · deep blacks · crisp daylight"
        case .silver: return "Black & white · textured grain · lifted shadows"
        case .meadow: return "Lush greens · warm light · gentle contrast"
        case .coast: return "Cool blues · airy highlights · delicate color"
        case .dusk: return "Teal shadows · warm color · cinematic contrast"
        case .faded: return "Pastel color · matte blacks · nostalgic warmth"
        case .sepia: return "Warm monochrome · soft contrast · antique texture"
        case .noir: return "Deep black & white · hard contrast · bold grain"
        }
    }
}

enum FilmGrain: String, Codable, CaseIterable, Identifiable {
    case off, fine, classic, heavy
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var note: String {
        switch self {
        case .off: return "Clean texture, with the stock's color and glow."
        case .fine: return "Fine, restrained texture for a smoother finish."
        case .classic: return "Natural texture matched to the film stock."
        case .heavy: return "Coarser, stronger grain for a pushed-film look."
        }
    }
    var strength: CGFloat {
        switch self { case .off: return 0; case .fine: return 0.55; case .classic: return 1; case .heavy: return 1.8 }
    }
    var size: CGFloat {
        switch self { case .off: return 1; case .fine: return 0.75; case .classic: return 1.25; case .heavy: return 2 }
    }
}

enum RollError: LocalizedError {
    case full, incomplete, developing, locked, noRoll, busy, invalidData
    var errorDescription: String? {
        switch self {
        case .full: return "This roll has all 36 exposures. It's ready to develop."
        case .incomplete: return "Shoot all 36 exposures before developing this roll."
        case .developing: return "This roll is already developing."
        case .locked: return "These photographs are still developing. Come back when the timer ends."
        case .noRoll: return "Load a film roll first."
        case .busy: return "Wait for the current exposure to finish."
        case .invalidData: return "The photograph could not be processed. No exposure was used."
        }
    }
}

struct Roll: Identifiable, Codable, Equatable {
    static let capacity = 36
    static let developmentTime: TimeInterval = 24 * 60 * 60
    var id = UUID()
    var stock: FilmStock
    var grain: FilmGrain = .classic
    var createdAt: Date
    var frames: [String] = []
    var developStartedAt: Date?
    init(stock: FilmStock, createdAt: Date, grain: FilmGrain = .classic) {
        self.stock = stock
        self.createdAt = createdAt
        self.grain = grain
    }
    private enum CodingKeys: String, CodingKey { case id, stock, grain, createdAt, frames, developStartedAt }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        stock = try values.decode(FilmStock.self, forKey: .stock)
        grain = try values.decodeIfPresent(FilmGrain.self, forKey: .grain) ?? .classic
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        frames = try values.decode([String].self, forKey: .frames)
        developStartedAt = try values.decodeIfPresent(Date.self, forKey: .developStartedAt)
    }
    var readyAt: Date? { developStartedAt?.addingTimeInterval(Self.developmentTime) }
    var canShoot: Bool { developStartedAt == nil && frames.count < Self.capacity }
    var canDevelop: Bool { developStartedAt == nil && frames.count == Self.capacity }
    func isReady(at date: Date) -> Bool { readyAt.map { date >= $0 } ?? false }
    mutating func addFrame(_ filename: String) throws {
        guard developStartedAt == nil else { throw RollError.developing }
        guard frames.count < Self.capacity else { throw RollError.full }
        frames.append(filename)
    }
    mutating func develop(at date: Date) throws {
        guard developStartedAt == nil else { throw RollError.developing }
        guard frames.count == Self.capacity else { throw RollError.incomplete }
        developStartedAt = date
    }
}
