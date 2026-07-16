#if canImport(UIKit)
import UIKit

extension UIView {
    /// Calculate layout using this view's bounds width.
    ///
    /// Convenience for non-list views — automatically uses `bounds.width`
    /// as the container width and calls `calculate()` synchronously.
    ///
    /// ```swift
    /// override func layoutSubviews() {
    ///     super.layoutSubviews()
    ///     let result = loomLayout {
    ///         HStack(spacing: 12, align: .center) {
    ///             Fixed(width: 60, height: 60).key(.avatar)
    ///             VStack(spacing: 4) {
    ///                 Text(nameAttr).key(.name)
    ///                 Text(bioAttr).key(.bio)
    ///             }.flex(grow: 1)
    ///         }.padding(16)
    ///     }
    ///     bindings.apply(result)
    /// }
    /// ```
    ///
    /// - Parameter content: Child nodes built with ``LoomBuilder``.
    /// - Returns: A computed ``LayoutResult`` with frames for all keyed nodes.
    public func loomLayout(@LoomBuilder content: () -> [LoomNode]) -> LayoutResult {
        LoomLayout(width: bounds.width, content: content).calculate()
    }
}
#endif
