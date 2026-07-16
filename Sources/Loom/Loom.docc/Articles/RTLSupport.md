# Right-to-Left (RTL) Layout

How Loom mirrors layouts for right-to-left languages, what
auto-flips, what doesn't, and how to opt in or override.

## Overview

Loom defers to the system's preferred layout direction by default.
For most apps, **shipping to RTL locales (Arabic, Hebrew, Persian,
Urdu, …) requires no per-call configuration** — the same
``LoomLayout`` that renders left-to-right on an English device
renders mirrored on an Arabic one, automatically.

When you need to override (tests, force-LTR snippets inside an RTL
article, previews), pass an explicit ``LoomDirection`` to the layout.

## Opting in

The default is already what you want. `LoomLayout(width:)` calls with
no `direction:` argument resolve to the system direction at calculate
time (see ``Loom/systemDirection``):

```swift
// Picks up RTL automatically on Arabic / Hebrew / etc. systems.
let layout = LoomLayout(width: 375) {
    HStack(spacing: 8) {
        Fixed(width: 40, height: 40).key(.avatar)
        Text(nameAttr).key(.name).flex(grow: 1)
    }
}
```

Force a direction explicitly when you need determinism:

```swift
// Tests / previews.
let layout = LoomLayout(width: 375, direction: .rtl) {
    /* same DSL */
}
```

## The edge model

`LoomEdge` carries two families of horizontal-axis edges:

| Family | Cases | Direction-aware? | Use for |
|---|---|---|---|
| **Absolute** | `.left`, `.right` | No — always physical | Decorative elements that must NOT mirror (logo pinned to physical-left, pixel-aligned background offsets) |
| **Direction-aware** | `.leading`, `.trailing` | Yes — flips with direction | Content that should mirror (text padding, action button positions, badges) |

Mirrors the `UIEdgeInsets` (absolute) vs `UIDirectionalEdgeInsets`
(direction-aware) split that UIKit added in iOS 11.

The two families **stack additively** on the same physical edge under
a given direction. Under `.ltr`, the physical-left padding equals
`padding.left + padding.leading`; under `.rtl`, the physical-left
padding equals `padding.left + padding.trailing`. In practice you
pick one family per node — additivity is mostly an implementation
detail of how Yoga combines them.

```swift
// Direction-aware: mirrors with the layout direction.
Text(bodyAttr)
    .padding(.leading, 16)   // physical-left under LTR, physical-right under RTL

// Absolute: pinned regardless of direction.
Image("watermark")
    .position(type: .absolute, top: 8, left: 8)  // always top-left corner
```

## Per-subtree override

Embed an explicitly-LTR subtree inside an RTL tree (e.g. a code
snippet inside an Arabic article) with the `.direction(_:)` modifier:

```swift
VStack(spacing: 12) {
    Text(arabicProseAttr).key(.body)
    HStack {
        Text(codeAttr).key(.code)
            .padding(8)
    }
    .direction(.ltr)  // this subtree stays LTR even on RTL devices
}
```

The subtree's direction inherits down to descendants unless they call
`.direction(...)` themselves.

## What auto-flips

When the resolved direction is `.rtl`:

- **HStack** child order — first source-order child sits on the
  physical right, last sits on the physical left.
- **Direction-aware edges** — `.padding(.leading, …)`,
  `.margin(.trailing, …)`, `.position(..., leading:, trailing:)`.
- **Direction-aware ZStack alignments** — `.topLeading`,
  `.topTrailing`, `.centerLeading`, `.centerTrailing`,
  `.bottomLeading`, `.bottomTrailing`.

## What does NOT auto-flip

- **Absolute edges** — `.left`, `.right`, `.top`, `.bottom`,
  `.horizontal`, `.vertical`, `.all`. These are physical edges by
  design.
- **Absolute alignments** — the original 9 `LoomZAlignment` cases
  (`.topLeft`, `.center`, …, `.bottomRight`).
- **View appearance** — corner radii, shadow offsets, gradient
  directions. Loom is a layout framework; mirror these with UIKit
  APIs in your view code if needed.
- **UILabel text alignment** — set
  `paragraphStyle.alignment = .natural` on your attributed string and
  UIKit handles the bidi alignment automatically.
- **Bidi text within a single line** — Core Text / NSStringDrawing
  handle the Unicode bidi algorithm. Loom doesn't touch text content.

## System direction detection

``Loom/systemDirection`` is the source consulted when
`LoomLayout.direction == .inherit`. It is safe to call from any
thread but uses different sources depending on context:

- **Main thread, UIKit available**: reads
  `UIApplication.shared.userInterfaceLayoutDirection`. Reflects the
  application's effective display direction including any
  `UIView.appearance().semanticContentAttribute` override.
- **Off the main thread, or non-UIKit platforms**: reads
  `Locale.characterDirection(forLanguage:)`. Reflects the user's
  locale; ignores app-level overrides.

For 99% of apps the two sources agree. The edge case is when an app
forces a direction via `UISemanticContentAttribute` while the
underlying locale points the other way. If your app does that AND
you compute Loom layouts off-main, **read `Loom.systemDirection`
once on the main thread, cache the value, and pass it through
`LoomLayout(width:direction:)` explicitly**. Loom's explicit
parameter always wins over the auto-detection helper.

## Cache invalidation when direction changes at runtime

Cached frames are direction-specific. If you offer a runtime toggle
(language switcher, accessibility preview), invalidate the cache when
direction changes:

```swift
@objc private func toggleDirection() {
    direction = (direction == .rtl) ? .ltr : .rtl
    layoutCache.invalidateAll()
    tableView.reloadData()
}
```

The `LoomExample` app demonstrates this pattern in
`ViewController.toggleDirection()`.

## Yoga absolute-position quirk

A Yoga implementation detail worth knowing: `position(type: .absolute,
left: ...)` is direction-aware in the bundled Yoga version — under
RTL, `left: 0` snaps the absolute child to the **right** edge of the
parent. The same `YGEdge.left` for `.padding` and `.margin` is
physical, not direction-aware.

If you need a truly physical anchor for an absolute element under
RTL, wrap that subtree in `.direction(.ltr)`:

```swift
ZStack {
    backgroundView()
    Image("logo")
        .position(type: .absolute, top: 0, left: 0)  // would flip under RTL
}
.direction(.ltr)  // pin the whole ZStack to LTR for predictable absolute positioning
```

## See Also

- ``LoomDirection``
- ``Loom/systemDirection``
- ``LoomLayout/init(width:direction:content:)``
- ``LoomNode/direction(_:)``
- <doc:CoreConcepts>
