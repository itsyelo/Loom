import CoreGraphics

/// The entry point for building and calculating a layout.
///
/// Create a layout with a fixed width and a tree of nodes, then call
/// ``calculate(engine:)`` to compute frames:
///
/// ```swift
/// let layout = LoomLayout(width: 375) {
///     VStack(spacing: 8) {
///         Text(titleAttr).key(.title)
///         Text(bodyAttr).key(.body)
///     }
/// }
///
/// // Synchronous (safe on any thread)
/// let result = layout.calculate()
/// let height = result.height
///
/// // Async (dispatches to background)
/// let result = await layout.calculateAsync()
/// ```
public struct LoomLayout: Sendable {
    /// The root node of the layout tree.
    public let root: LoomNode
    /// The container width used for calculation.
    public let width: CGFloat
    /// The layout direction for the root.
    ///
    /// `.inherit` (the default) resolves to ``Loom/systemDirection``
    /// at calculate time, which means LTR / RTL is picked up from
    /// system settings without any per-call configuration. Pass `.ltr`
    /// or `.rtl` explicitly when you need a deterministic direction
    /// (e.g. tests, previews, force-LTR content blocks).
    public let direction: LoomDirection

    /// Create a layout with a fixed width and child nodes.
    /// - Parameters:
    ///   - width: Container width (e.g. screen width or cell width).
    ///   - direction: Root layout direction. `.inherit` (default)
    ///     resolves to the system direction at calculate time.
    ///   - content: Child nodes built with ``LoomBuilder``.
    public init(
        width: CGFloat,
        direction: LoomDirection = .inherit,
        @LoomBuilder content: () -> [LoomNode]
    ) {
        let children = content()
        if children.count == 1 {
            self.root = children[0]
        } else {
            self.root = LoomNode(kind: .vstack(children))
        }
        self.width = width
        self.direction = direction
    }

    /// Calculate layout synchronously. Safe to call from any thread.
    /// Uses YogaEngine by default; pass a custom engine to override.
    public func calculate(engine: some LayoutEngine = YogaEngine.shared) -> LayoutResult {
        engine.calculate(node: root, width: width, direction: resolvedDirection())
    }

    /// Convenience: calculate and return only the height.
    public func calculateHeight(engine: some LayoutEngine = YogaEngine.shared) -> CGFloat {
        calculate(engine: engine).height
    }

    /// Calculate layout asynchronously on a background thread.
    /// Convenience for calling from the main thread without manual dispatch.
    @available(iOS 13.0, macOS 10.15, *)
    public func calculateAsync(engine: some LayoutEngine = YogaEngine.shared) async -> LayoutResult {
        let resolved = resolvedDirection()
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = engine.calculate(node: root, width: width, direction: resolved)
                continuation.resume(returning: result)
            }
        }
    }

    /// Async convenience: calculate and return only the height.
    @available(iOS 13.0, macOS 10.15, *)
    public func calculateHeightAsync(engine: some LayoutEngine = YogaEngine.shared) async -> CGFloat {
        await calculateAsync(engine: engine).height
    }

    /// Resolve `.inherit` at the root to a concrete LTR/RTL direction
    /// using ``Loom/systemDirection``.
    private func resolvedDirection() -> LoomDirection {
        direction == .inherit ? Loom.systemDirection : direction
    }
}
