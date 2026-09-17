import Foundation

func expectFailure(_ action: () throws -> Void) {
    do { try action(); fatalError("Expected operation to be rejected") } catch { }
}
let start = Date(timeIntervalSince1970: 1_800_000_000)
var roll = Roll(stock: .daylight, createdAt: start)
assert(roll.canShoot && !roll.canDevelop && !roll.isReady(at: start))
expectFailure { try roll.develop(at: start) }
for i in 0..<35 { try roll.addFrame("frame-\(i)") }
assert(roll.canShoot && !roll.canDevelop)
expectFailure { try roll.develop(at: start) }
try roll.addFrame("frame-35")
assert(!roll.canShoot && roll.canDevelop)
expectFailure { try roll.addFrame("overflow") }
// Taking the 36th shot alone must never start development.
assert(roll.readyAt == nil && !roll.isReady(at: start.addingTimeInterval(100000)))
let pressDevelop = start.addingTimeInterval(7200)
try roll.develop(at: pressDevelop)
assert(!roll.canShoot && !roll.canDevelop)
expectFailure { try roll.develop(at: pressDevelop.addingTimeInterval(10)) }
expectFailure { try roll.addFrame("late-shot") }
assert(!roll.isReady(at: pressDevelop.addingTimeInterval(86399.999)))
assert(roll.isReady(at: pressDevelop.addingTimeInterval(86400)))
assert(!roll.isReady(at: pressDevelop.addingTimeInterval(-500)))
let restored = try JSONDecoder().decode(Roll.self, from: JSONEncoder().encode(roll))
assert(restored == roll)
assert(restored.readyAt == pressDevelop.addingTimeInterval(86400))
assert(restored.isReady(at: pressDevelop.addingTimeInterval(90000)))
for stock in FilmStock.allCases {
    let saved = try JSONDecoder().decode(Roll.self, from: JSONEncoder().encode(Roll(stock: stock, createdAt: start)))
    assert(saved.stock == stock)
}
print("PASS: roll capacity, rejected early development, explicit timer start, exact 24-hour boundary, no extra captures, persisted deadline, all stocks.")
