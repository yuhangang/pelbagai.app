import Foundation
import CoreImage
import ImageIO
import MLX
import MLXLMCommon

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ImageInputPreparer {
    private static let maxDimension: CGFloat = 1_024
    private static let compressionQuality: CGFloat = 0.85

    #if canImport(UIKit)
    static func ciImage(from image: UIImage) -> CIImage? {
        autoreleasepool {
            guard let data = data(from: image) else {
                if let ciImage = image.ciImage { return ciImage }
                if let cgImage = image.cgImage { return CIImage(cgImage: cgImage) }
                return CIImage(image: image)
            }

            return CIImage(data: data, options: [.applyOrientationProperty: true])
                ?? image.ciImage
                ?? image.cgImage.map(CIImage.init(cgImage:))
                ?? CIImage(image: image)
        }
    }

    static func data(from image: UIImage) -> Data? {
        autoreleasepool {
            if let cgImage = image.cgImage,
               max(image.size.width, image.size.height) <= maxDimension {
                return encodeJPEG(cgImage)
            }

            let prepared = preparedImage(image, maxDimension: maxDimension)
            if let cgImage = prepared.cgImage,
               let encoded = encodeJPEG(cgImage) {
                return encoded
            }
            return prepared.jpegData(compressionQuality: compressionQuality) ?? prepared.pngData()
        }
    }

    static func image(from data: Data) -> UIImage? {
        autoreleasepool {
            if let cgImage = downsampledCGImage(from: data, maxDimension: maxDimension) {
                return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            }
            return UIImage(data: data)
        }
    }

    static func data(fromRawImageData data: Data) -> Data? {
        autoreleasepool {
            if let cgImage = downsampledCGImage(from: data, maxDimension: maxDimension) {
                return encodeJPEG(cgImage)
            }
            return UIImage(data: data).flatMap { Self.data(from: $0) }
        }
    }

    static func preparedForModel(_ image: UIImage) -> UIImage {
        autoreleasepool {
            if max(image.size.width, image.size.height) <= maxDimension {
                return image
            }
            return preparedImage(image, maxDimension: maxDimension)
        }
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

    private static func downsampledCGImage(from data: Data, maxDimension: CGFloat) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    private static func encodeJPEG(_ cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
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
