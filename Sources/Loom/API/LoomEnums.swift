import Foundation

// MARK: - LoomKey

/// A type that can be used as a key to identify nodes in a ``LayoutResult``.
///
/// Conform your enum to `LoomKey` to get compile-time safe keys:
/// ```swift
/// enum CellKey: String, LoomKey {
///     case avatar, name, body
///     var loomKeyValue: String { rawValue }
/// }
///
/// Text(attr).key(CellKey.name)
/// result.frame(for: CellKey.name)
/// ```
///
/// `String` also conforms to `LoomKey` for quick prototyping.
public protocol LoomKey {
    /// The string value used internally to store and look up frames.
    var loomKeyValue: String { get }
}

extension String: LoomKey {
    public var loomKeyValue: String { self }
}

extension RawRepresentable where RawValue == String {
    public var loomKeyValue: String { rawValue }
}

// MARK: - Layout Enums

/// Main-axis content distribution within a container.
///
/// Maps to CSS `justify-content` / Yoga `YGJustify`.
public enum LoomJustify: Sendable {
    /// Items packed at the start.
    case start
    /// Items centered.
    case center
    /// Items packed at the end.
    case end
    /// Equal space between items, no space at edges.
    case spaceBetween
    /// Equal space around items (half-space at edges).
    case spaceAround
    /// Equal space between and at edges.
    case spaceEvenly
}

/// Cross-axis alignment for container children or self-alignment.
///
/// Maps to CSS `align-items` / `align-self` / Yoga `YGAlign`.
public enum LoomAlign: Sendable {
    /// Align to the start of the cross axis.
    case start
    /// Center on the cross axis.
    case center
    /// Align to the end of the cross axis.
    case end
    /// Stretch to fill the cross axis (default for containers).
    case stretch
    /// Align to text baseline.
    case baseline
}

/// Controls whether flex items wrap to multiple lines.
///
/// Maps to CSS `flex-wrap` / Yoga `YGWrap`.
public enum LoomWrap: Sendable {
    /// Single line, may overflow (default).
    case noWrap
    /// Wrap to additional lines.
    case wrap
    /// Wrap in reverse order.
    case wrapReverse
}

/// Positioning mode for a node.
public enum LoomPositionType: Sendable {
    /// Normal flow layout (default).
    case relative
    /// Removed from flow, positioned relative to parent.
    case absolute
}

/// Layout direction. Controls how horizontal-axis edges (`.leading` /
/// `.trailing`), HStack child order, and absolute positioning resolve
/// to physical left/right.
///
/// - ``ltr``: leading = left, trailing = right.
/// - ``rtl``: leading = right, trailing = left.
/// - ``inherit``: fall back to the parent's direction. At the root,
///   resolves to the system direction at calculate time
///   (see ``Loom/systemDirection``).
public enum LoomDirection: Sendable {
    case ltr
    case rtl
    case inherit
}

/// Edge specifier for padding, margin, and position.
///
/// Two families:
///
/// - **Absolute** (`.left`, `.right`, `.top`, `.bottom`,
///   `.horizontal`, `.vertical`, `.all`): tied to a physical edge
///   regardless of layout direction.
/// - **Direction-aware** (`.leading`, `.trailing`): resolve to a
///   physical edge based on the resolved ``LoomDirection`` at layout
///   time. `.leading` is the physical left under LTR and the physical
///   right under RTL; `.trailing` is the opposite. Mirrors
///   `UIDirectionalEdgeInsets` semantics from UIKit.
///
/// `.left` / `.right` and `.leading` / `.trailing` can both be set on
/// the same node; the values stack additively on whichever physical
/// edge the direction resolves to. See <doc:RTLSupport>.
public enum LoomEdge: Sendable {
    case all, horizontal, vertical, top, bottom
    case left, right
    case leading, trailing
}

/// Alignment of children within a ``ZStack``.
///
/// Controls where overlaid children are positioned relative to the
/// container. The first child in a ZStack always sizes the container;
/// subsequent children are positioned according to this alignment.
///
/// Two families:
///
/// - **Absolute** (`.topLeft`, `.topCenter`, …, `.bottomRight`): tied
///   to a physical corner / edge regardless of layout direction.
/// - **Direction-aware** (`.topLeading`, `.topTrailing`,
///   `.centerLeading`, `.centerTrailing`, `.bottomLeading`,
///   `.bottomTrailing`): resolve to a physical corner based on the
///   ZStack's resolved ``LoomDirection``. `.topLeading` is top-left
///   under LTR and top-right under RTL; `.bottomTrailing` is the
///   opposite corner. See <doc:RTLSupport>.
public enum LoomZAlignment: Sendable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight
    case topLeading, topTrailing
    case centerLeading, centerTrailing
    case bottomLeading, bottomTrailing
}
