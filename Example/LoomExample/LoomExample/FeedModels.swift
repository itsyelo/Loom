import UIKit
import Loom

// MARK: - FeedContent

/// Immutable display content for one post: the attributed strings, built
/// exactly once. Both list patterns (pipeline and lazy cache) hold these —
/// rebuilding an equal `NSAttributedString` on every configure/measure
/// wastes main-thread time and defeats the framesetter cache's identity
/// fast path.
struct FeedContent {
    let post: Post
    let nameAttr: NSAttributedString
    let bodyAttr: NSAttributedString
    let timeAttr: NSAttributedString

    init(post: Post) {
        self.post = post
        self.nameAttr = FeedCell.nameAttr(post)
        self.bodyAttr = FeedCell.bodyAttr(post)
        self.timeAttr = FeedCell.timeAttr(post)
    }
}

// MARK: - FeedItemVM

/// The "Feed List Pipeline" view model (see the FeedListPipeline DocC
/// article): a row's content plus BOTH layout states, fully computed on a
/// background thread before the row is ever published to the data source.
/// A cache miss is structurally impossible, and toggling collapsed/expanded
/// costs zero calculation.
struct FeedItemVM {
    let content: FeedContent
    let collapsedLayout: LayoutResult
    let expandedLayout: LayoutResult
    /// Whether the body exceeds the collapsed line cap — decided by
    /// `measureDetails` in one call, no second layout needed.
    let isExpandable: Bool
    var isExpanded = false

    var layout: LayoutResult { isExpanded ? expandedLayout : collapsedLayout }

    /// Builds content and computes the layout states. Call off-main.
    init(post: Post, width: CGFloat, direction: LoomDirection) {
        content = FeedContent(post: post)
        collapsedLayout = FeedCell.buildLayout(
            content: content, width: width, expanded: false, direction: direction
        ).calculate()

        // Rich measurement: does the body actually get cut at 2 lines?
        // The 24pt inset mirrors the body's horizontal margins in
        // FeedCell.buildLayout. Skipping the expanded layout for
        // non-truncated posts saves one calculation per short post.
        let bodyMeasurement = Loom.defaultTextMeasurer.measureDetails(
            content.bodyAttr,
            maxWidth: width - 24,
            maxHeight: .greatestFiniteMagnitude,
            maxLines: 2
        )
        isExpandable = bodyMeasurement.details?.isTruncated ?? true

        expandedLayout = isExpandable
            ? FeedCell.buildLayout(
                content: content, width: width, expanded: true, direction: direction
              ).calculate()
            : collapsedLayout
    }
}
