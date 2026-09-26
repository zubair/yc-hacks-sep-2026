import SwiftUI
import UIKit

struct PostcardPhoto: View {
    let data: Data?
    var body: some View {
        GeometryReader { geometry in
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .accessibilityLabel("Your postcard photograph")
            } else {
                ZStack {
                    PostcardStyle.ink.opacity(0.06)
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
                        Text("A place worth sharing.").font(.system(.title2, design: .serif))
                        Text("Choose a photo to begin").font(.subheadline)
                    }.foregroundStyle(PostcardStyle.muted).padding()
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}

struct PostcardFront: View {
    let photoData: Data?
    let destination: String
    let recipient: String
    let sealed: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PostcardPhoto(data: photoData)
                .aspectRatio(1.22, contentMode: .fit)
                .overlay(alignment: .topTrailing) { PostcardStamp().padding(18) }
                .overlay(alignment: .bottomTrailing) {
                    if sealed {
                        VStack(spacing: 3) {
                            Image(systemName: "heart.fill").font(.title3)
                            Text("SEALED").font(.system(size: 9, weight: .bold)).tracking(1)
                        }.foregroundStyle(PostcardStyle.card).frame(width: 72, height: 72)
                            .background(PostcardStyle.vermilion, in: Circle())
                            .overlay(Circle().strokeBorder(PostcardStyle.card.opacity(0.6), lineWidth: 1).padding(5))
                            .rotationEffect(.degrees(-10)).padding(16).accessibilityHidden(true)
                    }
                }
            VStack(alignment: .leading, spacing: 7) {
                Text("GREETINGS FROM").font(.caption2.weight(.semibold)).tracking(2)
                    .foregroundStyle(PostcardStyle.muted)
                Text(destination.isEmpty ? "somewhere lovely" : destination)
                    .font(.system(.title, design: .serif)).fixedSize(horizontal: false, vertical: true)
                Divider().overlay(PostcardStyle.rule).padding(.vertical, 8)
                HStack(alignment: .top) {
                    Text(recipient.isEmpty ? "For someone you love" : "For \(recipient)")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 10)
                    Image(systemName: sealed ? "heart.circle" : "arrow.turn.up.right")
                        .foregroundStyle(PostcardStyle.vermilion).accessibilityHidden(true)
                }
            }.padding(22)
        }.padding(8).background(PostcardStyle.card)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PostcardStyle.rule.opacity(0.6), lineWidth: 0.5))
            .shadow(color: PostcardStyle.ink.opacity(0.10), radius: 20, x: 0, y: 10)
    }
}
