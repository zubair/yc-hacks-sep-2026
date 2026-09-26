import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let green = CGColor(red: 0.105, green: 0.255, blue: 0.205, alpha: 1)
let paper = CGColor(red: 0.974, green: 0.955, blue: 0.912, alpha: 1)
let red = CGColor(red: 0.72, green: 0.22, blue: 0.16, alpha: 1)

context.setFillColor(green)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let card = CGRect(x: 118, y: 222, width: 788, height: 580)
context.setFillColor(paper)
context.addPath(CGPath(roundedRect: card, cornerWidth: 26, cornerHeight: 26, transform: nil))
context.fillPath()

context.setStrokeColor(green)
context.setLineWidth(13)
context.setLineCap(.round)
context.move(to: CGPoint(x: 503, y: 270))
context.addLine(to: CGPoint(x: 503, y: 746))
context.strokePath()

for y in [360.0, 420.0, 480.0] {
    context.move(to: CGPoint(x: 560, y: y))
    context.addLine(to: CGPoint(x: 820, y: y))
    context.strokePath()
}

context.setFillColor(red)
context.fillEllipse(in: CGRect(x: 684, y: 604, width: 136, height: 136))
context.setFillColor(paper)
context.fillEllipse(in: CGRect(x: 720, y: 640, width: 64, height: 64))

context.setLineWidth(18)
context.move(to: CGPoint(x: 204, y: 614))
context.addLine(to: CGPoint(x: 340, y: 486))
context.addLine(to: CGPoint(x: 444, y: 584))
context.strokePath()
context.fillEllipse(in: CGRect(x: 260, y: 658, width: 55, height: 55))

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write app icon") }
