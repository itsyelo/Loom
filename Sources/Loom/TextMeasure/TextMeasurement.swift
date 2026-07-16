import CoreGraphics
import Foundation

/// The result of a detailed text measurement — the size Loom lays out
/// with, plus optional per-line details for UI decisions that a plain
/// `CGSize` can't answer.
///
/// Obtain one from ``TextMeasuring/measureDetails(_:maxWidth:maxHeight:maxLines:)``:
///
/// ```swift
/// let m = Loom.defaultTextMeasurer.measureDetails(
///     bodyAttr, maxWidth: width, maxHeight: .greatestFiniteMagnitude, maxLines: 2
/// )
/// viewModel.isExpandable = m.details?.isTruncated ?? true
/// ```
///
/// ``size`` is always present and **exactly equals** what
/// ``TextMeasuring/measure(_:maxWidth:maxHeight:maxLines:)`` returns for
/// the same inputs — safe to use for layout. ``details`` is `nil` when
/// the measurer doesn't provide line-level information (custom
/// conformers using the protocol's default implementation); both
/// built-in measurers always provide it.
public struct TextMeasurement: Sendable, Equatable {
    /// The measured size — identical to `measure(...)` for the same inputs.
    public let size: CGSize

    /// Line-level details, or `nil` if the measurer doesn't provide them.
    public let details: LineDetails?

    public init(size: CGSize, details: LineDetails? = nil) {
        self.size = size
        self.details = details
    }

    /// Line-level measurement details.
    public struct LineDetails: Sendable, Equatable {
        /// Number of lines contributing to ``TextMeasurement/size``
        /// (after the `maxLines` cap).
        public let lineCount: Int

        /// Whether `maxLines` cut content: some characters did not fit in
        /// the allowed lines. Clamping the returned height to `maxHeight`
        /// does **not** count as truncation — like `UILabel`, character
        /// visibility is decided by lines, not by the height clamp.
        public let isTruncated: Bool

        /// The characters covered by the measured lines, from the start
        /// of the string through the **natural line break** of the last
        /// visible line (UTF-16 indices, like `NSAttributedString.length`).
        ///
        /// "Natural" means the range is not reduced by a truncation
        /// ellipsis — it's the engine-agnostic answer to "where does the
        /// text get cut", which is what a custom "see more" treatment
        /// needs as its insertion point.
        public let visibleRange: NSRange

        /// Typographic width of the last visible line, excluding trailing
        /// whitespace — where an inline badge or "see more" token would go.
        public let lastLineWidth: CGFloat

        /// Distance from the top of the measured bounds to the first
        /// line's baseline. The anchor for future baseline alignment.
        ///
        /// > Note: Baselines are **renderer-specific** — each measurer
        /// > reports its own engine's line placement. For fonts with a
        /// > non-zero line gap (e.g. Helvetica), Core Text includes the
        /// > font's leading while TextKit mirrors `UILabel` and ignores
        /// > it, so absolute baseline values differ across measurers.
        /// > With a locked line height (see <doc:MultilineUILabelTips>)
        /// > the baseline *spacing* agrees across engines.
        public let firstBaseline: CGFloat

        /// Distance from the top of the measured bounds to the last
        /// visible line's baseline. Renderer-specific — see
        /// ``firstBaseline``.
        public let lastBaseline: CGFloat

        public init(
            lineCount: Int,
            isTruncated: Bool,
            visibleRange: NSRange,
            lastLineWidth: CGFloat,
            firstBaseline: CGFloat,
            lastBaseline: CGFloat
        ) {
            self.lineCount = lineCount
            self.isTruncated = isTruncated
            self.visibleRange = visibleRange
            self.lastLineWidth = lastLineWidth
            self.firstBaseline = firstBaseline
            self.lastBaseline = lastBaseline
        }

        /// Details for an empty string: zero lines, nothing truncated.
        public static let empty = LineDetails(
            lineCount: 0,
            isTruncated: false,
            visibleRange: NSRange(location: 0, length: 0),
            lastLineWidth: 0,
            firstBaseline: 0,
            lastBaseline: 0
        )
    }
}
