import Foundation
import ImageIO
import Testing
import UIKit
@testable import Postcard

@Suite("Photo preparation")
@MainActor
struct PostcardPhotoProcessorTests {
    @Test func convertsAChosenImageToJPEGBeforeSending() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8))
        let image = renderer.image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }
        let png = try #require(image.pngData())
        let jpeg = try PostcardPhotoProcessor.jpegData(from: png)
        #expect(jpeg.starts(with: [0xFF, 0xD8]))
        #expect(jpeg.count <= PostcardPhotoProcessor.maximumBytes)
        #expect(CGImageSourceCreateWithData(jpeg as CFData, nil) != nil)
    }

    @Test func rejectsUnreadableBytes() {
        #expect(throws: PostcardPhotoError.self) {
            try PostcardPhotoProcessor.jpegData(from: Data([0, 1, 2, 3]))
        }
    }
}
