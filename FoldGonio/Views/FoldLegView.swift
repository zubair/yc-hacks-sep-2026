import SwiftUI

/// The measuring screen while the phone is partly folded: a thigh on one half, a shin on the
/// other, and the knee pinned to the fold's frame. The reserved region sets the layout, and the
/// hinge only drives the numbers.
///
/// The leg is drawn straight across the crease, so folding the phone bends the drawing for real.
/// The small side view repeats the bend for anyone watching a flat screen or a 2D simulator.
struct FoldLegView: View {
    let fold: CGRect
    let size: CGSize

    var body: some View {
        let geometry = LegGeometry(fold: fold, size: size)
        let first = geometry.firstHalf
        let second = geometry.secondHalf
        // In tabletop pose the limb runs down the middle, so text keeps to the space beside it.
        let textWidth = geometry.isHorizontalFold ? max(size.width / 2 - 76, 0) : .infinity

        ZStack(alignment: .topLeading) {
            LegCanvas(geometry: geometry)

            HoldRing()
                .frame(width: 92, height: 92)
                .position(geometry.knee)

            FlexionReadout()
                .frame(maxWidth: textWidth, alignment: .leading)
                .padding(20)
                .frame(width: first.width, height: first.height, alignment: .topLeading)
                .offset(x: first.minX, y: first.minY)

            // The foot points trailing (tabletop) or down (book), which keeps these two corners clear.
            HoldStatus()
                .frame(maxWidth: textWidth, alignment: .leading)
                .padding(20)
                .frame(width: second.width, height: second.height, alignment: .bottomLeading)
                .offset(x: second.minX, y: second.minY)

            SideViewInset()
                .frame(width: 150, height: 110)
                .padding(16)
                .frame(width: second.width, height: second.height, alignment: .topTrailing)
                .offset(x: second.minX, y: second.minY)
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct FlexionReadout: View {
    @Environment(GonioModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Knee flexion")
                .font(.headline)
                .foregroundStyle(.secondary)
            AngleReadout(flexion: model.flexion, isLive: model.hinge.isMeasurable, alignment: .leading)
            PostureChip()
        }
    }
}

private struct SideViewInset: View {
    @Environment(GonioModel.self) private var model

    var body: some View {
        LegSideView(flexion: model.flexion)
            .padding(8)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

/// The leg drawn straight through the knee, so the physical fold does the bending.
private struct LegCanvas: View {
    let geometry: LegGeometry

    var body: some View {
        Canvas { context, size in
            // The crease. This is where the hinge meets the knee.
            var crease = Path()
            if geometry.isHorizontalFold {
                crease.move(to: CGPoint(x: 0, y: geometry.knee.y))
                crease.addLine(to: CGPoint(x: size.width, y: geometry.knee.y))
            } else {
                crease.move(to: CGPoint(x: geometry.knee.x, y: 0))
                crease.addLine(to: CGPoint(x: geometry.knee.x, y: size.height))
            }
            context.stroke(crease, with: .color(.orange.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))

            func limb(_ from: CGPoint, _ to: CGPoint, width: CGFloat) {
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(.teal.opacity(0.85)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            limb(geometry.hip, geometry.knee, width: 72)
            limb(geometry.knee, geometry.ankle, width: 54)
            limb(geometry.ankle, geometry.toe, width: 34)

            let radius: CGFloat = 30
            let joint = CGRect(x: geometry.knee.x - radius, y: geometry.knee.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: joint), with: .color(.orange))
            context.stroke(Path(ellipseIn: joint), with: .color(.white), lineWidth: 3)
        }
        .accessibilityHidden(true)
    }
}

/// A side view of the leg, bent to the live angle.
struct LegSideView: View {
    let flexion: Double

    var body: some View {
        Canvas { context, size in
            let theta = flexion * .pi / 180
            let thighLength = size.width * 0.42
            let shinLength = min(size.width * 0.4, size.height * 0.62)
            let footLength = shinLength * 0.3
            let knee = CGPoint(x: size.width * 0.5, y: size.height * 0.3)
            let hip = CGPoint(x: knee.x - thighLength, y: knee.y)
            // Screen y points down, so a positive angle swings the shin downward.
            let ankle = CGPoint(x: knee.x + shinLength * cos(theta), y: knee.y + shinLength * sin(theta))
            // The foot sits at a right angle to the shin, pointing forward.
            let toe = CGPoint(x: ankle.x + footLength * sin(theta), y: ankle.y - footLength * cos(theta))

            // Where a straight leg would be, for reference.
            var reference = Path()
            reference.move(to: knee)
            reference.addLine(to: CGPoint(x: knee.x + shinLength, y: knee.y))
            context.stroke(reference, with: .color(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // The flexion angle, as a wedge from the reference line to the shin.
            let radius = shinLength * 0.35
            var wedge = Path()
            wedge.move(to: knee)
            for step in 0...24 {
                let angle = theta * Double(step) / 24
                wedge.addLine(to: CGPoint(x: knee.x + radius * cos(angle), y: knee.y + radius * sin(angle)))
            }
            wedge.closeSubpath()
            context.fill(wedge, with: .color(.orange.opacity(0.3)))

            var leg = Path()
            leg.move(to: hip)
            leg.addLine(to: knee)
            leg.addLine(to: ankle)
            leg.addLine(to: toe)
            let width = max(size.width * 0.05, 5)
            context.stroke(leg, with: .color(.teal), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

            let dot = width * 1.3
            context.fill(Path(ellipseIn: CGRect(x: knee.x - dot, y: knee.y - dot, width: dot * 2, height: dot * 2)), with: .color(.orange))
        }
        .accessibilityElement()
        .accessibilityLabel("Leg bent to \(Int(flexion.rounded())) degrees")
    }
}
