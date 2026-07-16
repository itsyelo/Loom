import Foundation
import CoreGraphics

/// A virtual layout node that describes a piece of UI without touching UIKit.
///
/// `LoomNode` is a value type — create nodes using factory functions like
/// ``VStack(spacing:justify:align:children:)``, ``Text(_:)``, ``Fixed(width:height:)``,
/// then chain modifiers to customize style:
///
/// ```swift
/// HStack(spacing: 8) {
///     Fixed(width: 40, height: 40).key(.avatar)
///     Text(nameAttr).key(.name).flex(grow: 1)
/// }.padding(12)
/// ```
///
/// Nodes are either **containers** (VStack, HStack, ZStack) that hold children,
/// or **leaf nodes** (Text, Fixed, Spacer, Measured) that have intrinsic size.
public struct LoomNode: Sendable {
    /// The type of layout node.
    public enum Kind: @unchecked Sendable {
        /// Vertical stack — children laid out top to bottom.
        case vstack([LoomNode])
        /// Horizontal stack — children laid out left to right.
        case hstack([LoomNode])
        /// Overlay stack — children layered on top of each other.
        case zstack([LoomNode], alignment: LoomZAlignment)
        /// Text node. `maxLines` caps the measured height to exactly the
        /// first N lines (including `NSParagraphStyle.lineSpacing` and
        /// `paragraphSpacing` between them); `nil` means no limit.
        /// `measurer` is the size resolver — defaults to
        /// ``TextMeasurer/shared`` (Core Text), but can be any
        /// ``TextMeasuring`` conformer to align with a different
        /// renderer (YYLabel, SwiftUI Text, custom CT view, …).
        case text(NSAttributedString, maxLines: Int?, measurer: any TextMeasuring)
        /// Fixed-size node — width/height set via style.
        case fixed
        /// Spacer — occupies space, height set via style.
        case spacer
        /// Custom-measured node — size computed by the provided closure.
        case measured(@Sendable (CGFloat, CGFloat) -> CGSize)
    }

    public let kind: Kind
    /// Layout style properties (flex, size, padding, margin, etc.).
    public var style: LoomStyle
    /// Key for retrieving this node's frame from ``LayoutResult``.
    public var key: String?

    init(kind: Kind, style: LoomStyle = LoomStyle(), key: String? = nil) {
        self.kind = kind
        self.style = style
        self.key = key
    }

    var isLeaf: Bool {
        switch kind {
        case .vstack, .hstack, .zstack: return false
        case .text, .fixed, .spacer, .measured: return true
        }
    }
}

// MARK: - Modifiers

extension LoomNode {
    /// Assign a key for retrieving this node's computed frame from ``LayoutResult/frame(for:)``.
    /// - Parameter key: A ``LoomKey`` conforming value (enum case or String).
    /// - Returns: A copy of this node with the key set.
    public func key(_ key: some LoomKey) -> LoomNode {
        var copy = self
        copy.key = key.loomKeyValue
        return copy
    }

    // MARK: Padding

    /// Set equal padding on all edges.
    ///
    /// > Note: On leaf nodes (Text, Measured), padding is automatically handled by
    /// > wrapping in a container — the key's frame will correspond to the content area.
    public func padding(_ value: CGFloat) -> LoomNode {
        var copy = self
        copy.style.padding = LoomEdgeInsets(all: value)
        return copy
    }

    /// Set padding on specific edges.
    public func padding(_ edge: LoomEdge, _ value: CGFloat) -> LoomNode {
        var copy = self
        switch edge {
        case .all:
            copy.style.padding = LoomEdgeInsets(all: value)
        case .horizontal:
            copy.style.padding.left = value
            copy.style.padding.right = value
        case .vertical:
            copy.style.padding.top = value
            copy.style.padding.bottom = value
        case .top: copy.style.padding.top = value
        case .bottom: copy.style.padding.bottom = value
        case .left: copy.style.padding.left = value
        case .right: copy.style.padding.right = value
        case .leading: copy.style.padding.leading = value
        case .trailing: copy.style.padding.trailing = value
        }
        return copy
    }

    // MARK: Margin

    /// Set equal margin on all edges.
    public func margin(_ value: CGFloat) -> LoomNode {
        var copy = self
        copy.style.margin = LoomEdgeInsets(all: value)
        return copy
    }

