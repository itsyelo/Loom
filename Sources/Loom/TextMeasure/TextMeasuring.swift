import CoreGraphics
import Foundation

/// A pluggable text measurer.
///
/// Loom calls a `TextMeasuring` whenever a ``Text(_:maxLines:measurer:)``
/// node needs to resolve its size during layout. The default
/// implementation is ``TextMeasurer/shared`` — a Core Text + framesetter
/// cache that matches what `UILabel` / `NSStringDrawing` would render
/// given an attributed string with a "locked line height" paragraph
/// style (see <doc:MultilineUILabelTips>).
///
/// Conform a custom type when your renderer is not `UILabel` and its
/// natural sizing diverges from Core Text's `SuggestedSize`. Common
/// case: binding a multi-line attributed string to `YYLabel`, where
/// `YYTextLayout.textBoundingSize` is line-bounds-union (no trailing
/// font leading) — different from the default measurer by ~1 leading
/// per measurement.
///
/// ```swift
/// struct YYTextMeasurer: TextMeasuring {
///     func measure(
///         _ attr: NSAttributedString,
///         maxWidth: CGFloat,
///         maxHeight: CGFloat,
///         maxLines: Int
///     ) -> CGSize {
///         let container = YYTextContainer(
///             size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
///         )
///         container.maximumNumberOfRows = UInt(maxLines)
///         return YYTextLayout(container: container, text: attr)?.textBoundingSize ?? .zero
///     }
/// }
///
/// // Per-node:
/// Text(attr, maxLines: 2, measurer: YYTextMeasurer()).key(.body)
///
/// // Or wrap in a sugar factory in your app:
/// func YText(_ a: NSAttributedString, maxLines: Int? = nil) -> LoomNode {
///     Text(a, maxLines: maxLines, measurer: YYTextMeasurer.shared)
/// }
/// ```
///
/// ## Thread Safety
///
/// Loom may call `measure(...)` on any thread (typically the queue
/// running ``LoomLayout/calculate(engine:)``). Conformers are
/// responsible for their own internal synchronization. The default
/// ``TextMeasurer/shared`` uses a process-wide framesetter cache with
/// busy-tracking; custom conformers should use similar techniques if
/// they cache anything mutable.
public protocol TextMeasuring: Sendable {
    /// Return the size needed to render `attributedString` within the
    /// given constraints.
    ///
    /// - Parameters:
    ///   - attributedString: Immutable attributed text.
    ///   - maxWidth: Maximum available width
    ///     (`.greatestFiniteMagnitude` for no limit).
    ///   - maxHeight: Maximum available height. Final height is
    ///     clamped to this value (`.greatestFiniteMagnitude` for no
    ///     limit).
    ///   - maxLines: Maximum lines contributing to the returned
    ///     height. Pass `0` for no limit.
    func measure(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int
    ) -> CGSize

    /// Measure with line-level details — line count, truncation, visible
    /// character range, baselines. See ``TextMeasurement``.
    ///
    /// The returned ``TextMeasurement/size`` must equal
    /// ``measure(_:maxWidth:maxHeight:maxLines:)`` for the same inputs.
    ///
    /// A default implementation returns the plain measured size with
    /// ``TextMeasurement/details`` set to `nil`, so existing conformers
    /// keep compiling; both built-in measurers provide full details.
    /// Typically slower than `measure` (details require a real line
    /// layout, bypassing fast paths) — intended for once-per-item
    /// pipeline work, not hot re-measurement loops.
    func measureDetails(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int
    ) -> TextMeasurement
}

extension TextMeasuring {
    public func measureDetails(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int
    ) -> TextMeasurement {
        TextMeasurement(
            size: measure(
                attributedString,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                maxLines: maxLines
            ),
            details: nil
        )
    }
}
