import SwiftUI

/// Columns that fill from the top, each new view going under whichever column is shortest, like photos pinned to
/// a board. Views are asked how tall they'd like to be at the column's width.
public struct MasonryLayout: Layout {
    public var columns: Int
    public var spacing: CGFloat

    public init(columns: Int = 2, spacing: CGFloat = 12) {
        self.columns = max(1, columns)
        self.spacing = spacing
    }

    public struct Cache {
        var frames: [CGRect] = []
        var width: CGFloat = -1
        var height: CGFloat = 0
    }

    public func makeCache(subviews: Subviews) -> Cache { Cache() }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 360, height: 0)).width
        arrange(width: width, subviews: subviews, cache: &cache)
        return CGSize(width: width, height: cache.height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        arrange(width: bounds.width, subviews: subviews, cache: &cache)
        for (subview, frame) in zip(subviews, cache.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    private func arrange(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        guard cache.width != width || cache.frames.count != subviews.count else { return }
        let columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var heights = Array(repeating: CGFloat(0), count: columns)
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)
        for subview in subviews {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing), y: heights[column], width: columnWidth, height: height))
            heights[column] += height + spacing
        }
        cache.frames = frames
        cache.width = width
        cache.height = max(0, (heights.max() ?? 0) - spacing)
    }
}