    /// Set margin on specific edges.
    public func margin(_ edge: LoomEdge, _ value: CGFloat) -> LoomNode {
        var copy = self
        switch edge {
        case .all:
            copy.style.margin = LoomEdgeInsets(all: value)
        case .horizontal:
            copy.style.margin.left = value
            copy.style.margin.right = value
        case .vertical:
            copy.style.margin.top = value
            copy.style.margin.bottom = value
        case .top: copy.style.margin.top = value
        case .bottom: copy.style.margin.bottom = value
        case .left: copy.style.margin.left = value
        case .right: copy.style.margin.right = value
        case .leading: copy.style.margin.leading = value
        case .trailing: copy.style.margin.trailing = value
        }
        return copy
    }

    // MARK: Flex

    /// Set flex grow factor. Determines how much this item grows relative to siblings
    /// when there is extra space on the main axis.
    public func flex(grow: CGFloat) -> LoomNode {
        var copy = self
        copy.style.flexGrow = grow
        return copy
    }

    /// Set flex shrink factor. Determines how much this item shrinks relative to siblings
    /// when there is insufficient space on the main axis.
    public func flex(shrink: CGFloat) -> LoomNode {
        var copy = self
        copy.style.flexShrink = shrink
        return copy
    }

    /// Set both flex grow and shrink factors.
    public func flex(grow: CGFloat, shrink: CGFloat) -> LoomNode {
        var copy = self
        copy.style.flexGrow = grow
        copy.style.flexShrink = shrink
        return copy
    }

    /// Set the initial size of the item before flex distribution.
    public func flexBasis(_ value: CGFloat) -> LoomNode {
        var copy = self
        copy.style.flexBasis = value
        return copy
    }

    // MARK: Size

    /// Set explicit width and/or height.
    public func size(width: CGFloat? = nil, height: CGFloat? = nil) -> LoomNode {
        var copy = self
        if let w = width { copy.style.width = w }
        if let h = height { copy.style.height = h }
        return copy
    }

    /// Set minimum width and/or height constraints.
    public func minSize(width: CGFloat? = nil, height: CGFloat? = nil) -> LoomNode {
        var copy = self
        if let w = width { copy.style.minWidth = w }
        if let h = height { copy.style.minHeight = h }
        return copy
    }

    /// Set maximum width and/or height constraints.
    public func maxSize(width: CGFloat? = nil, height: CGFloat? = nil) -> LoomNode {
        var copy = self
        if let w = width { copy.style.maxWidth = w }
        if let h = height { copy.style.maxHeight = h }
        return copy
    }

    /// Set a width-to-height aspect ratio.
    public func aspectRatio(_ ratio: CGFloat) -> LoomNode {
        var copy = self
        copy.style.aspectRatio = ratio
        return copy
    }

    // MARK: Alignment

    /// Override the parent container's cross-axis alignment for this item.
    public func alignSelf(_ align: LoomAlign) -> LoomNode {
        var copy = self
        copy.style.alignSelf = align
        return copy
    }

    // MARK: Position

    /// Set absolute positioning with optional edge offsets.
    ///
    /// `left` / `right` are absolute (direction-unaware); `leading` /
    /// `trailing` flip with the layout's resolved ``LoomDirection``.
    /// See <doc:RTLSupport>.
    ///
    /// ```swift
    /// Fixed(width: 16, height: 16)
    ///     .position(type: .absolute, top: 0, trailing: 0)
    ///     .key(.badge)  // top-trailing badge in any direction
    /// ```
    public func position(
        type: LoomPositionType,
        top: CGFloat? = nil,
        left: CGFloat? = nil,
        bottom: CGFloat? = nil,
        right: CGFloat? = nil,
        leading: CGFloat? = nil,
        trailing: CGFloat? = nil
    ) -> LoomNode {
        var copy = self
        copy.style.positionType = type
        if let t = top { copy.style.position.top = t }
        if let l = left { copy.style.position.left = l }
        if let b = bottom { copy.style.position.bottom = b }
        if let r = right { copy.style.position.right = r }
        if let lead = leading { copy.style.position.leading = lead }
        if let trail = trailing { copy.style.position.trailing = trail }
        return copy
    }

    // MARK: Direction

    /// Override the layout direction for this node and its descendants.
    ///
    /// Pass `.inherit` (the default for any node that doesn't call
    /// `.direction(_:)`) to fall back to the parent's direction. At
    /// the root layout, `.inherit` resolves to the system direction.
    ///
    /// Useful for embedding content with a known direction inside a
    /// subtree of the opposite direction (e.g. an LTR code snippet
    /// inside an RTL article body). See <doc:RTLSupport>.
    public func direction(_ direction: LoomDirection) -> LoomNode {
        var copy = self
        copy.style.direction = (direction == .inherit) ? nil : direction
        return copy
    }
}
