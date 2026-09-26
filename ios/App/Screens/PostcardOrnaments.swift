import SwiftUI
import PostcardUI

/// Vermilion stamp with a perforated edge.
struct PostageStamp: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 3).fill(PostcardStyle.vermilion.opacity(0.92))
      RoundedRectangle(cornerRadius: 3)
        .strokeBorder(PostcardStyle.card, style: StrokeStyle(lineWidth: 3, dash: [3, 4]))
      VStack(spacing: 4) {
        Image(systemName: "leaf").font(.system(size: 26, weight: .light))
        Text("ITALIA · €0,70").font(.system(size: 8, weight: .semibold)).tracking(1)
      }
      .foregroundStyle(PostcardStyle.card)
    }
    .frame(width: 64, height: 78)
    .rotationEffect(.degrees(2))
    .accessibilityHidden(true)
  }
}

/// Circular postmark with wavy cancellation lines.
struct Postmark: View {
  var title: String
  var subtitle: String
  var footer: String = "ITALIA"
  var tint: Color = PostcardStyle.vermilion

  var body: some View {
    HStack(spacing: -10) {
      ZStack {
        Circle().strokeBorder(tint, lineWidth: 1.5)
        Circle().strokeBorder(tint, lineWidth: 0.8).padding(5)
        VStack(spacing: 2) {
          Text(title.uppercased()).font(.system(size: 7, weight: .bold)).tracking(1).lineLimit(1).minimumScaleFactor(0.6)
          Text(subtitle).font(.system(size: 9, weight: .semibold))
          Text(footer.uppercased()).font(.system(size: 7, weight: .bold)).tracking(1)
        }
        .foregroundStyle(tint)
        .padding(10)
      }
      .frame(width: 74, height: 74)
      WavyLines(tint: tint).frame(width: 46, height: 40)
    }
    .opacity(0.85)
    .rotationEffect(.degrees(-6))
    .accessibilityHidden(true)
  }
}

private struct WavyLines: View {
  var tint: Color
  var body: some View {
    Canvas { context, size in
      for row in 0..<4 {
        let y = size.height * (0.2 + 0.2 * CGFloat(row))
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        var x: CGFloat = 0
        while x < size.width {
          path.addQuadCurve(to: CGPoint(x: x + 8, y: y), control: CGPoint(x: x + 4, y: y - 3))
          path.addQuadCurve(to: CGPoint(x: x + 16, y: y), control: CGPoint(x: x + 12, y: y + 3))
          x += 16
        }
        context.stroke(path, with: .color(tint), lineWidth: 1)
      }
    }
  }
}

enum PostcardFonts {
  static func hand(_ size: CGFloat) -> Font { .custom("Snell Roundhand", size: size) }
  static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
}

extension Date {
  var postmarkText: String { formatted(.dateTime.day().month(.abbreviated).year()).uppercased() }
}
