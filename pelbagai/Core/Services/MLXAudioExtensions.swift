import Foundation
import CoreImage
import MLX
import MLXLMCommon

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ImageInputPreparer {
    private static let maxDimension: CGFloat = 1_024
    private static let compressionQuality: CGFloat = 0.78

    #if canImport(UIKit)
    static func ciImage(from image: UIImage) -> CIImage? {
        let prepared = preparedImage(image, maxDimension: maxDimension)
        guard let data = prepared.jpegData(compressionQuality: compressionQuality)
            ?? prepared.pngData() else {
            if let ciImage = prepared.ciImage { return ciImage }
            if let cgImage = prepared.cgImage { return CIImage(cgImage: cgImage) }
            return CIImage(image: prepared)
        }

        return CIImage(data: data, options: [.applyOrientationProperty: true])
            ?? prepared.ciImage
            ?? prepared.cgImage.map(CIImage.init(cgImage:))
            ?? CIImage(image: prepared)
    }

    static func data(from image: UIImage) -> Data? {
        let prepared = preparedImage(image, maxDimension: maxDimension)
        return prepared.jpegData(compressionQuality: compressionQuality)
            ?? prepared.pngData()
    }

    private static func preparedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let originalSize = image.size
        let longestSide = max(originalSize.width, originalSize.height)
        guard longestSide > maxDimension, longestSide > 0 else {
            return image
        }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(
            width: max(1, floor(originalSize.width * scale)),
            height: max(1, floor(originalSize.height * scale))
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    #elseif canImport(AppKit)
    static func ciImage(from image: NSImage) -> CIImage? {
        guard let data = data(from: image) else {
            return nil
        }
        return CIImage(data: data, options: [.applyOrientationProperty: true])
    }

    static func data(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
            ?? bitmap.representation(using: .png, properties: [:])
    }
    #endif
}
