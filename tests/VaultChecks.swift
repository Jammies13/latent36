import Foundation
import CryptoKit

// Uses only disposable fixtures. Never reads an installed app's photographs.
@main struct VaultChecks {
    static func expectFailure(_ action: () async throws -> Void) async {
        do { try await action(); fatalError("Expected vault operation to be rejected") }
        catch { }
    }

    static func main() async throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("latent36-tests-\(UUID().uuidString)")
        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: base) }
        func folder(_ name: String) throws -> URL {
            let result = base.appendingPathComponent(name)
            try manager.createDirectory(at: result, withIntermediateDirectories: true)
            return result
        }
        func writeIndex(_ rolls: [Roll], to root: URL) throws {
            try JSONEncoder().encode(rolls).write(to: root.appendingPathComponent("rolls.json"))
        }
        func expectBytes(_ url: URL, _ expected: Data) throws {
            let actual = try Data(contentsOf: url)
            assert(actual == expected, "File contents changed: \(url.lastPathComponent)")
        }
        let keyBytes = Data(repeating: 42, count: 32)
        let now = Date()
        var developed = Roll(stock: .daylight, createdAt: now.addingTimeInterval(-200000))
        for index in 0..<Roll.capacity { try developed.addFrame("test-\(index).frame") }
        try developed.develop(at: now.addingTimeInterval(-100000))

        let fresh = try folder("fresh")
        let freshVault = Vault(root: fresh)
        await expectFailure { _ = try await freshVault.newRoll(stock: .amber) }
        let initial = try await freshVault.load()
        assert(initial.isEmpty)
        let freshKey = try Data(contentsOf: fresh.appendingPathComponent("vault.key"))
        assert(freshKey.count == 32)
        assert(manager.fileExists(atPath: fresh.appendingPathComponent("rolls.json").path))
        let created = try await freshVault.newRoll(stock: .amber)
        let reopened = try await Vault(root: fresh).load()
        assert(created == reopened && reopened.count == 1)
        try expectBytes(fresh.appendingPathComponent("vault.key"), freshKey)

        // Simulate a crash between the first key write and index write.
        let interrupted = try folder("interrupted")
        try keyBytes.write(to: interrupted.appendingPathComponent("vault.key"))
        _ = try await Vault(root: interrupted).load()
        try expectBytes(interrupted.appendingPathComponent("vault.key"), keyBytes)

        // An absent index must preserve both ciphertext and the only decryption key.
        let orphaned = try folder("orphaned")
        let encrypted = try AES.GCM.seal(Data("preserved photograph".utf8), using: SymmetricKey(data: keyBytes)).combined!
        let frameURL = orphaned.appendingPathComponent(developed.frames[0])
        let keyURL = orphaned.appendingPathComponent("vault.key")
        try encrypted.write(to: frameURL)
        try keyBytes.write(to: keyURL)
        let orphanedVault = Vault(root: orphaned)
        await expectFailure { _ = try await orphanedVault.load() }
        await expectFailure { _ = try await orphanedVault.newRoll(stock: .silver) }
        await expectFailure { _ = try await orphanedVault.develop(developed.id) }
        try expectBytes(keyURL, keyBytes)
        try expectBytes(frameURL, encrypted)
        assert(!manager.fileExists(atPath: orphaned.appendingPathComponent("rolls.json").path))
        // Restoring the index allows retry on the same actor and decrypts original data.
        try writeIndex([developed], to: orphaned)
        _ = try await orphanedVault.load()
        let recovered = try await orphanedVault.photo(rollID: developed.id, frame: developed.frames[0])
        assert(recovered == Data("preserved photograph".utf8))

        let noKey = try folder("orphaned-without-key")
        try encrypted.write(to: noKey.appendingPathComponent("orphan.frame"))
        await expectFailure { _ = try await Vault(root: noKey).load() }
        assert(!manager.fileExists(atPath: noKey.appendingPathComponent("vault.key").path))

        for size in [0, 16, 31, 33] {
            let invalidKey = try folder("invalid-key-\(size)")
            let bytes = Data(repeating: 1, count: size)
            try bytes.write(to: invalidKey.appendingPathComponent("vault.key"))
            await expectFailure { _ = try await Vault(root: invalidKey).load() }
            try writeIndex([developed], to: invalidKey)
            await expectFailure { _ = try await Vault(root: invalidKey).load() }
            try expectBytes(invalidKey.appendingPathComponent("vault.key"), bytes)
        }
        let missingKey = try folder("missing-key")
        try writeIndex([developed], to: missingKey)
        await expectFailure { _ = try await Vault(root: missingKey).load() }
        assert(!manager.fileExists(atPath: missingKey.appendingPathComponent("vault.key").path))

        let damaged = try folder("damaged-index")
        try keyBytes.write(to: damaged.appendingPathComponent("vault.key"))
        let manifest = damaged.appendingPathComponent("rolls.json")
        let brokenJSON = Data("[{broken".utf8)
        try brokenJSON.write(to: manifest)
        let damagedVault = Vault(root: damaged)
        await expectFailure { _ = try await damagedVault.load() }
        try expectBytes(manifest, brokenJSON)

        var overfull = developed
        overfull.frames.append("extra.frame")
        var incomplete = developed
        incomplete.frames.removeLast()
        var repeated = developed
        repeated.frames[1] = repeated.frames[0].uppercased().replacingOccurrences(of: ".FRAME", with: ".frame")
        var reused = developed
        reused.id = UUID()
        let active = Roll(stock: .coast, createdAt: now)
        var invalidLibraries = [[developed, developed], [developed, reused], [overfull], [incomplete], [repeated],
                                [active, Roll(stock: .amber, createdAt: now)]]
        for filename in ["", "../escape.frame", "/absolute.frame", "folder\\escape.frame", "vault.key", "bad\u{0}.frame"] {
            var invalid = developed
            invalid.frames[0] = filename
            invalidLibraries.append([invalid])
        }
        for invalid in invalidLibraries {
            try writeIndex(invalid, to: damaged)
            let before = try Data(contentsOf: manifest)
            await expectFailure { _ = try await damagedVault.load() }
            await expectFailure { _ = try await damagedVault.develop(developed.id) }
            await expectFailure { _ = try await damagedVault.photo(rollID: developed.id, frame: developed.frames[0]) }
            try expectBytes(manifest, before)
            try expectBytes(damaged.appendingPathComponent("vault.key"), keyBytes)
        }
        try writeIndex([active, developed], to: damaged)
        let repaired = try await damagedVault.load()
        assert(repaired == [active, developed])

        // Loading and validation never bypass development or membership checks.
        let locked = try folder("locked")
        var waiting = developed
        waiting.developStartedAt = Date()
        try writeIndex([waiting], to: locked)
        try keyBytes.write(to: locked.appendingPathComponent("vault.key"))
        try encrypted.write(to: locked.appendingPathComponent(waiting.frames[0]))
        let lockedVault = Vault(root: locked)
        _ = try await lockedVault.load()
        await expectFailure { _ = try await lockedVault.photo(rollID: waiting.id, frame: waiting.frames[0]) }
        await expectFailure { _ = try await orphanedVault.photo(rollID: UUID(), frame: developed.frames[0]) }
        await expectFailure { _ = try await orphanedVault.photo(rollID: developed.id, frame: "../escape.frame") }
        print("PASS: vault initialization, key preservation, damaged indexes, failed-load isolation, retry, decryption and development lock.")
    }
}
