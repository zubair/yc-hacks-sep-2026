import Foundation

/// Where the leg goes on a partly folded screen: thigh on the first half, shin on the second,
/// knee pinned to the fold. It handles a horizontal fold (tabletop, portrait) and a vertical
/// one (book, landscape).
///
/// `fold` is the frame of the division reserved region, margins included, in the same
/// coordinate space as `size`.
struct LegGeometry: Equatable, Sendable {
    let isHorizontalFold: Bool
    let hip: CGPoint
    let knee: CGPoint
    let ankle: CGPoint
    let toe: CGPoint
    /// The half before the fold (top or leading), which holds the thigh.
    let firstHalf: CGRect
    /// The half after the fold (bottom or trailing), which holds the shin.
    let secondHalf: CGRect

    init(fold: CGRect, size: CGSize, inset: CGFloat = 28, footLength: CGFloat = 56) {
        isHorizontalFold = fold.width >= fold.height
        if isHorizontalFold {
            knee = CGPoint(x: size.width / 2, y: fold.midY)
            hip = CGPoint(x: knee.x, y: inset)
            ankle = CGPoint(x: knee.x, y: size.height - inset)
            // The foot points forward, toward the trailing edge.
            toe = CGPoint(x: ankle.x + footLength, y: ankle.y)
            firstHalf = CGRect(x: 0, y: 0, width: size.width, height: max(fold.minY, 0))
            secondHalf = CGRect(x: 0, y: fold.maxY, width: size.width, height: max(size.height - fold.maxY, 0))
        } else {
            knee = CGPoint(x: fold.midX, y: size.height / 2)
            hip = CGPoint(x: inset, y: knee.y)
            ankle = CGPoint(x: size.width - inset, y: knee.y)
            toe = CGPoint(x: ankle.x, y: ankle.y + footLength)
            firstHalf = CGRect(x: 0, y: 0, width: max(fold.minX, 0), height: size.height)
            secondHalf = CGRect(x: fold.maxX, y: 0, width: max(size.width - fold.maxX, 0), height: size.height)
        }
    }
}
