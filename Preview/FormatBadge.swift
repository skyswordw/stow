import SwiftUI

/// The archive's parcel-label badge: Archive Info, Glance's header, Welcome's recents and the Quick
/// Look preview (this file is built into the app and the Quick Look extension).
struct FormatBadge: View {
    let format: ArchiveFormat
    /// Archive Info's is 40 pt tall; Glance's header uses a smaller one. Everything scales with it.
    var height: CGFloat = 40
    /// Quick Look has no asset catalog, so it passes its written-out amber.
    var fill: Color = .accentColor

    var body: some View {
        let scale = height / 40
        let label = ParcelLabel(cornerRadius: 7 * scale, fold: 9 * scale)
        Text(format.badge)
            .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
            .tracking(0.4 * scale)
            .foregroundStyle(.white)
            .frame(width: 34 * scale, height: height)
            .background(fill.gradient, in: label)
            .overlay { label.flap.fill(.white.opacity(0.35)) }
            .accessibilityLabel("\(format.displayName) archive")
    }
}

/// A rounded label whose top-right corner is folded down: the corner is cut off along the fold,
/// and the flap lies inside the label below it, so nothing reaches past the rounded outline.
nonisolated struct ParcelLabel: Shape {
    var cornerRadius: CGFloat
    var fold: CGFloat

    /// The folded-down flap, the triangle under the fold line.
    var flap: some Shape { Flap(fold: fold, radius: crease) }

    /// The fold's own corners are only softened, so it still reads as a crease.
    private var crease: CGFloat { fold * 0.12 }

    func path(in rect: CGRect) -> Path {
        Path.rounded([
            (CGPoint(x: rect.maxX - fold, y: rect.minY), crease),
            (CGPoint(x: rect.maxX, y: rect.minY + fold), crease),
            (CGPoint(x: rect.maxX, y: rect.maxY), cornerRadius),
            (CGPoint(x: rect.minX, y: rect.maxY), cornerRadius),
            (CGPoint(x: rect.minX, y: rect.minY), cornerRadius),
        ])
    }

    private nonisolated struct Flap: Shape {
        let fold: CGFloat
        let radius: CGFloat

        func path(in rect: CGRect) -> Path {
            Path.rounded([
                (CGPoint(x: rect.maxX - fold, y: rect.minY), radius),
                (CGPoint(x: rect.maxX, y: rect.minY + fold), radius),
                (CGPoint(x: rect.maxX - fold, y: rect.minY + fold), radius),
            ])
        }
    }
}

nonisolated private extension Path {
    /// A closed polygon with each corner rounded by its own radius.
    static func rounded(_ corners: [(point: CGPoint, radius: CGFloat)]) -> Path {
        var path = Path()
        guard let last = corners.last, let first = corners.first else { return path }
        path.move(to: CGPoint(x: (last.point.x + first.point.x) / 2, y: (last.point.y + first.point.y) / 2))
        for (index, corner) in corners.enumerated() {
            let next = corners[(index + 1) % corners.count].point
            path.addArc(tangent1End: corner.point, tangent2End: next, radius: corner.radius)
        }
        path.closeSubpath()
        return path
    }
}
