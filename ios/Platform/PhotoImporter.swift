import Foundation
import UIKit

enum PhotoImportError: LocalizedError, Equatable {
  case unreadable
  case tooLarge

  var errorDescription: String? {
    switch self {
    case .unreadable: "That photo couldn't be read. Try another one."
    case .tooLarge: "That photo is too large even after resizing. Try a smaller one."
    }
  }
}

/// Converts picked images to JPEG within the backend limits: ≤ 10 MB and ≤ 20 megapixels.
/// Oversized images are downscaled/recompressed rather than rejected outright.
struct PhotoImporter: Sendable {
  static let maxBytes = 10 * 1024 * 1024
  static let maxPixels = 20_000_000

  func makeJPEG(from data: Data) throws -> Data {
    guard let image = UIImage(data: data), let cgImage = image.cgImage else { throw PhotoImportError.unreadable }
    let pixels = cgImage.width * cgImage.height
    var working = image
    if pixels > Self.maxPixels {
      let scale = (Double(Self.maxPixels) / Double(pixels)).squareRoot()
      let size = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
      // Scale 1 so the pixel count matches `size`; the default format would multiply by the screen scale.
      let format = UIGraphicsImageRendererFormat.default()
      format.scale = 1
      working = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    for quality in [0.9, 0.8, 0.7, 0.6, 0.5, 0.4] {
      if let jpeg = working.jpegData(compressionQuality: quality), jpeg.count <= Self.maxBytes { return jpeg }
    }
    throw PhotoImportError.tooLarge
  }
}
