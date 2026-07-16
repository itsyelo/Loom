import CoreGraphics
import CoreText
import Foundation

/// Thread-safe text measurement backed by Core Text (`CTFramesetter`).
///
/// Repeated measurements of the same attributed string are amortized via
/// a process-wide ``CTFramesetter`` cache with busy-tracking, so feed
/// scroll and prefetch paths only pay the framesetter construction cost
/// on a true cache miss.
///
/// The returned size is what `UILabel` would render for the same
/// attributed string and `numberOfLines`. For pixel-accurate agreement
/// across collapsed/expanded toggles, configure the attributed string's
/// `paragraphStyle` to lock per-line height — see <doc:MultilineUILabelTips>.
///
/// ```swift
/// Measured { maxWidth, maxHeight -> CGSize in
///     let textSize = TextMeasurer.measure(attrTitle, maxWidth: maxWidth, maxHeight: maxHeight)
///     return CGSize(width: textSize.width + 24, height: 36)
/// }
/// ```
public enum TextMeasurer {
    /// The default ``TextMeasuring`` instance backed by Core Text and
    /// the framesetter cache. Pass this (or any other ``TextMeasuring``)
    /// to ``Text(_:maxLines:measurer:)``.
    public static let shared: any TextMeasuring = DefaultTextMeasurer()

    /// Measure the size of an attributed string within the given constraints.
    ///
    /// - Parameters:
    ///   - attributedString: The text to measure. Must be immutable; mutating
    ///     it after passing in invalidates the framesetter cache identity.
    ///   - maxWidth: Maximum available width (`.greatestFiniteMagnitude` for
    ///     no limit).
    ///   - maxHeight: Maximum available height. The final height is clamped
    ///     to this value (`.greatestFiniteMagnitude` for no limit).
    ///   - maxLines: Maximum lines contributing to the returned height.
    ///     Pass `0` (default) for no limit.
    /// - Returns: The ceil'd size needed to render the text.
    public static func measure(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int = 0
    ) -> CGSize {
        guard attributedString.length > 0 else { return .zero }

        let entry = FramesetterCache.shared.acquire(for: attributedString)
        defer { FramesetterCache.shared.release(entry) }

        if maxLines > 0 {
            // Line-capped: needs a real CTFrame to find where line N ends;
            // shares the implementation with the details path.
            return detailsByLineLayout(
                attributedString,
                framesetter: entry.framesetter,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                maxLines: maxLines
            ).size
        } else {
            return measureBySuggestedSize(
                framesetter: entry.framesetter,
                maxWidth: maxWidth,
                maxHeight: maxHeight
            )
        }
    }

    /// Measure with line-level details. Always builds a `CTFrame` (the
    /// unbounded fast path can't report lines), so prefer plain
    /// ``measure(_:maxWidth:maxHeight:maxLines:)`` on hot paths that only
    /// need a size.
    public static func measureDetails(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int = 0
    ) -> TextMeasurement {
        guard attributedString.length > 0 else {
            return TextMeasurement(size: .zero, details: .empty)
        }

        let entry = FramesetterCache.shared.acquire(for: attributedString)
        defer { FramesetterCache.shared.release(entry) }

        return detailsByLineLayout(
            attributedString,
            framesetter: entry.framesetter,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            maxLines: maxLines
        )
    }

    // MARK: - Unbounded line count

    /// Single-call Core Text measurement when there is no maxLines cap.
    /// This is the hot path for caches and the cheapest of the two paths.
    private static func measureBySuggestedSize(
        framesetter: CTFramesetter,
        maxWidth: CGFloat,
        maxHeight: CGFloat
    ) -> CGSize {
        let constraint = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        var fitRange = CFRange(location: 0, length: 0)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            constraint,
            &fitRange
        )

        guard suggested.width > 0, suggested.height > 0 else { return .zero }

