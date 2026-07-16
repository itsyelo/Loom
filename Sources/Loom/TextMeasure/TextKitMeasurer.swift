import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A ``TextMeasuring`` implementation backed by TextKit
/// (`NSLayoutManager` + `NSTextContainer`) — the same layout engine
/// `UILabel` uses to render.
///
/// Because measurement and rendering share one engine, the returned size
/// matches `UILabel` **for any attributed string** — mixed fonts, custom
/// `lineSpacing`, no `paragraphStyle` at all — with none of the
/// locked-line-height discipline the Core Text path requires (see
/// <doc:MultilineUILabelTips>). `maxLines` maps directly to
/// `NSTextContainer.maximumNumberOfLines`, mirroring
/// `UILabel.numberOfLines` semantics including truncation.
///
/// Set it as the process-wide default once at launch:
///
/// ```swift
/// // AppDelegate
/// Loom.defaultTextMeasurer = TextKitMeasurer.shared
/// ```
///
/// or pass it per node: `Text(attr, measurer: TextKitMeasurer.shared)`.
///
/// ## Choosing between measurers
///
/// | | ``TextKitMeasurer`` | ``TextMeasurer`` (Core Text) |
/// |---|---|---|
/// | UILabel agreement | Native, any string | Requires locked line heights |
/// | Repeated measurement | No cache | `CTFramesetter` cache |
/// | Best for | Pipeline-style "measure once" flows | Hot paths re-measuring the same strings |
///
/// ## Thread Safety
///
/// A fresh TextKit stack is created per call, so measurement is safe from
/// any thread (TextKit objects are never shared across threads).
public struct TextKitMeasurer: TextMeasuring {
    /// Shared instance. The type is stateless; this exists so call sites
    /// read naturally and compare identically.
    public static let shared = TextKitMeasurer()

    public init() {}

    public func measure(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int
    ) -> CGSize {
        guard attributedString.length > 0 else { return .zero }

        // Truncating-tail matches UILabel's default drawing, including the
        // effect an ellipsis has on the final line's width.
        let pass = Self.runPass(
            attributedString,
            maxWidth: maxWidth,
            maxLines: maxLines,
            lineBreakMode: .byTruncatingTail
        )
        guard pass.usedSize.width > 0, pass.usedSize.height > 0 else { return .zero }
        return Self.clamp(pass.usedSize, maxWidth: maxWidth, maxHeight: maxHeight)
    }

    public func measureDetails(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int
    ) -> TextMeasurement {
        guard attributedString.length > 0 else {
            return TextMeasurement(size: .zero, details: .empty)
        }

        // Word-wrapping pass: line breaks are identical to the truncating
        // pass, but the last visible line keeps its NATURAL break — the
        // engine-agnostic semantics `visibleRange`/`lastLineWidth` promise
        // (and what the Core Text measurer reports).
        let wrap = Self.runPass(
            attributedString,
            maxWidth: maxWidth,
            maxLines: maxLines,
            lineBreakMode: .byWordWrapping
        )
        guard wrap.lineCount > 0, wrap.usedSize.width > 0, wrap.usedSize.height > 0 else {
            return TextMeasurement(size: .zero, details: .empty)
        }

        let isTruncated = wrap.visibleCharacterEnd < attributedString.length

        // The contract: details.size == measure(). When nothing is
        // truncated both line-break modes lay out identically; when
        // truncated, the ellipsis can widen the final line, so defer to
        // the truncating pass for the size.
        let size: CGSize
        if isTruncated {
            size = measure(
                attributedString,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                maxLines: maxLines
            )
        } else {
            size = Self.clamp(wrap.usedSize, maxWidth: maxWidth, maxHeight: maxHeight)
        }

        return TextMeasurement(
            size: size,
            details: TextMeasurement.LineDetails(
                lineCount: wrap.lineCount,
                isTruncated: isTruncated,
                visibleRange: NSRange(location: 0, length: wrap.visibleCharacterEnd),
                lastLineWidth: wrap.lastLineWidth,
                firstBaseline: wrap.firstBaseline,
                lastBaseline: wrap.lastBaseline
            )
        )
    }

    // MARK: - Layout pass

    private struct Pass {
        var usedSize: CGSize = .zero
        var lineCount = 0
        var visibleCharacterEnd = 0
        var lastLineWidth: CGFloat = 0
        var firstBaseline: CGFloat = 0
        var lastBaseline: CGFloat = 0
    }

    private static func runPass(
        _ attributedString: NSAttributedString,
        maxWidth: CGFloat,
        maxLines: Int,
        lineBreakMode: NSLineBreakMode
    ) -> Pass {
        let storage = NSTextStorage(attributedString: attributedString)
        let manager = NSLayoutManager()
        // UILabel does not apply font leading between lines (UITextView
        // does). Matching that here is what makes the two agree for fonts
        // with non-zero leading.
        manager.usesFontLeading = false

        // Unbounded container height: maxLines caps the line count and the
        // returned height is clamped to maxHeight afterwards. Constraining
        // the container itself would clip layout mid-line.
        let container = NSTextContainer(
            size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = maxLines
        container.lineBreakMode = lineBreakMode

        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        var pass = Pass()
        pass.usedSize = manager.usedRect(for: container).size

        let glyphRange = manager.glyphRange(for: container)
        guard glyphRange.length > 0 else { return pass }

        var lastFragmentGlyphRange = NSRange(location: 0, length: 0)
        manager.enumerateLineFragments(
            forGlyphRange: glyphRange
        ) { rect, usedRect, _, range, _ in
            // location(forGlyphAt:).y is the baseline offset within the
            // line fragment; add the fragment's own origin for a
            // top-of-bounds-relative baseline.
            let baseline = rect.minY + manager.location(forGlyphAt: range.location).y
            if pass.lineCount == 0 {
                pass.firstBaseline = baseline
            }
            pass.lineCount += 1
            pass.lastBaseline = baseline
            pass.lastLineWidth = usedRect.width
            lastFragmentGlyphRange = range
        }

        let lastFragmentCharRange = manager.characterRange(
            forGlyphRange: lastFragmentGlyphRange, actualGlyphRange: nil
        )
        pass.visibleCharacterEnd = lastFragmentCharRange.upperBound

        // Exclude trailing whitespace from the last line's width, matching
        // Core Text's typographic-width semantics (a wrap consumes spaces
        // at break points, but string-final whitespace stays in usedRect).
        let string = attributedString.string as NSString
        var contentEnd = lastFragmentCharRange.upperBound
        while contentEnd > lastFragmentCharRange.location,
              let scalar = Unicode.Scalar(string.character(at: contentEnd - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            contentEnd -= 1
        }
        if contentEnd < lastFragmentCharRange.upperBound {
            if contentEnd == lastFragmentCharRange.location {
                pass.lastLineWidth = 0
            } else {
                // x-origin of the first trailing-whitespace glyph == width
                // of the content before it (fragment-relative).
                let firstWhitespaceGlyph = manager.glyphIndexForCharacter(at: contentEnd)
                pass.lastLineWidth = manager.location(forGlyphAt: firstWhitespaceGlyph).x
            }
        }
        return pass
    }

    private static func clamp(
        _ size: CGSize, maxWidth: CGFloat, maxHeight: CGFloat
    ) -> CGSize {
        CGSize(
            width: ceil(min(size.width, maxWidth)),
            height: ceil(min(size.height, maxHeight))
        )
    }
}
