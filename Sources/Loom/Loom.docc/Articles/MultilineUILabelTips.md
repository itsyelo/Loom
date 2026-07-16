# Multi-line Text in UILabel: Measurement and Jitter

The two distinct UILabel text problems, and which tool fixes which:
premature truncation (use ``TextKitMeasurer``) vs. first-line jitter on
collapse/expand (lock the line height).

## Symptom Index

| Symptom | Problem | Fix |
|---|---|---|
| Last line cut off, or empty band below the text | **A. Measurement mismatch** — the default Core Text measurer and UILabel's TextKit disagree by a few points | Set `Loom.defaultTextMeasurer = TextKitMeasurer.shared` (or lock line heights for the fast Core Text path) |
| First line shifts 3–6pt when toggling collapsed/expanded | **B. UILabel's rendering-mode switch** — a `numberOfLines` 0 ↔ N quirk, independent of measurement | Lock the line height (below). No measurer choice affects this |

In DEBUG builds, ``LoomBindings/apply(_:)`` detects problem A
automatically and prints a warning naming the key.

## Problem A: Premature Truncation

The default ``TextMeasurer`` measures with Core Text
(`CTFramesetterSuggestFrameSizeWithConstraints`); `UILabel` lays out
with TextKit. For attributed strings without locked line heights —
mixed fonts especially — Core Text's height can come up a few points
short, and UILabel truncates one line early inside the measured frame.

Two fixes, pick by workload:

- **``TextKitMeasurer``** (recommended default): measures with UILabel's
  own engine, so any attributed string agrees natively. One line at
  launch covers every `Text` node:

  ```swift
  Loom.defaultTextMeasurer = TextKitMeasurer.shared
  ```

- **Core Text + locked line heights** (the fast path): the framesetter
  cache makes repeated measurement of the same string cheaper. Requires
  the locking convention below on every multi-line string — a
  per-callsite discipline. Prefer it only on hot paths that re-measure
  the same strings frequently.

## Problem B: First-Line Jitter on Toggle

> Important: This section addresses a quirk specific to **`UILabel`**
> and only when you toggle `numberOfLines` between `0` and a non-zero
> value at runtime. It is a *rendering* artifact — switching to
> ``TextKitMeasurer`` does not (and cannot) fix it.

`UILabel` switches between two internal vertical alignment strategies:

- `numberOfLines == 0` — preserves the font's **natural leading** (the
  ascent-above-cap-height region), placing the first line's cap-top a
  few points below the label's `bounds.minY`.
- `numberOfLines > 0` — uses **compact** rendering, placing the first
  line's cap-top at `bounds.minY` directly.

When you toggle between, say, 2 lines and unlimited lines on the same
attributed text, this mode switch produces a jump in the first line's
position within the label's frame. There is no public UIKit API to
override it.

**The magnitude scales with the fonts involved — judge visually before
adopting the lock.** At 13–15pt body sizes the jump is typically
~1–2pt, which many designs accept as-is (with ``TextKitMeasurer``
handling sizing, accepting it means no paragraph-style discipline at
all). With large mixed fonts — a 28pt headline run inside 14pt body —
it reaches 3–6pt and the lock below is warranted.

The fix is a `paragraphStyle` convention on the attributed string.
With per-line height **locked to a single value**, both rendering modes
collapse to the same line geometry and the visible jitter drops to the
iOS subpixel noise floor (~1pt, indistinguishable in practice).

## The Convention

**This convention is required only when** you bind to a `UILabel` AND
you toggle `numberOfLines` between `0` and a non-zero value at runtime
(the "collapse / expand body" pattern). For UILabel with a *fixed*
`numberOfLines`, you can safely use `min < max` and let each line size
naturally to its content — no jitter risk because there's no mode
switch to expose.

For the toggle case, Loom ships the convention as one call —
`lockLineHeight(toTallestOf:)` on `NSMutableParagraphStyle`:

```swift
let paragraphStyle = NSMutableParagraphStyle()
// ... your existing lineSpacing / paragraphSpacing settings ...
paragraphStyle.lockLineHeight(toTallestOf: [bodyFont, boldFont, italicFont, monoFont])
```

which is equivalent to setting both bounds by hand:

```swift
let lockedHeight = [
    bodyFont.lineHeight,
    boldFont.lineHeight,
    italicFont.lineHeight,
    monoFont.lineHeight,
].max() ?? bodyFont.lineHeight
paragraphStyle.minimumLineHeight = lockedHeight
paragraphStyle.maximumLineHeight = lockedHeight
```

Apply the resulting `paragraphStyle` as the `.paragraphStyle` attribute
on every run of your attributed string.

## The Rules (UILabel + numberOfLines toggle)

1. **Pick the MAX of every font's `lineHeight`** that appears in any
   run of the attributed string. Picking a smaller value (e.g. the
   base font when bold runs use a larger size) clamps the line frame
   below the larger glyph's natural advance, so the larger glyph
   overflows into the previous line's descent area and produces
   visible overlap. Empirical evidence: the `[Bug]` entry dated
   2026-04-25 in `issue-01`'s findings.
