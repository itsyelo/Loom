# Getting Started

Add Loom to your project and calculate your first layout.

## Installation

Add Loom to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/itsyelo/Loom.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → paste the URL.

## Your First Layout

### 1. Define Keys

Create an enum to identify the views you want frames for:

```swift
import Loom

enum MyKey: String, LoomKey {
    case title, subtitle
    var loomKeyValue: String { rawValue }
}
```

### 2. Describe the Layout

```swift
let layout = LoomLayout(width: view.bounds.width) {
    VStack(spacing: 8) {
        Text(titleAttr).key(MyKey.title)
        Text(subtitleAttr).key(MyKey.subtitle)
    }.padding(16)
}
```

### 3. Calculate

```swift
let result = layout.calculate()
// result.height → total height
// result.frame(for: MyKey.title) → CGRect for title
```

`calculate()` is synchronous and safe to call from **any thread**.

### 4. Apply Frames

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    titleLabel.frame = result.frame(for: MyKey.title) ?? .zero
    subtitleLabel.frame = result.frame(for: MyKey.subtitle) ?? .zero
}
```

## One Decision Before You Ship: Text Measurement

Loom measures text and UIKit renders it — two engines that must agree,
or labels truncate a few points early. Make the choice once, up front:

```swift
// application(_:didFinishLaunchingWithOptions:) — recommended for UILabel
Loom.defaultTextMeasurer = TextKitMeasurer.shared
```

| Option | Agreement with UILabel | Trade-off |
|---|---|---|
| ``TextKitMeasurer`` (set once at launch) | Native, for any attributed string | No measurement cache |
| Default Core Text ``TextMeasurer`` | Requires locked line heights on every multi-line string | Fastest for repeated re-measurement |

Details, symptoms, and the locked-line-height convention:
<doc:MultilineUILabelTips>.

## What's Next

- <doc:CoreConcepts> — Node types, styles, and the calculation pipeline
- <doc:UIKitIntegration> — Prefetch, cell height caching, and `LoomBindings`
- <doc:FeedListPipeline> — The zero-miss architecture for large feeds
