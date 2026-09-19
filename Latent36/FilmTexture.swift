import CoreImage
import Foundation

// Shared by sample previews and saved photographs. No repeating noise tiles or
// custom shader compilation, and at most one byte per output pixel of scratch.
enum FilmTexture {
    static func grain(_ image: CIImage, amount: CGFloat, size: CGFloat, seed: UInt64) throws -> CIImage {
        guard amount > 0 else { return image }
        let bounds = image.extent
        let cell = max(1, size)
        let width = Int(ceil(bounds.width / cell))
        let height = Int(ceil(bounds.height / cell))
        var bytes = Data(count: width * height)
        var state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        try bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            for y in 0..<height {
                try Task.checkCancellation()
                for x in 0..<width {
                    // xorshift64* with two averaged uniform samples: softer tails
                    // than white noise, without tinting monochrome stocks.
                    state ^= state >> 12
                    state ^= state << 25
                    state ^= state >> 27
                    let random = state &* 0x2545F4914F6CDD1D
                    buffer[y * width + x] = UInt8(((random >> 56) + ((random >> 48) & 255)) / 2)
                }
            }
        }
        let strength = min(1, amount)
        let noise = CIImage(bitmapData: bytes, bytesPerRow: width,
                            size: CGSize(width: width, height: height), format: .L8, colorSpace: nil)
            .transformed(by: CGAffineTransform(scaleX: cell, y: cell))
            .transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
            .cropped(to: bounds)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: strength, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: strength, w: 0),
                "inputBiasVector": CIVector(x: (1-strength)/2, y: (1-strength)/2, z: (1-strength)/2, w: 0)])
        // Neutral 50% gray is unchanged. Overlay naturally suppresses grain in
        // deep shadows and bright highlights rather than raising the black floor.
        return noise.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: bounds)
    }

    static func bloom(_ image: CIImage, amount: CGFloat) -> CIImage {
        guard amount > 0 else { return image }
        let bounds = image.extent
        let highlights = image.clampedToExtent().applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 4, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 4, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 4, w: 0),
            "inputBiasVector": CIVector(x: -3, y: -3, z: -3, w: 0)])
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(bounds.width, bounds.height) * 0.003])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0)])
        return highlights.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: bounds)
    }
}
