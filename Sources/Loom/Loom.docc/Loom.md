# ``Loom``

Background-thread layout pre-calculation for iOS, powered by Yoga.

## Overview

Loom lets you describe layouts with a declarative DSL, calculate frames on a background thread using Facebook's Yoga flexbox engine, and apply the cached results in `layoutSubviews` — eliminating layout computation from the main thread.

```swift
// 1. Describe
let layout = LoomLayout(width: 375) {
    HStack(spacing: 8) {
        Fixed(width: 40, height: 40).key(.avatar)
        Text(nameAttr).key(.name).flex(grow: 1)
    }
}

// 2. Calculate (any thread)
let result = layout.calculate()

// 3. Apply (main thread)
avatarView.frame = result.frame(for: .avatar) ?? .zero
nameLabel.frame = result.frame(for: .name) ?? .zero
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:CoreConcepts>

### Guides

- <doc:UIKitIntegration>
- <doc:FeedListPipeline>
- <doc:MultilineUILabelTips>
- <doc:RTLSupport>
- <doc:AdvancedUsage>

### Building Layouts

- ``LoomLayout``
- ``LoomNode``
- ``LoomBuilder``
- ``VStack(spacing:justify:align:children:)``
- ``HStack(spacing:lineSpacing:justify:align:wrap:children:)``
- ``ZStack(alignment:children:)``
- ``Text(_:maxLines:measurer:)``
- ``TextMeasuring``
- ``TextMeasurement``
- ``Fixed(width:height:)``
- ``Spacer(_:)``
- ``Measured(_:)``

### Layout Results

- ``LayoutResult``
- ``LoomKey``

### Caching & Performance

- ``LayoutCache``
- ``TextMeasurer``
- ``TextKitMeasurer``

### UIKit Integration

- ``LoomBindings``
- ``LoomBind``
- ``LoomLayoutable``
- ``UIKit/UIView/loomLayout(content:)``

### Configuration

- ``Loom``
- ``LoomDebugOptions``

### Style & Enums

- ``LoomStyle``
- ``LoomJustify``
- ``LoomAlign``
- ``LoomWrap``
- ``LoomZAlignment``
- ``LoomPositionType``
- ``LoomEdge``
- ``LoomEdgeInsets``

### Engine

- ``LayoutEngine``
- ``YogaEngine``
