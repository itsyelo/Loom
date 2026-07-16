import CoreGraphics

/// A layout calculation engine.
///
/// Loom ships with ``YogaEngine`` (the default). Conform to this protocol
/// to provide a custom engine:
///
/// ```swift
/// class MyEngine: LayoutEngine {
///     func calculate(node: LoomNode, width: CGFloat) -> LayoutResult { ... }
/// }
/// let result = layout.calculate(engine: MyEngine())
/// ```
public protocol LayoutEngine {
    /// Calculate layout for the given node tree at the specified width.
    /// - Parameters:
    ///   - node: The root ``LoomNode`` of the layout tree.
    ///   - width: The available container width.
    /// - Returns: A ``LayoutResult`` with computed frames for all keyed nodes.
    func calculate(node: LoomNode, width: CGFloat) -> LayoutResult

    /// Calculate layout with an explicit root layout direction. Used by
    /// ``LoomLayout`` to propagate `.ltr` / `.rtl` to the engine.
    ///
    /// Has a default implementation that ignores `direction` and falls
    /// back to ``calculate(node:width:)`` so existing custom engines
    /// keep working. Engines that support RTL (e.g. ``YogaEngine``)
    /// override this method.
    func calculate(
        node: LoomNode,
        width: CGFloat,
        direction: LoomDirection
    ) -> LayoutResult
}

extension LayoutEngine {
    public func calculate(
        node: LoomNode,
        width: CGFloat,
        direction: LoomDirection
    ) -> LayoutResult {
        calculate(node: node, width: width)
    }
}
