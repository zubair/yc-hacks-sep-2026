import Foundation
import ImageIO
import UIKit

enum PostcardPhotoError: LocalizedError {
    case unreadable
    case tooLarge
    case dimensionsTooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable: "That photo could not be opened. Choose another photo."
        case .tooLarge: "The JPEG is over 10 MB. Choose a smaller photo."
        case .dimensionsTooLarge: "The photo is over 20 megapixels. Choose a smaller photo."
        }
    }
}

enum PostcardPhotoProcessor {
    static let maximumBytes = 10_000_000
    static let maximumPixels = 20_000_000

    static func jpegData(from source: Data) throws -> Data {
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            throw PostcardPhotoError.unreadable
        }
        guard width <= maximumPixels / height else {
            throw PostcardPhotoError.dimensionsTooLarge
        }
        guard let image = UIImage(data: source),
              let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw PostcardPhotoError.unreadable
        }
        guard jpeg.count <= maximumBytes else {
            throw PostcardPhotoError.tooLarge
        }
        return jpeg
    }
}
