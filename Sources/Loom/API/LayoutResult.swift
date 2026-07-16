import CoreGraphics

/// The computed layout result containing frames for all keyed nodes.
///
/// Obtain a `LayoutResult` by calling ``LoomLayout/calculate(engine:)``.
/// Then use ``frame(for:)`` to retrieve individual view frames:
///
/// ```swift
/// let result = layout.calculate()
/// avatarView.frame = result.frame(for: CellKey.avatar) ?? .zero
/// ```
public struct LayoutResult: Sendable {
    /// The total computed size of the root node.
    public let size: CGSize
    let frames: [String: CGRect]

    /// The computed height (shorthand for `size.height`).
    public var height: CGFloat { size.height }
    /// The computed width (shorthand for `size.width`).
    public var width: CGFloat { size.width }

    /// Retrieve the computed frame for a keyed node.
    /// - Parameter key: The ``LoomKey`` assigned via ``LoomNode/key(_:)``.
    /// - Returns: The frame in the root node's coordinate space, or `nil` if the key was not found.
    public func frame(for key: some LoomKey) -> CGRect? {
        frames[key.loomKeyValue]
    }

    /// All keyed frames as an array of (key, frame) pairs.
    public var allFrames: [(key: String, frame: CGRect)] {
        frames.map { ($0.key, $0.value) }
    }

    /// Returns a sub-result with all frames re-based relative to the given
    /// container key's origin. Useful for custom views that receive their
    /// own frame from the parent layout and need child frames relative to self.
    ///
    /// ```swift
    /// let cardResult = result.relative(to: FeedKey.card)
    /// titleLabel.frame = cardResult?.frame(for: .cardTitle) ?? .zero
    /// ```
    public func relative(to containerKey: some LoomKey) -> LayoutResult? {
        guard let containerFrame = frame(for: containerKey) else { return nil }
        let origin = containerFrame.origin
        var rebasedFrames: [String: CGRect] = [:]
        for (key, frame) in frames {
            rebasedFrames[key] = frame.offsetBy(dx: -origin.x, dy: -origin.y)
        }
        return LayoutResult(size: containerFrame.size, frames: rebasedFrames)
    }

    init(size: CGSize, frames: [String: CGRect]) {
        self.size = size
        self.frames = frames
    }
}
