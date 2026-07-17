# Loom

Background-thread layout pre-calculation for iOS, powered by [Yoga](https://github.com/nicklockwood/yoga).

Describe layouts with a declarative DSL, calculate frames on a background thread, cache results, and apply them in `layoutSubviews` — eliminating layout computation from the main thread.

Sister library: [LoomText](https://github.com/itsyelo/LoomText) — a CoreText renderer that draws from the same precomputed layout Loom measures with. Typeset once; measurement and rendering share one source of truth.

## Features

- **Background calculation** — Yoga runs on any thread, zero main-thread layout cost
- **Result Builder DSL** — VStack, HStack, ZStack, Text, Fixed, Spacer, Measured
- **Core Text measurement** — Thread-safe text sizing with CTFramesetter caching
- **Layout caching** — `LayoutCache` with prefetch integration
- **LoomBindings** — Declarative view-key binding, one-line frame application
- **Debug mode** — Frame borders, key labels, calculation timing
- **async/await** — `calculateAsync()`, `resolveAsync()`, `precalculateAsync()`

## Example App

`Example/LoomExample` is a tabbed demo covering the main integration patterns:

| Tab | Demonstrates |
|-----|--------------|
| **Feed** | The recommended [pipeline architecture](Sources/Loom/Loom.docc/Articles/FeedListPipeline.md) — 1,000 posts, view models own both collapsed/expanded `LayoutResult`s, chunked background publishing, zero-calculation expand toggle, RTL rebuild |
| **Lazy Cache** | `LayoutCache` + prefetch for content you can't pre-compute |
| **Showcase** | Layout capability gallery — ZStack alignments, wrap, absolute positioning, padded leaves, aspectRatio, justify — the whole screen is one `LoomLayout` |
| **Custom View** | `UIView.loomLayout` outside lists + runtime debug overlay toggles |
| **Chat** | A full conversational UI on the pipeline paradigm — multiple bubble cell types (text/image/system), an auto-growing input bar with keyboard avoidance, a streaming bot reply as a single-row mutation (background recompute, atomic main-thread publish), and history-prepend paging with exact `contentOffset` compensation from known VM heights |

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/itsyelo/Loom.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → paste the URL.

## Quick Start

```swift
import Loom

// 1. Define keys
enum K: String, LoomKey {
    case avatar, name, body
    var loomKeyValue: String { rawValue }
}

// 2. Describe layout
let layout = LoomLayout(width: 375) {
    HStack(spacing: 8, align: .center) {
        Fixed(width: 40, height: 40).key(K.avatar)
        VStack(spacing: 4) {
            Text(nameAttr).key(K.name)
            Text(bodyAttr).key(K.body)
        }.flex(grow: 1)
    }.padding(12)
}

// 3. Calculate (safe on any thread)
let result = layout.calculate()
print(result.height) // cell height

// 4. Apply in layoutSubviews
avatarView.frame = result.frame(for: K.avatar) ?? .zero
nameLabel.frame = result.frame(for: K.name) ?? .zero
bodyLabel.frame = result.frame(for: K.body) ?? .zero
```

## Node Types

### Containers

| Factory | Description |
|---------|-------------|
| `VStack(spacing:justify:align:)` | Vertical stack (top → bottom) |
| `HStack(spacing:lineSpacing:justify:align:wrap:)` | Horizontal stack (left → right, optional wrap) |
| `ZStack(alignment:)` | Overlay stack (9 alignment positions) |

### Leaf Nodes

| Factory | Description |
|---------|-------------|
| `Text(NSAttributedString)` | Auto-measured via Core Text |
| `Fixed(width:height:)` | Explicit dimensions |
| `Spacer(CGFloat)` | Vertical gap |
| `Measured { maxW, maxH -> CGSize }` | Custom sizing closure |

### Modifiers

```swift
.key(.name)                        // assign key for frame retrieval
.flex(grow: 1, shrink: 1)          // flex distribution
.padding(12)                       // inner spacing
.margin(.horizontal, 16)           // outer spacing
.size(width: 100, height: 50)      // explicit size
.maxSize(height: 60)               // constraints
.alignSelf(.center)                // cross-axis override
```

## UIKit Integration

### Cell Height + Prefetch

```swift
class ViewController: UITableViewController, UITableViewDataSourcePrefetching {
    private let cache = LayoutCache(countLimit: 500)

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        cache.resolve(id: posts[indexPath.row].id, width: tableView.bounds.width) {
            FeedCell.buildLayout(for: posts[indexPath.row], width: tableView.bounds.width)
        }.height
    }

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let width = tableView.bounds.width
        DispatchQueue.global(qos: .userInitiated).async { [cache] in
            for ip in indexPaths {
                _ = cache.resolve(id: self.posts[ip.row].id, width: width) {
                    FeedCell.buildLayout(for: self.posts[ip.row], width: width)
                }
            }
        }
    }
}
```

### LoomBindings

```swift
class FeedCell: UITableViewCell {
    var layoutResult: LayoutResult?

    private lazy var bindings = LoomBindings {
        LoomBind(K.avatar, to: avatarView)
        LoomBind(K.name, to: nameLabel)
        LoomBind(K.body, to: bodyLabel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bindings.apply(layoutResult)
    }
}
```

## Non-List Views

For regular views (not cells), use the `loomLayout` extension — no need to specify width:

```swift
class ProfileHeaderView: UIView {
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let bioLabel = UILabel()

    private lazy var bindings = LoomBindings {
        LoomBind(K.avatar, to: avatarView)
        LoomBind(K.name, to: nameLabel)
        LoomBind(K.bio, to: bioLabel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let result = loomLayout {
            HStack(spacing: 12, align: .center) {
                Fixed(width: 60, height: 60).key(K.avatar)
                VStack(spacing: 4) {
                    Text(nameAttr).key(K.name)
                    Text(bioAttr).key(K.bio)
                }.flex(grow: 1)
            }.padding(16)
        }
        bindings.apply(result)
    }
}
```

## Advanced

### ZStack Overlays

```swift
ZStack(alignment: .bottomRight) {
    Fixed(width: 40, height: 40).key(.avatar)
    Fixed(width: 12, height: 12).key(.badge)  // online status dot
}
```

### Wrap Layout

```swift
HStack(spacing: 8, lineSpacing: 12, wrap: .wrap) {
    for tag in tags {
        Text(tag.attr).key("tag-\(tag.id)")
    }
}
```

### Debug Mode

```swift
#if DEBUG
Loom.debugOptions = [.showFrameBorders, .showKeys, .logLayoutTime]
#endif
```

### Async API

```swift
let result = await layout.calculateAsync()
let result = await cache.resolveAsync(id: post.id, width: 375) { ... }
await cache.precalculateAsync(ids: postIDs, width: 375) { id in ... }
```

## Documentation

Loom includes full [DocC](https://developer.apple.com/documentation/docc) documentation with API reference and usage guides.

### View in Xcode

Build the documentation target in Xcode:

**Product → Build Documentation** (or `⌃⇧⌘D`)

Then browse via Xcode's documentation window, or Option+Click any Loom symbol.

### Generate from Command Line

```bash
# Build the DocC archive
xcodebuild docbuild \
  -scheme Loom \
  -derivedDataPath .build/docc \
  -destination 'generic/platform=iOS'

# Open in Xcode
open .build/docc/Build/Products/Debug-iphoneos/Loom.doccarchive

# Or export as static HTML (for GitHub Pages)
$(xcrun --find docc) process-archive transform-for-static-hosting \
  .build/docc/Build/Products/Debug-iphoneos/Loom.doccarchive \
  --output-path docs \
  --hosting-base-path Loom
```

## License

MIT
