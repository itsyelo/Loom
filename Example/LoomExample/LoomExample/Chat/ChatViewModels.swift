import UIKit
import Loom

// MARK: - ChatMessageContent

/// Immutable display content for one message: the attributed strings, built
/// exactly once per message (mirrors `FeedContent`'s role). Only the fields
/// relevant to the message's `kind` are populated — e.g. `bodyAttr` is `nil`
/// for image/system messages, `receiptAttr` is `nil` unless the sender is
/// "me".
struct ChatMessageContent {
    let message: ChatMessage

    /// Text kind only.
    let bodyAttr: NSAttributedString?
    /// Text and image kinds (the timestamp shown next to/over the bubble).
    let timeAttr: NSAttributedString?
    /// Outgoing ("me") text/image messages only — the delivery glyph next
    /// to the timestamp.
    let receiptAttr: NSAttributedString?
    /// System kind only (date separators, notices).
    let systemAttr: NSAttributedString?

    init(message: ChatMessage) {
        self.message = message
        let isMe = message.sender?.isMe ?? false

        switch message.kind {
        case .text(let text):
            bodyAttr = ChatMessageContent.bodyAttr(text)
            timeAttr = ChatMessageContent.timeAttr(message.timestamp)
            receiptAttr = isMe ? ChatMessageContent.receiptAttr(message.status) : nil
            systemAttr = nil

        case .image:
            bodyAttr = nil
            timeAttr = ChatMessageContent.timeAttr(message.timestamp)
            receiptAttr = isMe ? ChatMessageContent.receiptAttr(message.status) : nil
            systemAttr = nil

        case .system(let text):
            bodyAttr = nil
            timeAttr = nil
            receiptAttr = nil
            systemAttr = ChatMessageContent.systemAttr(text)
        }
    }

    // MARK: - Attributed String Builders

    static func bodyAttr(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        let bodyFont = UIFont.systemFont(ofSize: 15)
        // CJK glyphs render through the PingFang fallback font, whose line
        // metrics at 15pt exceed SF's (~21pt vs ~18pt). Without a locked
        // line height, the measuring pass and UILabel's rendering pass can
        // disagree on line geometry for CJK strings, visually truncating
        // the last wrapped line (see the [Bug] finding dated 2026-07-08 in
        // the planning findings). Lock ONLY when the text actually contains
        // CJK: locking unconditionally would inflate Latin-only lines to
        // PingFang's height, sinking their baselines ~3pt and making short
        // bubbles look bottom-cramped. For CJK text the natural line is
        // already ~PingFang-height, so the lock is visually free there.
        if text.unicodeScalars.contains(where: { $0.isCJK }),
           let cjkFallback = UIFont(name: "PingFangSC-Regular", size: 15) {
            paragraphStyle.lockLineHeight(toTallestOf: [bodyFont, cjkFallback])
        }
        return NSAttributedString(string: text, attributes: [
            .font: bodyFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ])
    }

    static func timeAttr(_ date: Date) -> NSAttributedString {
        NSAttributedString(string: timeFormatter.string(from: date), attributes: [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.secondaryLabel
        ])
    }

    static func receiptAttr(_ status: DeliveryStatus) -> NSAttributedString {
        let (glyph, color) = receiptGlyph(for: status)
        return NSAttributedString(string: glyph, attributes: [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: color
        ])
    }

    static func systemAttr(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraphStyle
        ])
    }

    /// Delivery status → (glyph, tint). Read receipts tint blue to match
    /// the familiar "seen" convention; sending/sent stay neutral.
    private static func receiptGlyph(for status: DeliveryStatus) -> (glyph: String, color: UIColor) {
        switch status {
        case .sending: return ("🕓", .secondaryLabel)
        case .sent: return ("✓", .secondaryLabel)
        case .read: return ("✓✓", .systemBlue)
        }
    }

    /// "HH:mm", cached and locale-pinned so the same `Date` always formats
    /// to the same string across runs/devices regardless of the user's
    /// region settings (mirrors `MockChat`'s determinism goal).
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - CJK Detection

private extension Unicode.Scalar {
    /// Covers the ranges that matter for the mock conversation's Chinese
    /// text (and CJK punctuation): enough to decide "will PingFang fallback
    /// metrics apply to this string" — not a general-purpose classifier.
    var isCJK: Bool {
        switch value {
        case 0x4E00...0x9FFF,    // CJK Unified Ideographs
             0x3400...0x4DBF,    // CJK Extension A
             0x3000...0x303F,    // CJK punctuation（，。：etc. live in FF00 too）
             0xFF00...0xFFEF:    // full-width forms
            return true
        default:
            return false
        }
    }
}

// MARK: - ChatMessageVM

/// The chat pipeline's per-row view model (see the FeedListPipeline DocC
/// article for the paradigm): content plus a fully computed `LayoutResult`,
/// built off-main before the row is ever published to the data source. A
/// cache miss in `heightForRowAt` is structurally impossible.
///
/// Delivery-status changes or streaming text edits are modeled as
/// rebuilding a new `ChatMessage` and constructing a brand-new
/// `ChatMessageVM` from it — value semantics make "new content + new
/// layout" an atomic replace, with no partial-update bookkeeping.
struct ChatMessageVM {
    let content: ChatMessageContent
    let layout: LayoutResult

    var id: String { content.message.id }
    var height: CGFloat { layout.height }
    /// Discriminates which cell type/binding a row needs. Direction (me vs.
    /// other) is read separately off `content.message.sender?.isMe` since
    /// only `.text` has two mirrored layouts sharing one builder.
    var kind: ChatMessageKind { content.message.kind }

    /// Builds content and computes the layout. Call off-main — both steps
    /// are pure/thread-safe (Core Text measurement + Yoga calculation).
    init(message: ChatMessage, width: CGFloat, direction: LoomDirection) {
        content = ChatMessageContent(message: message)
        layout = ChatLayout.build(for: content, width: width, direction: direction).calculate()
    }
}

// MARK: - Debug Smoke

#if DEBUG
extension ChatMessageVM {
    /// Minimal smoke check: build a VM for one message of each kind (both
    /// directions for text) and assert every layout produced a positive
    /// height. Not wired to any call site yet — task 04 introduces the
    /// controller that would be a natural place to invoke this once at
    /// startup; kept here so later tasks can call it without re-deriving
    /// sample messages.
    static func debugSmokeTest(width: CGFloat = 390) {
        let now = Date()
        let samples: [ChatMessage] = [
            ChatMessage(id: "smoke-text-in", sender: MockChat.bot, timestamp: now, kind: .text("Hey, how's it going?"), status: .sent),
            ChatMessage(id: "smoke-text-out", sender: MockChat.me, timestamp: now, kind: .text("All good, thanks!"), status: .read),
            ChatMessage(
                id: "smoke-image", sender: MockChat.me, timestamp: now,
                kind: .image(url: URL(string: "https://example.com/x.jpg")!, size: CGSize(width: 1600, height: 1067)),
                status: .sending
            ),
            ChatMessage(id: "smoke-system", sender: nil, timestamp: now, kind: .system("Monday, January 5"), status: .read),
        ]

        for message in samples {
            let vm = ChatMessageVM(message: message, width: width, direction: .ltr)
            assert(vm.height > 0, "ChatMessageVM for \(message.id) computed zero height")
        }
    }
}
#endif
