import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

/// Image inspection and thumbnail generation built on ImageIO.
enum ImageUtil {
    struct Inspection {
        let fileExtension: String   // "jpg", "png", "heic", ...
        let width: Int
        let height: Int
        let captureDate: Date?      // from EXIF DateTimeOriginal, if present
    }

    static func inspect(_ data: Data) -> Inspection? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        var ext = "jpg"
        if let typeID = CGImageSourceGetType(source) as String?,
           let utType = UTType(typeID),
           let preferred = utType.preferredFilenameExtension {
            ext = preferred == "jpeg" ? "jpg" : preferred
        }

        var width = 0, height = 0
        var captureDate: Date?
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
            height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                captureDate = exifDateFormatter.date(from: dateString)
            }
        }
        return Inspection(fileExtension: ext, width: width, height: height, captureDate: captureDate)
    }

    /// JPEG thumbnail with the longest side capped at `maxPixel`.
    static func makeThumbnail(from data: Data, maxPixel: Int = 400) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }

    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
