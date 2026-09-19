import Foundation
import CryptoKit

enum VaultError: LocalizedError {
    case missingIndex, invalidIndex, invalidKey, notLoaded
    var errorDescription: String? {
        switch self {
        case .missingIndex: return "The film index is missing, but stored photographs remain. Keep this installation and its data so the library can be recovered."
        case .invalidIndex: return "The film index is damaged. Your stored photographs have not been changed."
        case .invalidKey: return "The film encryption key is missing or damaged. Your stored photographs have not been changed."
        case .notLoaded: return "Open the film library successfully before making changes."
        }
    }
}

actor Vault {
    private var rolls: [Roll] = []
    private var key: SymmetricKey?
    private var loaded = false
    private let processor = FilmProcessor()
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Latent36", isDirectory: true)
    }
    func load() throws -> [Roll] {
        if loaded { return rolls }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = root.appendingPathComponent("rolls.json")
        let keyURL = root.appendingPathComponent("vault.key")
        let restored: [Roll]
        let restoredKey: SymmetricKey
        if FileManager.default.fileExists(atPath: manifest.path) {
            let data = try Data(contentsOf: manifest)
            do { restored = try JSONDecoder().decode([Roll].self, from: data) }
            catch { throw VaultError.invalidIndex }
            try validate(restored)
            // Never regenerate a missing key over existing photographs.
            guard FileManager.default.fileExists(atPath: keyURL.path) else { throw VaultError.invalidKey }
            let bytes = try Data(contentsOf: keyURL)
            guard bytes.count == 32 else { throw VaultError.invalidKey }
            restoredKey = SymmetricKey(data: bytes)
        } else {
            // A missing index must never turn an existing library into a new one.
            let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            guard !files.contains(where: { $0.pathExtension.lowercased() == "frame" }) else {
                throw VaultError.missingIndex
            }
            restored = []
            if FileManager.default.fileExists(atPath: keyURL.path) {
                // Reuse the key if first-launch initialization was interrupted.
                let bytes = try Data(contentsOf: keyURL)
                guard bytes.count == 32 else { throw VaultError.invalidKey }
                restoredKey = SymmetricKey(data: bytes)
            } else {
                restoredKey = SymmetricKey(size: .bits256)
                try restoredKey.withUnsafeBytes {
                    try Data($0).write(to: keyURL, options: [.atomic, .completeFileProtectionUnlessOpen])
                }
            }
            try JSONEncoder().encode(restored).write(to: manifest, options: [.atomic, .completeFileProtectionUnlessOpen])
        }
        // Publish state only after every read, validation and initialization write succeeds.
        rolls = restored
        key = restoredKey
        loaded = true
        return rolls
    }
    private func validate(_ restored: [Roll]) throws {
        var ids = Set<UUID>()
        var frames = Set<String>()
        guard restored.filter({ $0.developStartedAt == nil }).count <= 1 else { throw VaultError.invalidIndex }
        for roll in restored {
            guard ids.insert(roll.id).inserted, roll.frames.count <= Roll.capacity,
                  roll.developStartedAt == nil || roll.frames.count == Roll.capacity else {
                throw VaultError.invalidIndex
            }
            for frame in roll.frames {
                guard !frame.isEmpty, !frame.contains("/"), !frame.contains("\\"),
                      !frame.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                      frame.hasSuffix(".frame"), frames.insert(frame.lowercased()).inserted else {
                    throw VaultError.invalidIndex
                }
            }
        }
    }
    private func persist(_ updated: [Roll]) throws {
        let data = try JSONEncoder().encode(updated)
        try data.write(to: root.appendingPathComponent("rolls.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        rolls = updated
    }
    func newRoll(stock: FilmStock) throws -> [Roll] {
        guard loaded else { throw VaultError.notLoaded }
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
        guard loaded else { throw VaultError.notLoaded }
        guard let index = rolls.firstIndex(where: { $0.id == id }) else { throw RollError.noRoll }
        var updated = rolls
        try updated[index].develop(at: Date())
        try persist(updated)
        return rolls
    }
    func photo(rollID: UUID, frame: String) throws -> Data {
        guard loaded else { throw VaultError.notLoaded }
        guard let roll = rolls.first(where: { $0.id == rollID }), roll.frames.contains(frame),
              frame == URL(fileURLWithPath: frame).lastPathComponent else { throw RollError.invalidData }
        guard roll.isReady(at: Date()) else { throw RollError.locked }
        guard let key else { throw RollError.invalidData }
        let bytes = try Data(contentsOf: root.appendingPathComponent(frame))
        return try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: key)
    }
}
