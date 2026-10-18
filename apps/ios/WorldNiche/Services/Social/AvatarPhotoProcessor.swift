import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct SelectedAvatarPhoto: Transferable, Sendable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            SelectedAvatarPhoto(data: try AvatarPhotoProcessor.jpeg(from: received.file))
        }
    }
}

enum AvatarPhotoProcessor {
    /// Decode a thumbnail, then render into new pixels. No source EXIF/GPS or other metadata is copied.
    static func jpeg(from url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 50_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let context = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw SocialError.invalidPhoto }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        let scale = max(512 / CGFloat(thumbnail.width), 512 / CGFloat(thumbnail.height))
        let width = CGFloat(thumbnail.width) * scale, height = CGFloat(thumbnail.height) * scale
        context.interpolationQuality = .high
        context.draw(thumbnail, in: CGRect(x: (512 - width) / 2, y: (512 - height) / 2, width: width, height: height))
        guard let image = context.makeImage() else { throw SocialError.invalidPhoto }
        for quality in [0.85, 0.7, 0.5] {
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw SocialError.invalidPhoto
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), AvatarPhotoReference.isValidJPEG(result as Data) { return result as Data }
        }
        throw SocialError.invalidPhoto
    }
}
