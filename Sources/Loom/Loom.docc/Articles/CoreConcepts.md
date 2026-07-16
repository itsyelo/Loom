# Core Concepts

Understand the three-phase workflow and the building blocks of Loom.

## The Three Phases

Loom separates layout into three distinct phases:

| Phase | Thread | What Happens |
|-------|--------|-------------|
| **Describe** | Any | Build a virtual node tree (no UIKit dependency) |
| **Calculate** | Any (typically background) | Yoga computes sizes and positions |
| **Apply** | Main | Set `view.frame` from cached results |

## Node Types

### Containers

Containers hold children and control how they're arranged:

| Factory | Direction | Use Case |
|---------|-----------|----------|
| ``VStack`` | Top → Bottom | Vertical list of items |
| ``HStack`` | Left → Right | Horizontal row of items |
| ``ZStack`` | Layered | Overlays (badges, gradients) |

```swift
VStack(spacing: 12, justify: .start, align: .stretch) {
    HStack(spacing: 8, align: .center) {
        // children...
    }
}
```

### Leaf Nodes

Leaf nodes have intrinsic size and no children:

| Factory | Size Source | Use Case |
|---------|-----------|----------|
| ``Text`` | Core Text measurement | Labels, text content |
| ``Fixed`` | Explicit width/height | Avatars, icons |
| ``Spacer`` | Explicit height | Vertical gaps |
| ``Measured`` | Custom closure | Buttons, complex controls |

```swift
Text(attributedString).key(.body)           // auto-measured
Fixed(width: 40, height: 40).key(.avatar)   // explicit size
Measured { maxW, maxH -> CGSize in          // custom logic
    CGSize(width: textWidth + 24, height: 36)
}
```

## Style Modifiers

Every node can be customized with chainable modifiers:

```swift
Text(bodyAttr, maxLines: 2)
    .key(.body)
    .flex(grow: 1, shrink: 1)
    .margin(.horizontal, 12)
```

> Note: Prefer `Text(_, maxLines:)` over `.maxSize(height:)` when you want
> to cap text by line count. A pixel cap rarely equals an integer number
> of rendered lines, so toggling between collapsed and expanded states
> shows a visible jump. `maxLines` snaps the measured frame to the exact
> N-line height. See <doc:MultilineUILabelTips> for the full convention.

### Flex Properties

| Modifier | Effect |
|----------|--------|
| `.flex(grow:)` | Expand to fill extra space |
| `.flex(shrink:)` | Shrink when space is tight |
| `.flexBasis(_:)` | Initial size before distribution |
| `.alignSelf(_:)` | Override parent's cross-axis alignment |

### Sizing

| Modifier | Effect |
|----------|--------|
| `.size(width:height:)` | Set explicit dimensions |
| `.minSize(width:height:)` | Minimum constraints |
| `.maxSize(width:height:)` | Maximum constraints |
| `.aspectRatio(_:)` | Width-to-height ratio |

### Spacing

| Modifier | Effect |
|----------|--------|
| `.padding(_:)` | Inner spacing (container area) |
| `.padding(_:_:)` | Per-edge padding |
| `.margin(_:)` | Outer spacing |
| `.margin(_:_:)` | Per-edge margin |

Per-edge modifiers accept absolute (`.left`, `.right`) and
direction-aware (`.leading`, `.trailing`) edges. The latter flip with
the layout direction; see <doc:RTLSupport>.

## Direction

`LoomLayout(width:)` defaults to ``LoomDirection/inherit``, which
resolves to the system's preferred direction at calculate time —
apps shipped to RTL locales render mirrored automatically. Override
explicitly when you need determinism:

```swift
let layout = LoomLayout(width: 375, direction: .rtl) { … }
```

Per-subtree override via `.direction(_:)`:

```swift
HStack { … }.direction(.ltr)   // pin this subtree to LTR
```

Full story (edge model, what auto-flips, system detection caveats):
<doc:RTLSupport>.

## Keys and LayoutResult

Assign keys to nodes you need frames for. After calculation,
retrieve frames from the ``LayoutResult``:

```swift
// Define keys
enum K: String, LoomKey {
    case avatar, name, body
    var loomKeyValue: String { rawValue }
}

// Build and calculate
let result = LoomLayout(width: 375) {
    HStack { Fixed(width: 40, height: 40).key(K.avatar) }
}.calculate()

// Read results
result.size              // total size
result.height            // shorthand for size.height
result.frame(for: K.avatar)  // CGRect?
result.allFrames         // [(key, frame)] array
```

## Thread Safety

- ``LoomNode`` is a Swift struct (value type) — safe to create on any thread
- ``LoomLayout/calculate(engine:)`` runs Yoga internally — safe on any thread
- ``LayoutResult`` is `Sendable` — safe to pass between threads
- ``TextMeasurer`` uses Core Text with framesetter caching — thread-safe
- Only `view.frame = ...` must happen on the main thread
