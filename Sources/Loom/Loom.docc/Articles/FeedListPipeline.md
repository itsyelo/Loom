# Feed List Pipeline

The recommended architecture for large, complex lists: compute layout as part
of the data pipeline so a cell can never be displayed without its frames.

## Overview

The prefetch + ``LayoutCache`` pattern in <doc:UIKitIntegration> computes
layouts *lazily* and hopes prefetching stays ahead of the scroll. That works
for moderate lists, but on low-end devices a single cache miss in
`heightForRowAt` means a synchronous layout calculation on the main thread —
exactly the frame drop you are trying to avoid.

For high-volume feeds, invert the relationship: **treat the
``LayoutResult`` as part of the row's data, not as a cache entry**. Data
that doesn't have a computed layout yet simply never reaches the data
source, which makes a miss structurally impossible:

```
Background: fetch → build NSAttributedStrings → calculate() → view models
                                                                  │
Main:       dataSource.append(viewModels) + insertRows  ◄─────────┘
            (only "complete" items are ever published)
```

## The View Model

Hold the computed result *and* the attributed strings on the view model.
Both matter:

- The ``LayoutResult`` is a dozen `CGRect`s plus a size — a few hundred
  bytes. Ten thousand rows cost a few megabytes; strong ownership is fine
  and, unlike ``LayoutCache``, nothing is ever evicted behind your back.
- The `NSAttributedString` must be built **once** and reused. The
  framesetter cache is keyed by string equality — rebuilding an equal
  string on every `cellForRowAt` pays the construction plus comparison
  cost on the main thread for nothing.

```swift
struct FeedItemVM {
    let post: Post
    let nameAttr: NSAttributedString
    let bodyAttr: NSAttributedString
    let layout: LayoutResult
}
```

The table view callbacks become trivial and allocation-free:

```swift
override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    items[indexPath.row].layout.height   // never a miss, never a calculation
}
```

## The Pipeline

Assemble view models entirely off-main, then publish:

```swift
func loadPage() {
    Task.detached(priority: .userInitiated) { [width = tableView.bounds.width] in
        let posts = try await api.fetchPage()
        let vms = posts.map { post in
            let nameAttr = Self.makeNameAttr(post)
            let bodyAttr = Self.makeBodyAttr(post)
            let layout = FeedCell.buildLayout(
                nameAttr: nameAttr, bodyAttr: bodyAttr, width: width
            ).calculate()
            return FeedItemVM(post: post, nameAttr: nameAttr,
                              bodyAttr: bodyAttr, layout: layout)
        }
        await MainActor.run { self.publish(vms) }
    }
}
```

### Publish in chunks

A 200-item page of text-heavy cells can take 100–300 ms to measure on a
low-end device. Don't hold the first screen hostage: compute in display
order and publish every ~20 items so the first batch renders while the
rest is still measuring.

### Decide expandability with rich measurement

"Does this post need an expand affordance at all?" is a one-call
question with ``TextMeasuring/measureDetails(_:maxWidth:maxHeight:maxLines:)``
— no second layout required, and posts that fit the collapsed cap can
skip their expanded layout entirely:

```swift
let m = Loom.defaultTextMeasurer.measureDetails(
    bodyAttr, maxWidth: bodyWidth, maxHeight: .greatestFiniteMagnitude, maxLines: 2
)
let isExpandable = m.details?.isTruncated ?? true
let expandedLayout = isExpandable ? buildLayout(expanded: true).calculate()
                                  : collapsedLayout
```

``TextMeasurement`` also carries the line count, the visible character
range (the natural cut point for a custom "see more" treatment), the
last line's width, and baselines.

### Pre-compute toggle states

If a cell has a collapsed/expanded (or similar two-state) layout, compute
**both** results during the pipeline and store both on the view model.
Toggling then costs zero calculation and animates cleanly:

```swift
struct FeedItemVM {
    let collapsedLayout: LayoutResult
    let expandedLayout: LayoutResult
    var isExpanded = false
    var layout: LayoutResult { isExpanded ? expandedLayout : collapsedLayout }
}
```

## Invalidation Events

The pipeline guarantees results are never *missing*; these events make
stored results *stale* and require recomputation:

| Event | Handling |
| --- | --- |
| Width change (rotation, iPad multitasking) | Recompute all off-main at the new width, then reload. Portrait-locked iPhone apps can mostly ignore this. |
| Dynamic Type change | Observe `UIContentSizeCategory.didChangeNotification`; rebuild attributed strings and recompute all. |
| Language / RTL change | Same as above — every frame mirrors. |
| Single-item mutation (edit, count change) | Recompute that item off-main, then replace the view model *and* reload the row in the same main-queue hop. Never publish new data with an old layout. |
| Collapse/expand toggle | No recomputation needed if both states were pre-computed. |

The first three are rare, whole-world events where a brief reload pass is
acceptable. The one to be disciplined about is item mutation: the new
layout and the new data must always be published atomically.

## Startup Configuration

Your first `calculate()` happens on a background thread, so configure Loom
on main at launch rather than relying on the off-main fallbacks:

```swift
// In application(_:didFinishLaunchingWithOptions:)
Loom.configure(screenScale: UIScreen.main.scale)
Loom.defaultTextMeasurer = TextKitMeasurer.shared  // native UILabel agreement
let direction = Loom.systemDirection   // resolved on main, honors app overrides
```

``TextKitMeasurer`` fits the pipeline especially well: each string is
measured only once or twice, so the Core Text path's framesetter cache
buys little, while UILabel-native sizing removes the locked-line-height
discipline entirely (see <doc:MultilineUILabelTips>).

Pass `direction` explicitly to `LoomLayout(width:direction:)` in the
pipeline if your app can run RTL — see <doc:RTLSupport> for why off-main
resolution can diverge.

## When to Use LayoutCache Instead

``LayoutCache`` remains the right tool when layouts genuinely can't be
computed ahead of time — search-as-you-type results, unbounded browsing
where holding every result is wasteful, or mixed feeds where only some
rows use Loom. For a feed you fully control, prefer this pipeline.
