import CoreGraphics
import Foundation
import yoga

/// The default layout engine, powered by Facebook's Yoga (CSS Flexbox).
///
/// Use ``shared`` for the singleton instance, or create your own if you need
/// a separate ``YogaConfig``. Conforms to ``LayoutEngine``.
public final class YogaEngine: LayoutEngine, @unchecked Sendable {
    /// Shared singleton instance with auto-detected screen scale.
    public static let shared = YogaEngine()

    public func calculate(node: LoomNode, width: CGFloat) -> LayoutResult {
        calculate(node: node, width: width, direction: .ltr)
    }

    public func calculate(
        node: LoomNode,
        width: CGFloat,
        direction: LoomDirection
    ) -> LayoutResult {
        let startTime: CFAbsoluteTime?
        #if DEBUG
        startTime = Loom.debugOptions.contains(.logLayoutTime) ? CFAbsoluteTimeGetCurrent() : nil
        #else
        startTime = nil
        #endif

        let config = YogaConfig.shared
        config.ensureScaleConfigured()
        let root = buildYogaTree(from: node, config: config)

        root.setWidth(Float(width))
        // Pass the resolved root direction to Yoga. Per-node overrides
        // (set via `applyStyle` calling `setDirection`) take precedence
        // for their subtrees; nodes without an explicit direction
        // inherit from this root value.
        root.calculateLayout(
            width: Float(width),
            height: .nan,
            direction: direction.yogaValue
        )

        var frames: [String: CGRect] = [:]
        extractFrames(from: root, loomNode: node, into: &frames)

        let size = root.layoutSize

        #if DEBUG
        if let startTime {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print(String(format: "[Loom] Layout calculated in %.2fms (%d keys, width: %.0f)",
                         elapsed, frames.count, width))
        }
        #endif

        return LayoutResult(size: size, frames: frames)
    }

    // MARK: - Build Yoga Tree

    private func buildYogaTree(from node: LoomNode, config: YogaConfig) -> YogaNode {
        // Leaf nodes with padding: auto-wrap in a container so that the
        // key's frame corresponds to the content area, not the padded area.
        if node.isLeaf && node.style.padding != .zero {
            return buildWrappedLeaf(from: node, config: config)
        }

        let yogaNode = YogaNode(config: config)
        applyStyle(node.style, to: yogaNode)

        switch node.kind {
        case .vstack(let children):
            yogaNode.setFlexDirection(.column)
            for child in children {
                let childYoga = buildYogaTree(from: child, config: config)
                yogaNode.addChild(childYoga)
            }

        case .hstack(let children):
            yogaNode.setFlexDirection(.row)
            for child in children {
                let childYoga = buildYogaTree(from: child, config: config)
                yogaNode.addChild(childYoga)
            }

        case .zstack(let children, _):
            // First child stays relative to size the container.
            // Remaining children are absolute, positioned during frame extraction.
            for (i, child) in children.enumerated() {
                var absChild = child
                if i > 0 && absChild.style.positionType == .relative {
                    absChild.style.positionType = .absolute
                }
                let childYoga = buildYogaTree(from: absChild, config: config)
                yogaNode.addChild(childYoga)
            }

        case .text(let attributedString, let maxLines, let measurer):
            let maxLinesArg = maxLines ?? 0
            yogaNode.setMeasureFunc { width, widthMode, height, heightMode in
                let maxW = widthMode == .undefined
                    ? CGFloat.greatestFiniteMagnitude : CGFloat(width)
                let maxH = heightMode == .undefined
                    ? CGFloat.greatestFiniteMagnitude : CGFloat(height)
                return measurer.measure(
                    attributedString,
                    maxWidth: maxW,
                    maxHeight: maxH,
                    maxLines: maxLinesArg
                )
            }

        case .fixed:
            break

        case .spacer:
            break

        case .measured(let closure):
            yogaNode.setMeasureFunc { width, widthMode, height, heightMode in
                let maxW = widthMode == .undefined
                    ? CGFloat.greatestFiniteMagnitude : CGFloat(width)
                let maxH = heightMode == .undefined
                    ? CGFloat.greatestFiniteMagnitude : CGFloat(height)
                return closure(maxW, maxH)
            }
        }

        return yogaNode
    }

