import Foundation
import CoreImage
import ImageIO

@main struct TextureChecks {
    static func main() throws {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let bounds = CGRect(x: 0, y: 0, width: 256, height: 256)
        func flat(_ level: CGFloat) -> CIImage {
            CIImage(color: CIColor(red: level, green: level, blue: level)).cropped(to: bounds)
        }
        func pixels(_ image: CIImage) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: 256 * 256 * 4)
            context.render(image, toBitmap: &result, rowBytes: 256 * 4, bounds: bounds, format: .RGBA8, colorSpace: nil)
            return result
        }
        func stats(_ values: [UInt8]) -> (mean: Double, variance: Double) {
            let reds = stride(from: 0, to: values.count, by: 4).map { Double(values[$0]) }
            let mean = reds.reduce(0, +) / Double(reds.count)
            let variance = reds.map { ($0-mean) * ($0-mean) }.reduce(0, +) / Double(reds.count)
            return (mean, variance)
        }
        let mid = flat(0.5)
        let clean = pixels(mid)
        let disabled = pixels(try FilmTexture.grain(mid, amount: 0, size: 2, seed: 17))
        assert(clean == disabled, "Off must preserve the input exactly")
        let classic = pixels(try FilmTexture.grain(mid, amount: 0.22, size: 1, seed: 17))
        let repeatGrain = pixels(try FilmTexture.grain(mid, amount: 0.22, size: 1, seed: 17))
        let different = pixels(try FilmTexture.grain(mid, amount: 0.22, size: 1, seed: 18))
        assert(classic == repeatGrain && classic != different, "Texture must be stable per seed and vary between photographs")
        let fine = pixels(try FilmTexture.grain(mid, amount: 0.10, size: 1, seed: 17))
        let heavy = pixels(try FilmTexture.grain(mid, amount: 0.40, size: 1, seed: 17))
        assert(stats(fine).variance > 1)
        assert(stats(classic).variance > stats(fine).variance * 2)
        assert(stats(heavy).variance > stats(classic).variance * 2)
        assert(abs(stats(classic).mean - stats(clean).mean) < 1.5, "Grain must not change overall exposure")
        for index in stride(from: 0, to: classic.count, by: 4) {
            assert(classic[index] == classic[index+1] && classic[index+1] == classic[index+2], "Grain must be monochrome")
            assert(classic[index+3] == 255, "Texture must not make the photo transparent")
        }
        for level in [CGFloat(0), 0.05, 0.95, 1] {
            let result = pixels(try FilmTexture.grain(flat(level), amount: 0.22, size: 1, seed: 17))
            assert(stats(result).variance < stats(classic).variance * 0.1, "Grain must fade at tonal extremes")
            if level == 0 || level == 1 { assert(result == pixels(flat(level))) }
        }
        let coarse = pixels(try FilmTexture.grain(mid, amount: 0.22, size: 3, seed: 17))
        func neighborDifference(_ values: [UInt8]) -> Double {
            var sum = 0.0
            for y in 0..<256 {
                for x in 0..<255 {
                    let index = (y * 256 + x) * 4
                    sum += abs(Double(values[index]) - Double(values[index+4]))
                }
            }
            return sum / (256 * 255)
        }
        assert(neighborDifference(coarse) < neighborDifference(classic) * 0.75, "Larger grain must have larger clusters")
        let dark = flat(0.2)
        assert(pixels(FilmTexture.bloom(dark, amount: 0.16)) == pixels(dark), "Glow must not fog a dark scene")
        let light = CIImage(color: .white).cropped(to: CGRect(x: 120, y: 120, width: 16, height: 16))
            .composited(over: dark)
        let glow = FilmTexture.bloom(light, amount: 0.16)
        assert(glow.extent == bounds)
        assert(stats(pixels(glow)).mean > stats(pixels(light)).mean, "Bright sources should spread a subtle glow")
        print("PASS: grain strength, size, deterministic seeds, neutral exposure, grayscale, opacity, protected tonal extremes and highlight-only bloom.")

        // Full production renders and detail crops for visual review in Actions.
        let processor = FilmProcessor()
        let sample = try Data(contentsOf: URL(fileURLWithPath: "Latent36/PreviewSamples/river.png"))
        let output = URL(fileURLWithPath: "build/film-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for stock in [FilmStock.amber, .noir] {
            for grain in FilmGrain.allCases {
                try autoreleasepool {
                    let data = try processor.render(sample, stock: stock, grain: grain)
                    let image = CIImage(data: data)!
                    let rect = CGRect(x: (image.extent.width-800)/2, y: (image.extent.height-800)/2, width: 800, height: 800)
                    let crop = image.cropped(to: rect).transformed(by: .init(translationX: -rect.minX, y: -rect.minY))
                    let jpeg = CIContext().jpegRepresentation(of: crop, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:])!
                    try jpeg.write(to: output.appendingPathComponent("grain-\(stock.rawValue)-\(grain.rawValue).jpg"))
                }
            }
        }
        // Confirm production JPEGs remain bounded even with blur and grain.
        let oversized = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 5000, height: 1000))
        let input = CIContext().jpegRepresentation(of: oversized, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:])!
        let outputJPEG = try processor.render(input, stock: .dusk, grain: .heavy)
        let source = CGImageSourceCreateWithData(outputJPEG as CFData, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        assert(decoded.width == 4096 && decoded.height <= 820)
        print("PASS: all grain choices through production renderer; eight detail crops written; 4096-pixel output cap retained.")
    }
}
