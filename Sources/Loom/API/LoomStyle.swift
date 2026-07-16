import CoreGraphics

/// Edge insets for padding, margin, and position values.
///
/// Carries two families of horizontal-axis edges:
///
/// - **Absolute** (``left`` / ``right``): tied to a physical edge
///   regardless of direction.
/// - **Direction-aware** (``leading`` / ``trailing``): resolve to a
///   physical edge based on the layout's resolved ``LoomDirection``.
///   Mirrors `UIDirectionalEdgeInsets` semantics.
///
/// Values from both families add together on the same physical edge.
/// For example, under `.ltr`, the physical-left padding is
/// `left + leading`; under `.rtl`, the physical-left padding is
/// `left + trailing`. See <doc:RTLSupport>.
public struct LoomEdgeInsets: Sendable, Equatable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat
    /// Direction-aware leading edge. Resolves to physical left under
    /// ``LoomDirection/ltr`` and physical right under
    /// ``LoomDirection/rtl``.
    public var leading: CGFloat
    /// Direction-aware trailing edge. Mirror of ``leading``.
    public var trailing: CGFloat

    public static let zero = LoomEdgeInsets(
        top: 0, left: 0, bottom: 0, right: 0, leading: 0, trailing: 0
    )

    public init(
        top: CGFloat = 0,
        left: CGFloat = 0,
        bottom: CGFloat = 0,
        right: CGFloat = 0,
        leading: CGFloat = 0,
        trailing: CGFloat = 0
    ) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
        self.leading = leading
        self.trailing = trailing
    }

    public init(all value: CGFloat) {
        self.init(top: value, left: value, bottom: value, right: value)
    }

    public init(horizontal: CGFloat = 0, vertical: CGFloat = 0) {
        self.init(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
}

/// Absolute-position edge offsets for a ``LoomNode``.
///
/// Unlike ``LoomEdgeInsets``, every edge is optional: `nil` means the
/// edge is unconstrained (Yoga places the node according to the parent's
/// `justify` / `align`), while an explicit value — **including `0`** —
/// pins the node's edge at that offset from the container edge.
///
/// `left` / `right` are absolute; `leading` / `trailing` resolve based
/// on the layout's ``LoomDirection``. See <doc:RTLSupport>.
public struct LoomPosition: Sendable, Equatable {
    public var top: CGFloat?
    public var left: CGFloat?
    public var bottom: CGFloat?
    public var right: CGFloat?
    /// Direction-aware leading edge offset.
    public var leading: CGFloat?
    /// Direction-aware trailing edge offset.
    public var trailing: CGFloat?

    /// No edges constrained.
    public static let unset = LoomPosition()

    public init(
        top: CGFloat? = nil,
        left: CGFloat? = nil,
        bottom: CGFloat? = nil,
        right: CGFloat? = nil,
        leading: CGFloat? = nil,
        trailing: CGFloat? = nil
    ) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
        self.leading = leading
        self.trailing = trailing
    }
}

/// Layout style properties for a ``LoomNode``.
///
/// Usually set via modifier methods on ``LoomNode`` (e.g. `.flex(grow:)`, `.padding(_:)`).
/// Can also be accessed directly via ``LoomNode/style``.
public struct LoomStyle: Sendable {
    // Container properties
    public var justifyContent: LoomJustify = .start
    public var alignItems: LoomAlign = .stretch
    public var alignContent: LoomAlign = .start
    public var gap: CGFloat = 0
    public var lineSpacing: CGFloat? = nil  // row gap, defaults to same as gap if nil
    public var wrap: LoomWrap = .noWrap

    // Flex item properties
    public var flexGrow: CGFloat = 0
    public var flexShrink: CGFloat = 1
    public var flexBasis: CGFloat? = nil
    public var alignSelf: LoomAlign? = nil

    // Dimensions
    public var width: CGFloat? = nil
    public var height: CGFloat? = nil
    public var minWidth: CGFloat? = nil
    public var maxWidth: CGFloat? = nil
    public var minHeight: CGFloat? = nil
    public var maxHeight: CGFloat? = nil
    public var aspectRatio: CGFloat? = nil

    // Spacing
    public var padding: LoomEdgeInsets = .zero
    public var margin: LoomEdgeInsets = .zero

    // Positioning
    public var positionType: LoomPositionType = .relative
    public var position: LoomPosition = .unset

    /// Layout direction override for this node and its descendants.
    ///
    /// `nil` (default) means inherit from parent — at the root, that
    /// resolves to the system direction at calculate time.
    /// Use `.ltr` or `.rtl` to pin this subtree to a specific
    /// direction regardless of ancestors.
    public var direction: LoomDirection? = nil

    public init() {}
}