    /// Wrap a leaf node that has padding in a container.
    /// The container gets the padding + non-flex style; the inner leaf keeps
    /// its kind, key, and measure func but no padding.
    private func buildWrappedLeaf(from node: LoomNode, config: YogaConfig) -> YogaNode {
        // Container: takes padding, margin, flex properties from original
        var containerStyle = node.style
        // Inner leaf: strip padding (container handles it)
        var innerStyle = node.style
        innerStyle.padding = .zero
        // Move margin to container only
        innerStyle.margin = .zero
        // Move flex to container only
        innerStyle.flexGrow = 0
        innerStyle.flexShrink = 1
        innerStyle.flexBasis = nil
        innerStyle.alignSelf = nil

        // Container doesn't need the dimensions that belong to the leaf
        containerStyle.width = nil
        containerStyle.height = nil
        containerStyle.minWidth = nil
        containerStyle.maxWidth = nil
        containerStyle.minHeight = nil
        containerStyle.maxHeight = nil
        containerStyle.aspectRatio = nil

        var innerNode = node
        innerNode.style = innerStyle

        let containerYoga = YogaNode(config: config)
        containerYoga.setFlexDirection(.column)
        applyStyle(containerStyle, to: containerYoga)

        let innerYoga = buildYogaTree(from: innerNode, config: config)
        containerYoga.addChild(innerYoga)

        return containerYoga
    }

    private func alignedOrigin(
        childSize: CGSize, containerSize: CGSize, alignment: LoomZAlignment
    ) -> CGPoint {
        // `alignment` here is always absolute — direction-aware variants
        // are resolved to absolute via `resolveAlignment(_:direction:)`
        // before reaching this function.
        let x: CGFloat
        let y: CGFloat

        switch alignment {
        case .topLeft, .centerLeft, .bottomLeft:
            x = 0
        case .topCenter, .center, .bottomCenter:
            x = (containerSize.width - childSize.width) / 2
        case .topRight, .centerRight, .bottomRight:
            x = containerSize.width - childSize.width
        case .topLeading, .topTrailing,
             .centerLeading, .centerTrailing,
             .bottomLeading, .bottomTrailing:
            // Caller must pre-resolve via resolveAlignment(_:direction:).
            assertionFailure("Direction-aware alignment reached alignedOrigin")
            x = 0
        }

        switch alignment {
        case .topLeft, .topCenter, .topRight,
             .topLeading, .topTrailing:
            y = 0
        case .centerLeft, .center, .centerRight,
             .centerLeading, .centerTrailing:
            y = (containerSize.height - childSize.height) / 2
        case .bottomLeft, .bottomCenter, .bottomRight,
             .bottomLeading, .bottomTrailing:
            y = containerSize.height - childSize.height
        }

        return CGPoint(x: x, y: y)
    }

    /// Resolve a (possibly direction-aware) ZStack alignment to its
    /// absolute equivalent given the container's resolved direction.
    /// Pure absolute alignments are returned as-is.
    private func resolveAlignment(
        _ alignment: LoomZAlignment,
        direction: YGDirection
    ) -> LoomZAlignment {
        let isRTL = (direction == .RTL)
        switch alignment {
        case .topLeading:    return isRTL ? .topRight    : .topLeft
        case .topTrailing:   return isRTL ? .topLeft     : .topRight
        case .centerLeading: return isRTL ? .centerRight : .centerLeft
        case .centerTrailing:return isRTL ? .centerLeft  : .centerRight
        case .bottomLeading: return isRTL ? .bottomRight : .bottomLeft
        case .bottomTrailing:return isRTL ? .bottomLeft  : .bottomRight
        default:             return alignment
        }
    }

