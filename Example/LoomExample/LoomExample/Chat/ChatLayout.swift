import UIKit
import Loom

// MARK: - Layout Keys

/// Keys for all binds used across the three chat message layouts (text,
/// image, system). Not every message uses every key — e.g. `receipt` only
/// appears on messages sent by "me", `avatar` only on incoming ones.
enum ChatKey: String, LoomKey {
    case avatar, bubble, body, time, receipt, image, system
    var loomKeyValue: String { rawValue }
}

// MARK: - ChatLayout

/// Namespace for the chat bubble layout builders and their shared constants.
/// Mirrors `FeedCell.buildLayout`'s role: pure `LoomLayout` construction from
/// already-built attributed strings, no UIKit involved.
enum ChatLayout {

    // MARK: Constants

    /// Bubble max width as a fraction of the row width.
    static let bubbleWidthRatio: CGFloat = 0.72
    /// Avatar size for incoming messages.
    static let avatarSize: CGFloat = 32
    /// System message max width as a fraction of the row width.
    static let systemWidthRatio: CGFloat = 0.8
    /// Image message max width as a fraction of the row width.
    static let imageWidthRatio: CGFloat = 0.6
    /// Image message max height, regardless of aspect ratio.
    static let imageMaxHeight: CGFloat = 280

    /// Horizontal inset applied to every row (outside the bubble).
    private static let rowHorizontalPadding: CGFloat = 12
    /// Vertical inset inside each message row (8pt between bubbles — 4pt
    /// from each row — matching mainstream chat spacing).
    ///
    /// Applied as root *padding*, deliberately not margin: each builder's
    /// single top-level node becomes the Yoga ROOT (`LoomLayout.init`
    /// unwraps a lone child), and Yoga half-ignores root margins — the
    /// subtree still shifts down by `margin.top`, but `LayoutResult.height`
    /// excludes the margin entirely. Every row then overflows its cell by
    /// `margin.top`, which reads as randomly "clipped" bubbles (overflow
    /// hidden or shown depending on neighboring cells' reuse z-order) and
    /// zero visual spacing. Root padding participates fully in the
    /// calculated size, so rows contain their content exactly.
    private static let rowVerticalPadding: CGFloat = 4
    /// Gap between avatar and bubble.
    private static let avatarGap: CGFloat = 8
    /// Bubble corner padding around its content.
    private static let bubblePadding: CGFloat = 10
    /// Gap between body text and the trailing time/receipt line.
    private static let metaTopGap: CGFloat = 4
    /// Gap between the time label and the receipt glyph.
    private static let metaSpacing: CGFloat = 3

    // MARK: - Dispatch

    /// Build the row layout for a message's content, dispatching to the
    /// per-kind builder. `width` is the full row width (table view width);
    /// bubble/image max sizes are derived from it internally.
    static func build(for content: ChatMessageContent, width: CGFloat, direction: LoomDirection) -> LoomLayout {
        switch content.message.kind {
        case .text:
            return textLayout(content: content, width: width, direction: direction)
        case .image:
            return imageLayout(content: content, width: width, direction: direction)
        case .system:
            return systemLayout(content: content, width: width, direction: direction)
        }
    }

    // MARK: - Text Bubble

    /// Text message row: avatar (incoming only) + bubble containing body text
    /// and a trailing time/receipt line. Bubble hugs its content up to
    /// `bubbleWidthRatio * width`; short text naturally leaves the bubble
    /// narrower since `Text` measures to its own intrinsic width.
    static func textLayout(content: ChatMessageContent, width: CGFloat, direction: LoomDirection) -> LoomLayout {
        let isMe = content.message.sender?.isMe ?? false
        let bubbleMaxWidth = floor(width * bubbleWidthRatio)

        return LoomLayout(width: width, direction: direction) {
            HStack(spacing: avatarGap, align: .end) {
                if isMe {
                    Spacer(0).flex(grow: 1, shrink: 0)
                    textBubble(content: content, isMe: true, maxWidth: bubbleMaxWidth)
                } else {
                    Fixed(width: avatarSize, height: avatarSize).key(ChatKey.avatar)
                    textBubble(content: content, isMe: false, maxWidth: bubbleMaxWidth)
                    Spacer(0).flex(grow: 1, shrink: 0)
                }
            }
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
        }
    }