2. **Set `minimumLineHeight` and `maximumLineHeight` to the same value.**
   In the toggle scenario, leaving them apart lets each line's height
   vary with its content, which re-introduces baseline asymmetry
   across `numberOfLines` modes.
3. **Don't try to compensate per-font.** `min` is *not* a floor for
   smaller fonts and `max` is *not* a ceiling for larger ones — both
   apply to every line uniformly. The single locked value must satisfy
   the largest font's natural lineHeight.
4. **`lineSpacing` / `paragraphSpacing` still work normally** alongside a
   locked line height. They add gaps *between* lines and paragraphs;
   locking line height controls the lines' own frame.

> Note: For UILabel with a **fixed** `numberOfLines` (no runtime
> toggle), prefer `min < max` to let small-font lines stay compact
> and big-font lines (e.g. mixed 28pt headers) get the room they
> need. Locking everything to the largest font's lineHeight makes
> small-font runs look sparse for no benefit.

## End-to-End Example

```swift
let baseFont = UIFont.systemFont(ofSize: 14)
let boldFont = UIFont.boldSystemFont(ofSize: 14)
let monoFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)

let paragraph = NSMutableParagraphStyle()
paragraph.lineSpacing = 4
paragraph.paragraphSpacing = 8
paragraph.lockLineHeight(toTallestOf: [baseFont, boldFont, monoFont])

let body = NSMutableAttributedString(
    string: post.text,
    attributes: [.font: baseFont, .paragraphStyle: paragraph]
)
// ... apply boldFont / monoFont to specific ranges as needed ...

// 1. Loom describes + measures
let layout = LoomLayout(width: 378) {
    Text(body, maxLines: expanded ? nil : 2)
        .key(.body)
}
let frames = layout.calculate()

// 2. Apply on main thread + sync UILabel.numberOfLines to the same N
bodyLabel.attributedText = body
bodyLabel.numberOfLines = expanded ? 0 : 2
bodyLabel.frame = frames.frame(for: .body) ?? .zero
```

> Important: `bodyLabel.numberOfLines` must mirror Loom's `maxLines` for
> the same attributed text. If they disagree, UIKit ignores Loom's frame
> cap and renders extra lines outside it.

## Custom Renderers

If you bind your `Text` node to anything other than `UILabel` —
**`YYLabel`** (Core Text + async drawing), a SwiftUI `Text`, a custom
`CTFrameDraw` view, etc. — the locked-line-height convention above is
not needed. Those renderers don't have UILabel's two-mode internal
alignment, so toggling `numberOfLines` produces zero first-line
jitter without any `paragraphStyle` lock.

**However**, measurement must still match your renderer. This is the
general principle behind ``TextMeasuring``: *whatever draws the text
should also be what sizes it* — `UILabel` is just one renderer among
many, served by the built-in ``TextKitMeasurer``. For renderers whose
natural sizing diverges (the most common case is YYLabel, whose
`YYTextLayout.textBoundingSize` is line-bounds-union and excludes the
trailing font leading), bind a custom ``TextMeasuring`` so Loom's
frame matches what the renderer will actually draw:

```swift
import YYText

struct YYTextMeasurer: TextMeasuring {
    static let shared = YYTextMeasurer()

    func measure(
        _ attr: NSAttributedString,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        maxLines: Int
    ) -> CGSize {
        let container = YYTextContainer(
            size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        )
        container.maximumNumberOfRows = UInt(maxLines)
        return YYTextLayout(container: container, text: attr)?.textBoundingSize ?? .zero
    }
}

// Optional sugar so the call site stays as terse as the default Text:
public func YText(_ attr: NSAttributedString, maxLines: Int? = nil) -> LoomNode {
    Text(attr, maxLines: maxLines, measurer: YYTextMeasurer.shared)
}

// In your layout tree:
YText(bodyAttr, maxLines: 2).key(.body)
```

Loom calls `measure` on whichever thread `LoomLayout.calculate(...)`
runs on — your conformer is responsible for thread safety. The
default ``TextMeasurer/shared`` uses a process-wide framesetter
cache; custom conformers should add their own caching if profiling
shows it matters.

## Residual Jitter

Even with the convention applied correctly, you may notice ~1pt of
position drift on toggle. This is iOS's subpixel rendering noise floor
at line-count transitions and is independent of measurement engine,
``TextMeasurer`` accuracy, or `UILabel` configuration. We've verified
the same residual is present in YYText's own `UILabelSizeExample` demo
when measured with `YYTextLayout` (the gold-standard CoreText
measurer). Eliminating it entirely requires drawing text yourself
without going through `UILabel`'s rendering pipeline; that decision
trade-off is out of scope for a layout framework.

## See Also

- ``Text(_:maxLines:measurer:)``
- ``TextMeasuring``
- ``TextKitMeasurer``
- ``Loom/defaultTextMeasurer``
- ``TextMeasurer/shared``
- ``TextMeasurer/measure(_:maxWidth:maxHeight:maxLines:)``
- <doc:CoreConcepts>
