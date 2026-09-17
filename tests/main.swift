import Foundation
import CoreImage
import ImageIO

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

// Render all recipes using a color gradient; confirm valid, nonblank JPEGs.
let context = CIContext()
let gradient = CIFilter(name: "CILinearGradient", parameters: [
    "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 160, y: 120),
    "inputColor0": CIColor(red: 0.1, green: 0.3, blue: 0.6),
    "inputColor1": CIColor(red: 0.9, green: 0.7, blue: 0.4)])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 160, height: 120))
let original = context.jpegRepresentation(of: gradient, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:])!
let processor = FilmProcessor()
for stock in FilmStock.allCases {
    let jpeg = try processor.render(original, stock: stock)
    guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Invalid JPEG") }
    assert(cg.width == 160 && cg.height == 120)
    var pixels = [UInt8](repeating: 0, count: 160 * 120 * 4)
    let bitmap = CGContext(data: &pixels, width: 160, height: 120, bitsPerComponent: 8, bytesPerRow: 160 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.draw(cg, in: CGRect(x: 0, y: 0, width: 160, height: 120))
    let levels = stride(from: 0, to: pixels.count, by: 4).map { Int(pixels[$0]) }
    assert(levels.max()! - levels.min()! > 30, "Recipe lost image detail")
    let mean = levels.reduce(0, +) / levels.count
    assert(mean > 10 && mean < 245, "Recipe is nearly blank")
    if stock == .silver {
        let differences: [Int] = stride(from: 0, to: pixels.count, by: 4).map { index in
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            return abs(red - green) + abs(green - blue)
        }
        assert(differences.reduce(0,+) / differences.count < 5, "Silver should be monochrome")
    }
}
expectFailure { _ = try processor.render(Data([0,1,2]), stock: .daylight) }
print("PASS: all four film recipes create nonblank, correctly sized JPEGs; Silver is monochrome; invalid captures rejected.")