    /// The bubble itself: a `.key(.bubble)` container (the cell binds this
    /// key's frame to a rounded background view) holding the body text and
    /// the trailing meta line (time + receipt for outgoing messages only).
    ///
    /// The container keeps the default `.stretch` cross-axis alignment (its
    /// own width is auto/shrink-to-fit up to `maxWidth`, resolved from
    /// `body`'s natural content width — this is what lets short messages
    /// narrow the bubble). Only the trailing meta line opts out via
    /// `.alignSelf(.end)` so it hugs the bubble's right edge regardless of
    /// how wide the body text ends up.
    private static func textBubble(content: ChatMessageContent, isMe: Bool, maxWidth: CGFloat) -> LoomNode {
        VStack(spacing: metaTopGap) {
            Text(content.bodyAttr ?? NSAttributedString()).key(ChatKey.body)

            if isMe {
                HStack(spacing: metaSpacing, align: .center) {
                    Text(content.timeAttr ?? NSAttributedString()).key(ChatKey.time)
                    Text(content.receiptAttr ?? NSAttributedString()).key(ChatKey.receipt)
                }.alignSelf(.end)
            } else {
                Text(content.timeAttr ?? NSAttributedString()).key(ChatKey.time).alignSelf(.end)
            }
        }
        .key(ChatKey.bubble)
        .padding(bubblePadding)
        .maxSize(width: maxWidth)
    }

    // MARK: - Image Bubble

    /// Image message row: same avatar/spacer arrangement as the text bubble,
    /// but the bubble content is a fixed-size image with the timestamp
    /// overlaid at the bottom-trailing corner.
    static func imageLayout(content: ChatMessageContent, width: CGFloat, direction: LoomDirection) -> LoomLayout {
        let isMe = content.message.sender?.isMe ?? false
        let imageSize = scaledImageSize(for: content.message, width: width)

        return LoomLayout(width: width, direction: direction) {
            HStack(spacing: avatarGap, align: .end) {
                if isMe {
                    Spacer(0).flex(grow: 1, shrink: 0)
                    imageBubble(content: content, imageSize: imageSize, isMe: true)
                } else {
                    Fixed(width: avatarSize, height: avatarSize).key(ChatKey.avatar)
                    imageBubble(content: content, imageSize: imageSize, isMe: false)
                    Spacer(0).flex(grow: 1, shrink: 0)
                }
            }
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
        }
    }

    private static func imageBubble(content: ChatMessageContent, imageSize: CGSize, isMe: Bool) -> LoomNode {
        ZStack(alignment: .bottomTrailing) {
            Fixed(width: imageSize.width, height: imageSize.height).key(ChatKey.image)
            HStack(spacing: metaSpacing, align: .center) {
                Text(content.timeAttr ?? NSAttributedString()).key(ChatKey.time)
                if isMe {
                    Text(content.receiptAttr ?? NSAttributedString()).key(ChatKey.receipt)
                }
            }
            .margin(.right, 6)
            .margin(.bottom, 6)
        }
        .key(ChatKey.bubble)
    }

    /// Scale the model's known pixel size down to fit within
    /// `imageWidthRatio * width` and `imageMaxHeight`, preserving aspect
    /// ratio. Computed in Swift (not via a layout modifier) since both caps
    /// apply simultaneously and the smaller resulting scale must win.
    private static func scaledImageSize(for message: ChatMessage, width: CGFloat) -> CGSize {
        guard case .image(_, let naturalSize) = message.kind, naturalSize.width > 0, naturalSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        let maxWidth = floor(width * imageWidthRatio)
        let widthScale = maxWidth / naturalSize.width
        let heightScale = imageMaxHeight / naturalSize.height
        let scale = min(widthScale, heightScale, 1)
        return CGSize(
            width: floor(naturalSize.width * scale),
            height: floor(naturalSize.height * scale)
        )
    }

    // MARK: - System Message

    /// Centered, bubble-less small text — used for date separators and
    /// one-off notices.
    static func systemLayout(content: ChatMessageContent, width: CGFloat, direction: LoomDirection) -> LoomLayout {
        let maxWidth = floor(width * systemWidthRatio)
        return LoomLayout(width: width, direction: direction) {
            HStack(justify: .center) {
                Text(content.systemAttr ?? NSAttributedString())
                    .key(ChatKey.system)
                    .maxSize(width: maxWidth)
            }
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
        }
    }
}
