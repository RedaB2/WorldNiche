import Foundation
import ImageIO
import UniformTypeIdentifiers

@main struct AvatarChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ result: Bool, _ label: String) {
            guard result else { fatalError("FAIL: \(label)") }
            count += 1; print("PASS \(label)")
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("worldniche-avatar-tests-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let source = scratch.appendingPathComponent("source.jpg")
        let context = CGContext(data:nil,width:2048,height:1024,bitsPerComponent:8,bytesPerRow:0,
                                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red:0.1,green:0.5,blue:0.3,alpha:1);context.fill(CGRect(x:0,y:0,width:2048,height:1024))
        let destination = CGImageDestinationCreateWithURL(source as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(destination,context.makeImage()!,[
            kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:34.0,kCGImagePropertyGPSLatitudeRef:"N",kCGImagePropertyGPSLongitude:118.0,kCGImagePropertyGPSLongitudeRef:"W"],
            kCGImagePropertyExifDictionary:[kCGImagePropertyExifDateTimeOriginal:"2026:10:18 12:00:00"],
            kCGImagePropertyTIFFDictionary:[kCGImagePropertyTIFFArtist:"private source metadata"]
        ] as CFDictionary)
        check(CGImageDestinationFinalize(destination),"Fixture carries source metadata")
        let processed = try AvatarPhotoProcessor.jpeg(from:source)
        check(AvatarPhotoReference.isValidJPEG(processed),"Thumbnail is bounded JPEG")
        let image = CGImageSourceCreateWithData(processed as CFData,nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(image,0,nil)! as NSDictionary
        check(properties[kCGImagePropertyPixelWidth] as? Int == 512 && properties[kCGImagePropertyPixelHeight] as? Int == 512,"Thumbnail is exactly 512 by 512")
        check(properties[kCGImagePropertyGPSDictionary] == nil,"GPS metadata removed")
        check(properties[kCGImagePropertyTIFFDictionary] == nil,"Source camera/artist metadata removed")
        let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
        check(exif?[kCGImagePropertyExifDateTimeOriginal] == nil,"Original capture date removed")
        let files = scratch.appendingPathComponent("private-photos")
        let id = try AvatarPhotoFiles.save(processed,directory:files)
        check(AvatarPhotoFiles.load(id,directory:files) == processed,"Guest photo round trips locally")
        check(AvatarPhotoFiles.load("../source",directory:files) == nil,"Local path traversal rejected")
        AvatarPhotoFiles.remove(id,directory:files)
        check(AvatarPhotoFiles.load(id,directory:files) == nil,"Removing photo deletes local bytes")
        let second = try AvatarPhotoFiles.save(processed,directory:files)
        AvatarPhotoFiles.removeAll(directory:files)
        check(AvatarPhotoFiles.load(second,directory:files) == nil,"Clear-device cleanup removes photos")
        check(AvatarPhotoReference.isValidPath("11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222.jpg"),"Canonical private object path accepted")
        for path in ["https://example.com/p.jpg","../photo.jpg","11111111-1111-1111-1111-111111111111/../../secret.jpg","11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222.jpg?token=secret"] {
            check(!AvatarPhotoReference.isValidPath(path),"Untrusted photo path rejected")
        }
        check(!AvatarPhotoReference.isValidJPEG(Data(repeating:0,count:300001)),"Oversized upload rejected")
        check(!AvatarPhotoReference.isValidJPEG(Data("<svg/>".utf8)),"Non-JPEG upload rejected")
        let invalid = scratch.appendingPathComponent("invalid.jpg");try Data("not an image".utf8).write(to:invalid)
        do { _ = try AvatarPhotoProcessor.jpeg(from:invalid);fatalError("Invalid image decoded") }
        catch { count += 1;print("PASS Invalid image produces a recoverable error") }
        let decoder = JSONDecoder();decoder.keyDecodingStrategy = .convertFromSnakeCase
        let legacy = try decoder.decode(ExplorerProfile.self,from:Data(#"{"id":null,"display_name":"Explorer","avatar":"globe","share_exploration":false}"#.utf8))
        check(legacy.avatarPath == nil && legacy.localAvatarID == nil,"Legacy symbol profiles decode without photo fields")
        count += try await AvatarAPIChecks.run()
        print("PASS: \(count) avatar processing, privacy, filesystem, API recovery, and compatibility checks")
    }
}