    // MARK: - Apply Style

    private func applyStyle(_ style: LoomStyle, to node: YogaNode) {
        // Direction override for this subtree. nil means "inherit from
        // parent" (Yoga's default), so only call the setter when an
        // explicit override was set via `.direction(_:)`.
        if let direction = style.direction {
            node.setDirection(direction.yogaValue)
        }

        // Container
        node.setJustifyContent(style.justifyContent.yogaValue)
        node.setAlignItems(style.alignItems.yogaValue)
        node.setAlignContent(style.alignContent.yogaValue)
        node.setFlexWrap(style.wrap.yogaValue)

        if style.gap > 0 {
            if style.lineSpacing != nil {
                // When lineSpacing is set separately, gap only applies to item spacing
                node.setGap(.column, Float(style.gap))
            } else {
                node.setGap(.all, Float(style.gap))
            }
        }
        if let lineSpacing = style.lineSpacing {
            node.setGap(.row, Float(lineSpacing))
        }

        // Flex item
        node.setFlexGrow(Float(style.flexGrow))
        node.setFlexShrink(Float(style.flexShrink))

        if let basis = style.flexBasis {
            node.setFlexBasis(Float(basis))
        }

        if let alignSelf = style.alignSelf {
            node.setAlignSelf(alignSelf.yogaValue)
        }

        // Dimensions
        if let w = style.width { node.setWidth(Float(w)) }
        if let h = style.height { node.setHeight(Float(h)) }
        if let v = style.minWidth { node.setMinWidth(Float(v)) }
        if let v = style.maxWidth { node.setMaxWidth(Float(v)) }
        if let v = style.minHeight { node.setMinHeight(Float(v)) }
        if let v = style.maxHeight { node.setMaxHeight(Float(v)) }
        if let r = style.aspectRatio { node.setAspectRatio(Float(r)) }

        // Padding (.left/.right are absolute; .leading/.trailing map
        // to YGEdge.start/.end, which Yoga resolves based on the
        // node's resolved direction).
        let p = style.padding
        if p.top != 0 { node.setPadding(.top, Float(p.top)) }
        if p.left != 0 { node.setPadding(.left, Float(p.left)) }
        if p.bottom != 0 { node.setPadding(.bottom, Float(p.bottom)) }
        if p.right != 0 { node.setPadding(.right, Float(p.right)) }
        if p.leading != 0 { node.setPadding(.start, Float(p.leading)) }
        if p.trailing != 0 { node.setPadding(.end, Float(p.trailing)) }

        // Margin
        let m = style.margin
        if m.top != 0 { node.setMargin(.top, Float(m.top)) }
        if m.left != 0 { node.setMargin(.left, Float(m.left)) }
        if m.bottom != 0 { node.setMargin(.bottom, Float(m.bottom)) }
        if m.right != 0 { node.setMargin(.right, Float(m.right)) }
        if m.leading != 0 { node.setMargin(.start, Float(m.leading)) }
        if m.trailing != 0 { node.setMargin(.end, Float(m.trailing)) }

        // Position — nil means "edge unconstrained"; an explicit value
        // (including 0) pins the edge. See ``LoomPosition``.
        if style.positionType == .absolute {
            node.setPositionType(.absolute)
            let pos = style.position
            if let v = pos.top { node.setPosition(.top, Float(v)) }
            if let v = pos.left { node.setPosition(.left, Float(v)) }
            if let v = pos.bottom { node.setPosition(.bottom, Float(v)) }
            if let v = pos.right { node.setPosition(.right, Float(v)) }
            if let v = pos.leading { node.setPosition(.start, Float(v)) }
            if let v = pos.trailing { node.setPosition(.end, Float(v)) }
        }
    }

    // MARK: - Extract Frames

