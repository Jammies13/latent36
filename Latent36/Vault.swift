import Foundation
import CryptoKit

actor Vault {
    private var rolls: [Roll] = []
    private var key: SymmetricKey?
    private var loaded = false
    private let processor = FilmProcessor()
    private let root: URL
    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Latent36", isDirectory: true)
    }
    func load() throws -> [Roll] {
        if loaded { return rolls }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = root.appendingPathComponent("rolls.json")
        let keyURL = root.appendingPathComponent("vault.key")
        if FileManager.default.fileExists(atPath: manifest.path) {
            rolls = try JSONDecoder().decode([Roll].self, from: Data(contentsOf: manifest))
            // Never regenerate a missing key over existing photographs.
            let bytes = try Data(contentsOf: keyURL)
            guard bytes.count == 32 else { throw RollError.invalidData }
            key = SymmetricKey(data: bytes)
        } else {
            let newKey = SymmetricKey(size: .bits256)
            try newKey.withUnsafeBytes { try Data($0).write(to: keyURL, options: [.atomic, .completeFileProtectionUnlessOpen]) }
            key = newKey
        }
        guard rolls.allSatisfy({ $0.frames.count <= Roll.capacity && ($0.developStartedAt == nil || $0.frames.count == Roll.capacity) }),
              rolls.filter({ $0.developStartedAt == nil }).count <= 1 else { throw RollError.invalidData }
        loaded = true
        return rolls
    }
    private func persist(_ updated: [Roll]) throws {
        let data = try JSONEncoder().encode(updated)
        try data.write(to: root.appendingPathComponent("rolls.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        rolls = updated
    }
    func newRoll(stock: FilmStock) throws -> [Roll] {
        guard loaded else { throw RollError.invalidData }
        guard !rolls.contains(where: { $0.developStartedAt == nil }) else { throw RollError.busy }
        try persist(rolls + [Roll(stock: stock, createdAt: Date())])
        return rolls
    }
    func capture(_ data: Data, rollID: UUID) throws -> [Roll] {
        guard loaded, let key, let index = rolls.firstIndex(where: { $0.id == rollID }) else { throw RollError.noRoll }
        guard rolls[index].canShoot else { throw RollError.full }
        let jpeg = try autoreleasepool { try processor.render(data, stock: rolls[index].stock) }
        let sealed = try AES.GCM.seal(jpeg, using: key)
        guard let bytes = sealed.combined else { throw RollError.invalidData }
        let name = UUID().uuidString + ".frame"
        let path = root.appendingPathComponent(name)
        try bytes.write(to: path, options: [.atomic, .completeFileProtectionUnlessOpen])
        var updated = rolls
        try updated[index].addFrame(name)
        do { try persist(updated) }
        catch { try? FileManager.default.removeItem(at: path); throw error }
        return rolls
    }
    func develop(_ id: UUID) throws -> [Roll] {
        guard let index = rolls.firstIndex(where: { $0.id == id }) else { throw RollError.noRoll }
        var updated = rolls
        try updated[index].develop(at: Date())
        try persist(updated)
        return rolls
    }
    func photo(rollID: UUID, frame: String) throws -> Data {
        guard let roll = rolls.first(where: { $0.id == rollID }), roll.frames.contains(frame),
              frame == URL(fileURLWithPath: frame).lastPathComponent else { throw RollError.invalidData }
        guard roll.isReady(at: Date()) else { throw RollError.locked }
        guard let key else { throw RollError.invalidData }
        let bytes = try Data(contentsOf: root.appendingPathComponent(frame))
        return try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: key)
    }
}