        return CGSize(
            width: ceil(min(suggested.width, maxWidth)),
            height: ceil(min(suggested.height, maxHeight))
        )
    }

    // MARK: - Line layout (details + line-capped sizing)

    /// Build a CTFrame to discover the real lines, then call
    /// `CTFramesetterSuggestFrameSizeWithConstraints` on the string
    /// range covering the visible lines. Using the same suggested-size
    /// API as the unbounded path guarantees both paths report the same
    /// size metric (height includes line leading, paragraph spacing,
    /// locked line heights, etc.) for the same input.
    private static func detailsByLineLayout(
        _ attributedString: NSAttributedString,
        framesetter: CTFramesetter,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int
    ) -> TextMeasurement {
        // Large but finite path height so Core Text emits every line.
        // Must NOT be `CGFloat.greatestFiniteMagnitude` — CTFrame coords
        // at ~1.8e308 cause catastrophic floating-point cancellation in
        // any subsequent y-arithmetic. 100k pt is well above any realistic
        // body of text.
        let pathRect = CGRect(x: 0, y: 0, width: maxWidth, height: 100_000)
        let path = CGPath(rect: pathRect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), path, nil
        )
        let allLines = CTFrameGetLines(frame) as? [CTLine] ?? []
        guard !allLines.isEmpty else {
            return TextMeasurement(size: .zero, details: .empty)
        }

        // Visible lines: everything from the start of the string through
        // the natural break of line N-1 (or the last existing line).
        let n = maxLines > 0 ? min(maxLines, allLines.count) : allLines.count
        let lastLine = allLines[n - 1]
        let lastLineRange = CTLineGetStringRange(lastLine)
        let visibleEnd = lastLineRange.location + lastLineRange.length
        let visibleRange = NSRange(location: 0, length: visibleEnd)

        // SuggestedSize on the visible range uses the same algorithm
        // as the unbounded path — identical metric definition.
        var fitRange = CFRange(location: 0, length: 0)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: visibleEnd),
            nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            &fitRange
        )

        guard suggested.width > 0, suggested.height > 0 else {
            return TextMeasurement(size: .zero, details: .empty)
        }

        let size = CGSize(
            width: ceil(min(suggested.width, maxWidth)),
            height: ceil(min(suggested.height, maxHeight))
        )

        // Baselines: CTFrame coordinates are bottom-up within the path,
        // so distance-from-top = pathHeight - originY.
        var origins = [CGPoint](repeating: .zero, count: n)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: n), &origins)
        let firstBaseline = pathRect.height - origins[0].y
        let lastBaseline = pathRect.height - origins[n - 1].y

        let lastLineWidth = CGFloat(
            CTLineGetTypographicBounds(lastLine, nil, nil, nil)
                - CTLineGetTrailingWhitespaceWidth(lastLine)
        )

        return TextMeasurement(
            size: size,
            details: TextMeasurement.LineDetails(
                lineCount: n,
                isTruncated: visibleEnd < attributedString.length,
                visibleRange: visibleRange,
                lastLineWidth: lastLineWidth,
                firstBaseline: firstBaseline,
                lastBaseline: lastBaseline
            )
        )
    }
}

// MARK: - Framesetter Cache

/// Process-wide cache of `CTFramesetter` instances keyed by attributed
/// string identity. Busy-tracking ensures two threads measuring the
/// same key concurrently don't share a single framesetter (CTFramesetter
/// is documented as not safe for concurrent use); the second thread
/// transparently builds a fresh one and the cache keeps the first.
private final class FramesetterCache: @unchecked Sendable {
    static let shared = FramesetterCache()

    private let cache = NSCache<NSAttributedString, FramesetterEntry>()
    private let lock = NSLock()
    private var busy = Set<ObjectIdentifier>()

    init(countLimit: Int = 100) {
        cache.countLimit = countLimit
    }

    /// Acquire a framesetter entry. Always returns a usable entry. Callers
    /// MUST call `release(_:)` when done so concurrent measurements of the
    /// same key can reuse the cached framesetter.
    func acquire(for key: NSAttributedString) -> FramesetterEntry {
        lock.lock()
        if let cached = cache.object(forKey: key) {
            let id = ObjectIdentifier(cached)
            if !busy.contains(id) {
                busy.insert(id)
                lock.unlock()
                return cached
            }
        }
        lock.unlock()

        // Cache miss, or cached entry is busy on another thread — build a
        // fresh framesetter and store it if no entry exists yet.
        let framesetter = CTFramesetterCreateWithAttributedString(key)
        let entry = FramesetterEntry(framesetter)

        lock.lock()
        if cache.object(forKey: key) == nil {
            cache.setObject(entry, forKey: key)
        }
        busy.insert(ObjectIdentifier(entry))
        lock.unlock()
        return entry
    }

    func release(_ entry: FramesetterEntry) {
        lock.lock()
        busy.remove(ObjectIdentifier(entry))
        lock.unlock()
    }
}

/// Wrapper that lets `CTFramesetter` (a CoreFoundation type) live inside
/// `NSCache` (which requires AnyObject values).
private final class FramesetterEntry {
    let framesetter: CTFramesetter
    init(_ framesetter: CTFramesetter) {
        self.framesetter = framesetter
    }
}

// MARK: - Default TextMeasuring

/// Default ``TextMeasuring`` implementation. Forwards to the static
/// ``TextMeasurer/measure(_:maxWidth:maxHeight:maxLines:)`` so the
/// existing Core Text path and framesetter cache are reused.
///
/// Use ``TextMeasurer/shared`` rather than constructing this directly
/// so all default-measurer call sites share the same instance.
public struct DefaultTextMeasurer: TextMeasuring {
    public init() {}

    public func measure(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int
    ) -> CGSize {
        TextMeasurer.measure(
            attributedString,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            maxLines: maxLines
        )
    }

    public func measureDetails(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int
    ) -> TextMeasurement {
        TextMeasurer.measureDetails(
            attributedString,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            maxLines: maxLines
        )
    }
}