    private func extractFrames(
        from root: YogaNode,
        loomNode: LoomNode,
        into frames: inout [String: CGRect]
    ) {
        let absX = root.layoutLeft
        let absY = root.layoutTop
        recordFrame(
            for: loomNode,
            yogaRef: root.ref,
            absX: absX,
            absY: absY,
            width: root.layoutWidth,
            height: root.layoutHeight,
            into: &frames
        )
        extractChildFrames(
            containerRef: root.ref,
            loomNode: loomNode,
            absX: absX,
            absY: absY,
            into: &frames
        )
    }

    /// Record the frame for a keyed node. For a leaf with padding
    /// (auto-wrapped in a container by `buildYogaTree`), the recorded
    /// frame is the inner content area — the documented key semantics.
    private func recordFrame(
        for loomNode: LoomNode,
        yogaRef: YGNodeRef,
        absX: CGFloat,
        absY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        into frames: inout [String: CGRect]
    ) {
        guard let key = loomNode.key else { return }

        if loomNode.isLeaf && loomNode.style.padding != .zero,
           let innerYoga = YGNodeGetChild(yogaRef, 0) {
            frames[key] = CGRect(
                x: absX + CGFloat(YGNodeLayoutGetLeft(innerYoga)),
                y: absY + CGFloat(YGNodeLayoutGetTop(innerYoga)),
                width: CGFloat(YGNodeLayoutGetWidth(innerYoga)),
                height: CGFloat(YGNodeLayoutGetHeight(innerYoga))
            )
        } else {
            frames[key] = CGRect(x: absX, y: absY, width: width, height: height)
        }
    }

    /// Recurse into a container's children, recording keyed frames in
    /// absolute (root) coordinates. `absX`/`absY` is the container's
    /// absolute origin; leaf nodes return immediately.
    private func extractChildFrames(
        containerRef: YGNodeRef,
        loomNode: LoomNode,
        absX: CGFloat,
        absY: CGFloat,
        into frames: inout [String: CGRect]
    ) {
        let children: [LoomNode]
        let zAlignment: LoomZAlignment?
        switch loomNode.kind {
        case .vstack(let c), .hstack(let c):
            children = c
            zAlignment = nil
        case .zstack(let c, let alignment):
            children = c
            zAlignment = alignment
        default:
            return
        }

        let containerSize = CGSize(
            width: CGFloat(YGNodeLayoutGetWidth(containerRef)),
            height: CGFloat(YGNodeLayoutGetHeight(containerRef))
        )

        for (index, childLoom) in children.enumerated() {
            guard let childYoga = YGNodeGetChild(containerRef, index) else { continue }
            var childFrame = CGRect(
                x: CGFloat(YGNodeLayoutGetLeft(childYoga)),
                y: CGFloat(YGNodeLayoutGetTop(childYoga)),
                width: CGFloat(YGNodeLayoutGetWidth(childYoga)),
                height: CGFloat(YGNodeLayoutGetHeight(childYoga))
            )

            // ZStack alignment: reposition non-first children within the
            // container (the first child stays relative and sizes it).
            if let zAlignment, index > 0, childLoom.style.positionType == .relative {
                let resolvedDir = YGNodeLayoutGetDirection(containerRef)
                let resolvedAlignment = resolveAlignment(zAlignment, direction: resolvedDir)
                childFrame.origin = alignedOrigin(
                    childSize: childFrame.size,
                    containerSize: containerSize,
                    alignment: resolvedAlignment
                )
            }

            let childAbsX = absX + childFrame.origin.x
            let childAbsY = absY + childFrame.origin.y

            recordFrame(
                for: childLoom,
                yogaRef: childYoga,
                absX: childAbsX,
                absY: childAbsY,
                width: childFrame.width,
                height: childFrame.height,
                into: &frames
            )
            extractChildFrames(
                containerRef: childYoga,
                loomNode: childLoom,
                absX: childAbsX,
                absY: childAbsY,
                into: &frames
            )
        }
    }
}
