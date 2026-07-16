import CoreGraphics

/// Conform your model to this protocol to enable convenient cache integration.
///
/// ```swift
/// struct Post: LoomLayoutable {
///     let id: String
///     let nameAttr: NSAttributedString
///     let bodyAttr: NSAttributedString
///
///     var loomLayoutId: AnyHashable { id }
///
///     func loomLayout(width: CGFloat) -> LoomLayout {
///         LoomLayout(width: width) {
///             VStack(spacing: 8) {
///                 Text(nameAttr).key(FeedKey.name)
///                 Text(bodyAttr).key(FeedKey.body)
///             }
///         }
///     }
/// }
/// ```
public protocol LoomLayoutable {
    var loomLayoutId: AnyHashable { get }
    func loomLayout(width: CGFloat) -> LoomLayout
}

extension LayoutCache {
    /// Resolve layout for a LoomLayoutable model.
    public func resolve(_ model: some LoomLayoutable, width: CGFloat) -> LayoutResult {
        resolve(id: model.loomLayoutId, width: width) {
            model.loomLayout(width: width)
        }
    }

    /// Get cached height for a LoomLayoutable model, calculating if needed.
    public func height(for model: some LoomLayoutable, width: CGFloat) -> CGFloat {
        resolve(model, width: width).height
    }
}
