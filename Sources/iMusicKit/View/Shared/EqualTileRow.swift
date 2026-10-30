import SwiftUI

/// Gives each tile the same width and the height needed by the tallest tile at that width.
struct EqualTileRow: Layout {
    /// Horizontal gap between adjacent tiles, in points.
    var spacing: CGFloat = 8

    /// Measures wrapping content using the final column width rather than each tile's ideal width.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let width: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            width = max(0, proposedWidth)
        } else {
            let idealWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
            width = idealWidth * CGFloat(subviews.count) + gaps
        }
        let tileWidth = max(0, width - gaps) / CGFloat(subviews.count)
        let tileProposal = ProposedViewSize(width: tileWidth, height: nil)
        let height = subviews.map { $0.sizeThatFits(tileProposal).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    /// Places every tile in an equally sized cell, including its background and hit target.
    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let width = max(0, bounds.width - gaps) / CGFloat(subviews.count)
        let tileProposal = ProposedViewSize(width: width, height: bounds.height)
        for (index, tile) in subviews.enumerated() {
            tile.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                anchor: .topLeading,
                proposal: tileProposal
            )
        }
    }
}
