import Foundation
import CoreGraphics

// MARK: - Container Nodes

/// Create a vertical stack — children laid out top to bottom.
///
/// ```swift
/// VStack(spacing: 8) {
///     Text(titleAttr).key(.title)
///     Text(bodyAttr).key(.body)
/// }
/// ```
///
/// - Parameters:
///   - spacing: Gap between children (default 0).
///   - justify: Main-axis distribution (default `.start`).
///   - align: Cross-axis alignment (default `.stretch`).
///   - children: Child nodes built with ``LoomBuilder``.
/// - Returns: A container ``LoomNode``.
public func VStack(
    spacing: CGFloat = 0,
    justify: LoomJustify = .start,
    align: LoomAlign = .stretch,
    @LoomBuilder children: () -> [LoomNode]
) -> LoomNode {
    var style = LoomStyle()
    style.gap = spacing
    style.justifyContent = justify
    style.alignItems = align
    return LoomNode(kind: .vstack(children()), style: style)
}

/// Create a horizontal stack — children laid out left to right.
///
/// ```swift
/// HStack(spacing: 10, align: .center) {
///     Fixed(width: 40, height: 40).key(.avatar)
///     Text(nameAttr).key(.name).flex(grow: 1)
/// }
/// ```
///
/// - Parameters:
///   - spacing: Gap between children (default 0).
///   - lineSpacing: Gap between lines when wrapping (default same as `spacing`).
///   - justify: Main-axis distribution (default `.start`).
///   - align: Cross-axis alignment (default `.stretch`).
///   - wrap: Whether to wrap to multiple lines (default `.noWrap`).
///   - children: Child nodes built with ``LoomBuilder``.
/// - Returns: A container ``LoomNode``.
public func HStack(
    spacing: CGFloat = 0,
    lineSpacing: CGFloat? = nil,
    justify: LoomJustify = .start,
    align: LoomAlign = .stretch,
    wrap: LoomWrap = .noWrap,
    @LoomBuilder children: () -> [LoomNode]
) -> LoomNode {
    var style = LoomStyle()
    style.gap = spacing
    style.lineSpacing = lineSpacing
    style.justifyContent = justify
    style.alignItems = align
    style.wrap = wrap
    return LoomNode(kind: .hstack(children()), style: style)
}

/// Create an overlay stack — children layered on top of each other.
///
/// The first child determines the container's size. Subsequent children
/// are positioned according to the `alignment` parameter.
///
/// ```swift
/// ZStack(alignment: .bottomRight) {
///     Fixed(width: 40, height: 40).key(.avatar)
///     Fixed(width: 12, height: 12).key(.badge)
/// }
/// ```
///
/// - Parameters:
///   - alignment: Where to position overlay children (default `.topLeft`).
///   - children: Child nodes built with ``LoomBuilder``.
/// - Returns: A container ``LoomNode``.
public func ZStack(
    alignment: LoomZAlignment = .topLeft,
    @LoomBuilder children: () -> [LoomNode]
) -> LoomNode {
    LoomNode(kind: .zstack(children(), alignment: alignment))
}

// MARK: - Leaf Nodes

/// Create a text node.
///
/// Measured on whatever thread `calculate()` is called from. By default
/// uses ``TextMeasurer/shared`` (Core Text, thread-safe, framesetter
/// cached) — pass a custom ``TextMeasuring`` conformer via `measurer:`
/// when binding to a renderer whose natural sizing diverges (YYLabel,
/// SwiftUI Text, custom CT view, etc.).
///
/// Use `maxLines` to cap the node at an exact line count. Because the
/// height snaps to full lines (including `lineSpacing` /
/// `paragraphSpacing`), a truncated layout lines up with the full-text
/// layout pixel-for-pixel on the first N lines — avoiding visible jumps
/// when toggling between collapsed and expanded states.
///
/// ```swift
/// // Default (Core Text + UILabel):
/// Text(bodyAttr, maxLines: 2).key(.body)
///
/// // Custom measurer for a different renderer (e.g. YYLabel):
/// Text(bodyAttr, maxLines: 2, measurer: YYTextMeasurer.shared).key(.body)
/// ```
///
/// When binding this node to a `UILabel`, set `numberOfLines` to the
/// same value (or `0` when `maxLines` is `nil`). UIKit ignores Loom's
/// cap and will draw extra lines outside the measured frame if the two
/// disagree. See <doc:MultilineUILabelTips>.
///
/// - Parameters:
///   - attributedString: The immutable attributed string to measure.
///     Must not be mutated after passing to Loom.
///   - maxLines: Maximum number of lines the node will occupy. `nil`
///     (default) means no limit.
///   - measurer: Pluggable size resolver. `nil` (default) uses
///     ``Loom/defaultTextMeasurer``, captured at node build time.
/// - Returns: A leaf ``LoomNode``.
public func Text(
    _ attributedString: NSAttributedString,
    maxLines: Int? = nil,
    measurer: (any TextMeasuring)? = nil
) -> LoomNode {
    LoomNode(kind: .text(
        attributedString,
        maxLines: maxLines,
        measurer: measurer ?? Loom.defaultTextMeasurer
    ))
}

/// Create a fixed-size node (e.g. avatar image, icon).
///
/// - Parameters:
///   - width: Fixed width in points.
///   - height: Fixed height in points.
/// - Returns: A leaf ``LoomNode``.
public func Fixed(width: CGFloat, height: CGFloat) -> LoomNode {
    var style = LoomStyle()
    style.width = width
    style.height = height
    return LoomNode(kind: .fixed, style: style)
}

/// Create a spacer node that occupies vertical space.
///
/// - Parameter size: Height of the spacer in points.
/// - Returns: A leaf ``LoomNode``.
public func Spacer(_ size: CGFloat) -> LoomNode {
    var style = LoomStyle()
    style.height = size
    return LoomNode(kind: .spacer, style: style)
}

/// Create a node with a custom measurement closure.
///
/// Use this for controls whose size depends on content but can't be
/// measured with Core Text (e.g. buttons with icons + insets).
/// The closure must be thread-safe.
///
/// ```swift
/// Measured { maxWidth, maxHeight -> CGSize in
///     let textSize = TextMeasurer.measure(attrTitle, maxWidth: maxWidth, maxHeight: maxHeight)
///     return CGSize(width: textSize.width + 24, height: 36)
/// }
/// ```
///
/// - Parameter measure: A `@Sendable` closure receiving (maxWidth, maxHeight) and returning the computed size.
/// - Returns: A leaf ``LoomNode``.
public func Measured(
    _ measure: @Sendable @escaping (CGFloat, CGFloat) -> CGSize
) -> LoomNode {
    LoomNode(kind: .measured(measure))
}
