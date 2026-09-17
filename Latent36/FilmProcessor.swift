import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Foundation

// Original recipes, not licensed reproductions of named commercial films.
// Called only by Vault's serial actor; no GPU work on the main thread.
struct FilmProcessor {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func render(_ data: Data, stock: FilmStock) throws -> Data {
        guard var image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw RollError.invalidData
        }
        // Keep detail while bounding working memory for container use.
        let scale = min(1, 4096 / max(image.extent.width, image.extent.height))
        if scale < 1 { image = image.transformed(by: .init(scaleX: scale, y: scale)) }
        image = image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
        let bounds = image.extent.integral
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = stock == .silver ? 0 : (stock == .chrome ? 1.16 : 0.92)
        controls.contrast = stock == .chrome ? 1.08 : (stock == .silver ? 1.06 : 0.98)
        image = controls.outputImage ?? image

        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = CGPoint(x: 0, y: stock == .chrome ? 0.01 : 0.035)
        curve.point1 = CGPoint(x: 0.25, y: stock == .chrome ? 0.20 : 0.23)
        curve.point2 = CGPoint(x: 0.5, y: 0.51)
        curve.point3 = CGPoint(x: 0.75, y: stock == .daylight ? 0.79 : 0.80)
        curve.point4 = CGPoint(x: 1, y: 0.975)
        image = curve.outputImage ?? image

        if stock != .silver {
            let balance = CIFilter.temperatureAndTint()
            balance.inputImage = image
            balance.neutral = CIVector(x: 6500, y: 0)
            balance.targetNeutral = CIVector(x: stock == .amber ? 7200 : (stock == .daylight ? 6800 : 6350), y: stock == .chrome ? 3 : 0)
            image = balance.outputImage ?? image
        }
        if stock == .amber {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = image
            matrix.rVector = CIVector(x: 1.04, y: 0, z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: 0.96, w: 0)
            matrix.biasVector = CIVector(x: -0.015, y: 0, z: 0.018, w: 0)
            image = matrix.outputImage ?? image
        }
        let vignette = CIFilter.vignette()
        vignette.inputImage = image
        vignette.intensity = stock == .chrome ? 0.22 : 0.35
        vignette.radius = Float(min(bounds.width, bounds.height) * 0.65)
        image = vignette.outputImage ?? image

        // Zero-centered monochrome grain, kept subtle at full resolution.
        if let noise = CIFilter.randomGenerator().outputImage {
            let grain = stock == .silver ? 0.11 : (stock == .amber ? 0.08 : 0.045)
            let mono = noise.cropped(to: bounds).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            let centered = mono.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: grain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: grain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: grain, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -grain/2, y: -grain/2, z: -grain/2, w: 0)])
            image = centered.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: image])
        }
        guard let jpeg = context.jpegRepresentation(of: image.cropped(to: bounds),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.94]) else {
            throw RollError.invalidData
        }
        return jpeg
    }
}
