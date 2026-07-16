# Advanced Usage

ZStack overlays, custom measurement, debug tools, and async APIs.

## ZStack Overlays

``ZStack`` layers children on top of each other. The first child sizes the container;
subsequent children are positioned according to the alignment:

```swift
ZStack(alignment: .bottomRight) {
    Fixed(width: 40, height: 40).key(.avatar)     // sizes container
    Fixed(width: 12, height: 12).key(.badge)       // positioned at bottom-right
}
```

### Alignment Options

``LoomZAlignment`` provides 9 positions:

| | Left | Center | Right |
|---|---|---|---|
| **Top** | `.topLeft` | `.topCenter` | `.topRight` |
| **Center** | `.centerLeft` | `.center` | `.centerRight` |
| **Bottom** | `.bottomLeft` | `.bottomCenter` | `.bottomRight` |

### Image Overlay Example

```swift
ZStack(alignment: .bottomLeft) {
    Spacer(0).size(height: 200).key(.coverImage)
    Spacer(0).size(height: 40).key(.gradient)       // overlay
    Text(titleAttr).key(.imageTitle)
        .margin(.left, 12).margin(.bottom, 12)
}
```

## Custom Measurement

Use ``Measured(_:)`` for controls whose size depends on content but can't be
measured with Core Text:

```swift
Measured { maxWidth, maxHeight -> CGSize in
    let textSize = TextMeasurer.measure(titleAttr, maxWidth: .greatestFiniteMagnitude, maxHeight: 36)
    let iconWidth: CGFloat = 20
    let padding: CGFloat = 12
    let spacing: CGFloat = 4
    return CGSize(
        width: padding + iconWidth + spacing + textSize.width + padding,
        height: 36
    )
}
```

The closure must be `@Sendable` (thread-safe). Use ``TextMeasurer/measure(_:maxWidth:maxHeight:)``
for text sizing within the closure.

## Wrapping Layout

Use `wrap: .wrap` on ``HStack`` for tag clouds or action bars that flow to the next line:

```swift
HStack(spacing: 8, lineSpacing: 12, wrap: .wrap) {
    for tag in tags {
        Text(tag.attr).key("tag-\(tag.id)")
    }
}
```

- `spacing` — gap between items on the same line
- `lineSpacing` — gap between lines (defaults to `spacing` if not set)

## Debug Mode

Enable visual debugging to inspect layout frames:

```swift
#if DEBUG
Loom.debugOptions = [.showFrameBorders, .showKeys, .logLayoutTime]
#endif
```

| Option | Effect |
|--------|--------|
| `.showFrameBorders` | Colored borders on every keyed view |
| `.showKeys` | Key name label at top-left of each view |
| `.logLayoutTime` | Prints calculation time to console |

Debug overlays are applied through ``LoomBindings/apply(_:)`` and only compile
in DEBUG builds (zero overhead in release).

## Async API

For Swift Concurrency, use the async variants:

```swift
// Single calculation
let result = await layout.calculateAsync()

// Cache with async resolve
let result = await cache.resolveAsync(id: post.id, width: 375) {
    FeedCell.buildLayout(for: post, width: 375)
}

// Batch parallel pre-calculation
await cache.precalculateAsync(ids: postIDs, width: 375) { id in
    FeedCell.buildLayout(for: posts[id], width: 375)
}
```

The sync ``LoomLayout/calculate(engine:)`` is still preferred when you're already
on a background thread — `calculateAsync` is a convenience for calling from the main thread.

## Custom Layout Engine

Loom uses ``YogaEngine`` by default, but you can provide your own ``LayoutEngine``:

```swift
class MyEngine: LayoutEngine {
    func calculate(node: LoomNode, width: CGFloat) -> LayoutResult {
        // custom implementation
    }
}

let result = layout.calculate(engine: MyEngine())
```

## Non-List Views

Loom isn't just for cells. Use the `loomLayout` UIView extension for any view:

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    let result = loomLayout {
        HStack(spacing: 12, align: .center) {
            Fixed(width: 60, height: 60).key(.avatar)
            VStack(spacing: 4) {
                Text(nameAttr).key(.name)
                Text(bioAttr).key(.bio)
            }.flex(grow: 1)
        }.padding(16)
    }
    bindings.apply(result)
}
```

This automatically uses `bounds.width` and calls `calculate()` synchronously.
For simple views, the calculation is sub-millisecond — no need for async.
