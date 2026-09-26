import SwiftUI
import PostcardCore
import PostcardMotion
import PostcardUI

/// Secondary pane of the compose arrangement on the inner display.
/// The postcard stands on its own half of the fold and reacts to the hinge:
/// state drives the flip, hinge angle drives a gentle tilt, reserved regions are read for the readout.
/// Purely presentational: nothing here mutates state or sends.
@available(iOS 27.1, *)
struct DuoComposeStage: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var foldActive = false

  private var state: PostcardPresentationState { env.presentation.state }
  private var draft: PostcardDraft { env.compose.draft }
  private var isOpen: Bool { state == .writing }
  private var isSealed: Bool { state == .sealed || state == .sending || state == .sent }

  private var hingeDegrees: Double? {
    switch env.presentation.posture {
    case .partiallyOpen(let degrees): degrees
    case .fullyOpen: 180
    case .closed: 0
    case .unknown: nil
    }
  }

  /// Tilt the card back as the device folds (table pose), so it reads like a card propped on the upper half.
  private var tilt: Double {
    guard !reduceMotion, let degrees = hingeDegrees, degrees < 170 else { return 0 }
    return min(35, (180 - degrees) * 0.35)
  }

  var body: some View {
    VStack(spacing: 16) {
      PostcardFlipContainer(isOpen: isOpen) {
        front
      } back: {
        back
      }
      .aspectRatio(1.45, contentMode: .fit)
      .frame(maxWidth: 520)
      .modifier(PostcardSealEffect(isSealed: isSealed))
      .rotation3DEffect(.degrees(-tilt), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
      .animation(.spring(response: 0.5, dampingFraction: 0.8), value: tilt)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(isOpen ? "Postcard back, writing" : isSealed ? "Sealed postcard" : "Postcard front")

      readout
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onGeometryChange(for: Bool.self) { proxy in
      proxy.reservedRegions(kind: .division).contains(where: \.isActive)
    } action: { foldActive = $0 }
  }

  private var front: some View {
    VStack(alignment: .leading, spacing: 0) {
      Group {
        if let data = draft.photoData, let image = UIImage(data: data) {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          ZStack {
            PostcardStyle.ink.opacity(0.06)
            Label("Choose a photo", systemImage: "photo.on.rectangle.angled").foregroundStyle(PostcardStyle.muted)
          }
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 170)
      .clipped()
      VStack(alignment: .leading, spacing: 4) {
        Text("GREETINGS FROM").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(PostcardStyle.muted)
        Text(draft.destination.isEmpty ? "somewhere lovely" : draft.destination)
          .font(.system(.title2, design: .serif)).foregroundStyle(PostcardStyle.ink).lineLimit(1)
      }
      .padding(16)
    }
    .background(PostcardStyle.card)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .shadow(color: PostcardStyle.ink.opacity(0.12), radius: 18, y: 10)
  }

  private var back: some View {
    HStack(alignment: .top, spacing: 14) {
      Text(draft.message.isEmpty ? "Your note appears here as you write." : draft.message)
        .font(.system(.body, design: .serif)).foregroundStyle(draft.message.isEmpty ? PostcardStyle.muted : PostcardStyle.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      Rectangle().fill(PostcardStyle.rule).frame(width: 1)
      VStack(alignment: .leading, spacing: 6) {
        RoundedRectangle(cornerRadius: 3).strokeBorder(PostcardStyle.vermilion, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
          .frame(width: 40, height: 48).frame(maxWidth: .infinity, alignment: .trailing)
        Spacer(minLength: 0)
        Text("TO").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(PostcardStyle.muted)
        Text(draft.recipientName.isEmpty ? "—" : draft.recipientName).font(.subheadline.weight(.semibold)).foregroundStyle(PostcardStyle.ink)
        Text("FROM").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(PostcardStyle.muted)
        Text(draft.senderName.isEmpty ? "—" : draft.senderName).font(.subheadline).foregroundStyle(PostcardStyle.ink)
      }
      .frame(width: 110)
    }
    .padding(18)
    .background(PostcardStyle.card)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .shadow(color: PostcardStyle.ink.opacity(0.12), radius: 18, y: 10)
  }

  private var readout: some View {
    HStack(spacing: 14) {
      Label(hingeDegrees.map { "\(Int($0.rounded()))°" } ?? "—", systemImage: "angle")
      Label(poseText, systemImage: "rectangle.split.2x1")
      Label(foldActive ? "Fold active" : "Flat", systemImage: "square.dashed")
    }
    .font(.caption.monospacedDigit())
    .foregroundStyle(PostcardStyle.muted)
    .padding(.horizontal, 12).padding(.vertical, 6)
    .background(.regularMaterial, in: Capsule())
    .accessibilityElement(children: .combine)
  }

  private var poseText: String {
    switch env.presentation.posture {
    case .closed: "Closed"
    case .partiallyOpen: "Partially open"
    case .fullyOpen: "Fully open"
    case .unknown: "No hinge"
    }
  }
}
