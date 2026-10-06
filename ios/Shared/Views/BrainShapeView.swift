import SwiftUI

/// One square of a Brain Battle rotation puzzle (polyomino cell).
struct BrainCell: Hashable {
    let x: Int
    let y: Int

    /// Parses `[[x, y], ...]` from an untyped server payload.
    static func list(from value: Any?) -> [BrainCell] {
        guard let raw = value as? [Any] else { return [] }
        var out: [BrainCell] = []
        for item in raw {
            guard let pair = item as? [Any], pair.count >= 2,
                  let x = pair[0] as? Int, let y = pair[1] as? Int
            else { continue }
            out.append(BrainCell(x: x, y: y))
        }
        return out
    }

    /// Parses `[[[x, y], ...], ...]` (the four answer shapes).
    static func shapes(from value: Any?) -> [[BrainCell]] {
        guard let raw = value as? [Any] else { return [] }
        return raw.map { BrainCell.list(from: $0) }
    }
}

/// Draws a polyomino from cell data: rounded squares with a few darker
/// offset layers underneath for a subtle 3D extrusion. Used by the TV
/// board (target + four choices) and on the phone's answer buttons, so both
/// screens show exactly the same shapes.
struct BrainShapeView: View {
    let cells: [BrainCell]
    var color: Color = Color(hex: "38BDF8")
    /// Number of extrusion layers drawn under the top face.
    var depth: Int = 3

    var body: some View {
        Canvas { context, size in
            let layout = BrainShapeLayout(cells: cells, size: size, depth: depth)
            guard layout.unit > 0 else { return }
            let radius: CGFloat = layout.unit * 0.22
            let step: CGFloat = layout.unit * 0.07

            // Extrusion: darkest layer furthest away.
            var layer: Int = depth
            while layer >= 1 {
                let offset: CGFloat = step * CGFloat(layer)
                for rect in layout.rects {
                    let r = rect.offsetBy(dx: offset, dy: offset)
                    let path = Path(roundedRect: r, cornerRadius: radius)
                    context.fill(path, with: .color(Color.black.opacity(0.55)))
                    context.fill(path, with: .color(color.opacity(0.35)))
                }
                layer -= 1
            }

            // Top faces with a soft diagonal sheen and a bright rim.
            for rect in layout.rects {
                let path = Path(roundedRect: rect, cornerRadius: radius)
                let gradient = Gradient(colors: [color, color.opacity(0.72)])
                context.fill(path, with: .linearGradient(gradient,
                                                         startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                                         endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                let shine = Path(roundedRect: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
                                    .offsetBy(dx: -rect.width * 0.08, dy: -rect.height * 0.08),
                                 cornerRadius: radius * 0.6)
                context.fill(shine, with: .color(Color.white.opacity(0.16)))
                context.stroke(path, with: .color(Color.white.opacity(0.45)), lineWidth: max(1, rect.width * 0.04))
            }
        }
    }
}

/// Pure geometry for `BrainShapeView`: fits the shape's bounding box into
/// the available size (leaving room for the extrusion) and centres it.
struct BrainShapeLayout {
    let unit: CGFloat
    let rects: [CGRect]

    init(cells: [BrainCell], size: CGSize, depth: Int) {
        guard !cells.isEmpty, size.width > 0, size.height > 0 else {
            unit = 0
            rects = []
            return
        }
        let xs: [Int] = cells.map { $0.x }
        let ys: [Int] = cells.map { $0.y }
        let minX: Int = xs.min() ?? 0
        let minY: Int = ys.min() ?? 0
        let cols: CGFloat = CGFloat((xs.max() ?? 0) - minX + 1)
        let rows: CGFloat = CGFloat((ys.max() ?? 0) - minY + 1)
        let extra: CGFloat = 0.07 * CGFloat(depth) + 0.1
        let fitted: CGFloat = min(size.width / (cols + extra), size.height / (rows + extra))
        let gap: CGFloat = fitted * 0.08
        let originX: CGFloat = (size.width - fitted * (cols + extra)) / 2 + fitted * 0.05
        let originY: CGFloat = (size.height - fitted * (rows + extra)) / 2 + fitted * 0.05
        var out: [CGRect] = []
        for cell in cells {
            let x: CGFloat = originX + CGFloat(cell.x - minX) * fitted + gap / 2
            let y: CGFloat = originY + CGFloat(cell.y - minY) * fitted + gap / 2
            out.append(CGRect(x: x, y: y, width: fitted - gap, height: fitted - gap))
        }
        unit = fitted
        rects = out
    }
}
