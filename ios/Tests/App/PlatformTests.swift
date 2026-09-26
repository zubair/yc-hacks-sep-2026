import XCTest
import UIKit
import PostcardCore
@testable import Postcard

final class PlatformTests: XCTestCase {
  func testFileDraftStoreRoundTripsPhotoBytes() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("draft-\(UUID()).json")
    let store = FileDraftStore(url: url)
    let draft = PostcardDraft(recipientId: UUID(), recipientName: "Ana", senderName: "Zed", destination: "Porto", message: "Tiles everywhere.", photoData: Data([1, 2, 3, 4]))
    store.save(draft)
    XCTAssertEqual(FileDraftStore(url: url).load(), draft)
    store.clear()
    XCTAssertNil(store.load())
  }

  func testPhotoImporterDownscalesOversizedImages() throws {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let big = UIGraphicsImageRenderer(size: CGSize(width: 6000, height: 4000), format: format).image { context in
      UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 6000, height: 4000))
    }
    let jpeg = try PhotoImporter().makeJPEG(from: big.pngData()!)
    let result = UIImage(data: jpeg)!.cgImage!
    XCTAssertLessThanOrEqual(result.width * result.height, PhotoImporter.maxPixels)
    XCTAssertGreaterThan(result.width * result.height, PhotoImporter.maxPixels / 2, "downscale should land near the cap, not collapse")
    XCTAssertLessThanOrEqual(jpeg.count, PhotoImporter.maxBytes)
  }

  func testPhotoImporterRejectsGarbage() {
    XCTAssertThrowsError(try PhotoImporter().makeJPEG(from: Data("not an image".utf8)))
  }

  func testConfigurationFallsBackToFixtureWhenEmpty() {
    XCTAssertFalse(AppConfiguration(rawURL: "", rawKey: "").isConfigured)
    XCTAssertFalse(AppConfiguration(rawURL: nil, rawKey: nil).isConfigured)
    XCTAssertTrue(AppConfiguration(rawURL: "http://127.0.0.1:54321", rawKey: "sb_publishable_x").isConfigured)
  }

  func testPostureMapping() {
    XCTAssertEqual(DevicePosture.closed.isOpen, false)
    XCTAssertEqual(DevicePosture.partiallyOpen(angleDegrees: 30).isOpen, true)
    XCTAssertEqual(DevicePosture.fullyOpen.isOpen, true)
    XCTAssertNil(DevicePosture.unknown.isOpen)
  }

  @MainActor
  func testConversationPhotoLoadAndRetryErrorPreservesVisiblePhoto() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("postcard-photo-\(UUID()).jpg")
    let photo = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
      UIColor.systemBlue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
    }.jpegData(compressionQuality: 0.8)!
    try photo.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    let service = SpyPostcardService()
    let conversationId = UUID()
    let message = PostcardMessage(
      id: UUID(), conversationId: conversationId, senderId: UUID(), recipientId: UUID(),
      senderName: "Alex", recipientName: "Olivia", destination: "Cinque Terre",
      message: "The sea really is this blue.", photoPath: "fixture/photo.jpg", createdAt: Date()
    )
    await service.setPhotoFixture(messages: [message], url: file)
    let model = ConversationViewModel(service: service, conversationId: conversationId)
    await model.load()
    XCTAssertEqual(model.photoData[message.id], photo)
    XCTAssertNil(model.photoErrors[message.id])

    try FileManager.default.removeItem(at: file)
    await model.retryPhoto(id: message.id)
    XCTAssertEqual(model.photoData[message.id], photo)
    XCTAssertNotNil(model.photoErrors[message.id])
  }
}
