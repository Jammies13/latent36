import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Foundation

// Original recipes, not licensed reproductions of named commercial films.
// Used by the photo vault and preview renderer off the main thread.
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
        let recipe = stock.recipe
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = recipe.saturation
        controls.contrast = recipe.contrast
        image = controls.outputImage ?? image

        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = CGPoint(x: 0, y: recipe.black)
        curve.point1 = CGPoint(x: 0.25, y: recipe.shadow)
        curve.point2 = CGPoint(x: 0.5, y: 0.51)
        curve.point3 = CGPoint(x: 0.75, y: recipe.highlight)
        curve.point4 = CGPoint(x: 1, y: 0.975)
        image = curve.outputImage ?? image

        if recipe.saturation > 0 {
            let balance = CIFilter.temperatureAndTint()
            balance.inputImage = image
            balance.neutral = CIVector(x: 6500, y: 0)
            balance.targetNeutral = CIVector(x: recipe.temperature, y: recipe.tint)
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
        if stock == .meadow || stock == .coast || stock == .dusk {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = image
            switch stock {
            case .meadow:
                matrix.gVector = CIVector(x: 0, y: 1.035, z: 0, w: 0)
                matrix.biasVector = CIVector(x: 0.008, y: 0.003, z: -0.008, w: 0)
            case .coast:
                matrix.rVector = CIVector(x: 0.96, y: 0, z: 0, w: 0)
                matrix.biasVector = CIVector(x: 0, y: 0.012, z: 0.025, w: 0)
            default:
                matrix.rVector = CIVector(x: 1.075, y: 0, z: 0, w: 0)
                matrix.bVector = CIVector(x: 0, y: 0, z: 0.96, w: 0)
                matrix.biasVector = CIVector(x: -0.03, y: 0.012, z: 0.03, w: 0)
            }
            image = matrix.outputImage ?? image
        }
        if stock == .sepia {
            let tone = CIFilter.sepiaTone()
            tone.inputImage = image
            tone.intensity = 0.72
            image = tone.outputImage ?? image
        }
        let vignette = CIFilter.vignette()
        vignette.inputImage = image
        vignette.intensity = stock == .chrome ? 0.22 : 0.35
        vignette.radius = Float(min(bounds.width, bounds.height) * 0.65)
        image = vignette.outputImage ?? image

        // Zero-centered monochrome grain, kept subtle at full resolution.
        if let noise = CIFilter.randomGenerator().outputImage {
            let grain = recipe.grain
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

private struct FilmRecipe {
    var saturation: Float = 0.92
    var contrast: Float = 0.98
    var black: Double = 0.035
    var shadow: Double = 0.23
    var highlight: Double = 0.80
    var temperature: CGFloat = 6500
    var tint: CGFloat = 0
    var grain: CGFloat = 0.045
}

private extension FilmStock {
    var recipe: FilmRecipe {
        // The first four recipes preserve the original release's parameters.
        switch self {
        case .daylight: return FilmRecipe(highlight: 0.79, temperature: 6800)
        case .amber: return FilmRecipe(temperature: 7200, grain: 0.08)
        case .chrome: return FilmRecipe(saturation: 1.16, contrast: 1.08, black: 0.01, shadow: 0.20, temperature: 6350, tint: 3)
        case .silver: return FilmRecipe(saturation: 0, contrast: 1.06, grain: 0.11)
        case .meadow: return FilmRecipe(saturation: 1.06, contrast: 0.97, black: 0.025, shadow: 0.24, highlight: 0.79, temperature: 6750, tint: -3, grain: 0.035)
        case .coast: return FilmRecipe(saturation: 0.78, contrast: 0.94, black: 0.05, shadow: 0.26, highlight: 0.82, temperature: 6000, grain: 0.03)
        case .dusk: return FilmRecipe(saturation: 0.91, contrast: 1.10, black: 0.015, shadow: 0.19, highlight: 0.81, temperature: 7000, tint: 2, grain: 0.095)
        case .faded: return FilmRecipe(saturation: 0.66, contrast: 0.89, black: 0.09, shadow: 0.29, highlight: 0.77, temperature: 7300, tint: 4, grain: 0.065)
        case .sepia: return FilmRecipe(saturation: 0, contrast: 0.96, black: 0.06, shadow: 0.26, highlight: 0.78, grain: 0.08)
        case .noir: return FilmRecipe(saturation: 0, contrast: 1.24, black: 0, shadow: 0.16, highlight: 0.85, grain: 0.16)
        }
    }
}
