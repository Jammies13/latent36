import Foundation

enum FilmStock: String, Codable, CaseIterable, Identifiable {
    case daylight, amber, chrome, silver
    var id: String { rawValue }
    var name: String {
        switch self { case .daylight: return "DAYLIGHT 200"; case .amber: return "AMBER 400"
        case .chrome: return "CHROME 100"; case .silver: return "SILVER 400" }
    }
    var note: String {
        switch self {
        case .daylight: return "Soft contrast · warm skin · gentle grain"
        case .amber: return "Golden highlights · cool shadows · stronger grain"
        case .chrome: return "Rich color · deep blacks · crisp daylight"
        case .silver: return "Black & white · textured grain · lifted shadows"
        }
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
    var createdAt: Date
    var frames: [String] = []
    var developStartedAt: Date?
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
