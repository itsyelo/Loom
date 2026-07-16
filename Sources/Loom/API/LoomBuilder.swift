import Foundation

/// Result builder for declaratively constructing ``LoomNode`` trees.
///
/// Supports `if/else`, `for` loops, and optional nodes:
/// ```swift
/// VStack {
///     Text(titleAttr).key(.title)
///     if showImage {
///         Fixed(width: 200, height: 150).key(.image)
///     }
///     for tag in tags {
///         Text(tag.attr).key("tag-\(tag.id)")
///     }
/// }
/// ```
@resultBuilder
public struct LoomBuilder {
    public static func buildBlock(_ components: [LoomNode]...) -> [LoomNode] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: LoomNode) -> [LoomNode] {
        [expression]
    }

    public static func buildOptional(_ component: [LoomNode]?) -> [LoomNode] {
        component ?? []
    }

    public static func buildEither(first component: [LoomNode]) -> [LoomNode] {
        component
    }

    public static func buildEither(second component: [LoomNode]) -> [LoomNode] {
        component
    }

    public static func buildArray(_ components: [[LoomNode]]) -> [LoomNode] {
        components.flatMap { $0 }
    }
}
