#if canImport(UIKit)
import UIKit

extension NSMutableParagraphStyle {
    /// Lock every line's height to the tallest font's `lineHeight` — the
    /// fix for `UILabel`'s first-line jitter when toggling `numberOfLines`
    /// between `0` and a non-zero value (collapse/expand).
    ///
    /// Pass **every** font that appears in any run of the attributed
    /// string. Locking to less than the tallest font's natural line
    /// height makes larger glyphs overflow into the previous line.
    ///
    /// ```swift
    /// let style = NSMutableParagraphStyle()
    /// style.lineSpacing = 4
    /// style.lockLineHeight(toTallestOf: [bodyFont, boldFont, monoFont])
    /// ```
    ///
    /// Only needed for the toggle case, and only when the ~1–2pt jitter
    /// at body sizes is visually unacceptable (it reaches 3–6pt with
    /// large mixed fonts) — see <doc:MultilineUILabelTips>. Composes
    /// with `lineSpacing` / `paragraphSpacing`, which keep working
    /// normally alongside a locked height.
    public func lockLineHeight(toTallestOf fonts: [UIFont]) {
        guard let tallest = fonts.map(\.lineHeight).max() else { return }
        minimumLineHeight = tallest
        maximumLineHeight = tallest
    }
}
#endif
