# UIKit Integration

Integrate Loom with UITableView and UICollectionView for pre-calculated cell layouts.

## Overview

> Tip: For large feeds where smooth scrolling on low-end devices is the
> goal, prefer the pipeline architecture in <doc:FeedListPipeline> — it
> makes cache misses structurally impossible. The lazy prefetch pattern
> below fits moderate lists and mixed content.

The typical integration pattern uses three UIKit hooks:

1. **`prefetchRowsAt`** — trigger background pre-calculation
2. **`heightForRowAt`** — return cached height
3. **`cellForRowAt`** — pass cached ``LayoutResult`` to cell
4. **`layoutSubviews`** — apply frames from result

## Layout Cache

``LayoutCache`` stores computed ``LayoutResult`` values, keyed by model ID + width:

```swift
class ViewController: UITableViewController {
    private let layoutCache = LayoutCache(countLimit: 500)
}
```

### Resolve Pattern

Use ``LayoutCache/resolve(id:width:builder:)`` to get cached results or calculate on miss:

```swift
let result = layoutCache.resolve(id: post.id, width: tableView.bounds.width) {
    FeedCell.buildLayout(for: post, width: tableView.bounds.width)
}
```

### Cell Height

```swift
override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    let post = posts[indexPath.row]
    return layoutCache.resolve(id: post.id, width: tableView.bounds.width) {
        FeedCell.buildLayout(for: post, width: tableView.bounds.width)
    }.height
}
```

## Prefetching

Use `UITableViewDataSourcePrefetching` to pre-calculate layouts on a background thread
before cells are needed:

```swift
func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
    let width = tableView.bounds.width
    let posts = indexPaths.map { self.posts[$0.row] }

    DispatchQueue.global(qos: .userInitiated).async { [layoutCache] in
        for post in posts {
            _ = layoutCache.resolve(id: post.id, width: width) {
                FeedCell.buildLayout(for: post, width: width)
            }
        }
    }
}
```

## LoomBindings

``LoomBindings`` eliminates manual frame assignment boilerplate:

```swift
class FeedCell: UITableViewCell {
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    var layoutResult: LayoutResult?

    private lazy var bindings = LoomBindings {
        LoomBind(FeedKey.avatar, to: avatarView)
        LoomBind(FeedKey.name, to: nameLabel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bindings.apply(layoutResult)
    }
}
```

### Custom Subviews

For custom views with their own subviews, use ``LoomBindings/apply(_:relativeTo:)``
to get frames in local coordinates:

```swift
// Card view is a custom UIView with imageView, titleLabel, etc.
private lazy var cardBindings = LoomBindings {
    LoomBind(FeedKey.cardImage, to: cardView.imageView)
    LoomBind(FeedKey.cardTitle, to: cardView.titleLabel)
}

override func layoutSubviews() {
    super.layoutSubviews()
    bindings.apply(layoutResult)

    if let cardFrame = layoutResult?.frame(for: FeedKey.card) {
        cardView.frame = cardFrame
        cardBindings.apply(layoutResult, relativeTo: FeedKey.card)
    }
}
```

## Cell Layout Builder

Keep layout descriptions in the cell class (not the model):

```swift
class FeedCell: UITableViewCell {
    static func buildLayout(for post: Post, width: CGFloat) -> LoomLayout {
        let nameAttr = NSAttributedString(string: post.name, attributes: [...])
        let bodyAttr = NSAttributedString(string: post.body, attributes: [...])

        return LoomLayout(width: width) {
            VStack(spacing: 0) {
                HStack(spacing: 8, align: .center) {
                    Fixed(width: 40, height: 40).key(FeedKey.avatar)
                    Text(nameAttr).key(FeedKey.name).flex(grow: 1)
                }.padding(.horizontal, 12).padding(.vertical, 10)

                Text(bodyAttr).key(FeedKey.body)
                    .margin(.horizontal, 12)
            }
        }
    }
}
```

This keeps the model pure data and allows the same model to have different
layouts in different screens.

## Dynamic Updates

To update a cell's layout with animation (e.g. expand/collapse):

```swift
// 1. Invalidate and recalculate
let newResult = layoutCache.update(id: post.id, width: width) {
    FeedCell.buildLayout(for: post, width: width, expanded: true)
}

// 2. Update cell and animate height change
cell.layoutResult = newResult
cell.setNeedsLayout()
tableView.beginUpdates()
tableView.endUpdates()
```
