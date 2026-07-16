import UIKit
import Loom
import SDWebImage

// MARK: - Shared Bubble Palette
//
// Incoming bubbles use a neutral system background — `content`'s attributed
// strings (built in `ChatMessageContent`, task 02) already use `.label` /
// `.secondaryLabel` colors that read correctly on that background in both
// appearances, so incoming cells apply the attributed strings unmodified.
//
// Outgoing ("me") bubbles use a saturated `systemBlue` fill. `.label` /
// `.secondaryLabel` text is close to unreadable on that fill, so outgoing
// cells re-color a *copy* of each attributed string at configure time
// instead of threading a direction parameter through task 02's attr
// builders — see findings.md ("[Decision] outgoing color adaptation").
private enum ChatBubblePalette {
    static let incomingBackground = UIColor.secondarySystemBackground
    static let outgoingBackground = UIColor.systemBlue

    static let outgoingBody = UIColor.white
    static let outgoingTime = UIColor.white.withAlphaComponent(0.75)
    /// Read receipts on the outgoing (blue) bubble can't use the
    /// light/dark-mode "seen" blue tint (it would vanish on a blue fill), so
    /// opacity carries the same "sending < sent < read" progression instead.
    static func outgoingReceipt(for status: DeliveryStatus) -> UIColor {
        status == .read ? .white : UIColor.white.withAlphaComponent(0.75)
    }

    /// Dark, semi-transparent pill behind time/receipt text overlaid
    /// directly on a photo — required for legibility regardless of bubble
    /// direction or the photo's own colors.
    static let imageOverlayPill = UIColor.black.withAlphaComponent(0.45)
    static let imageOverlayText = UIColor.white
}

/// Returns a copy of `attr` with `.foregroundColor` overridden across its
/// full range, preserving every other attribute (font, kerning, ...). Used
/// to re-tint the already-built attributed strings from `ChatMessageContent`
/// for contexts task 02 doesn't know about (outgoing bubble fill, photo
/// overlay pill) without rebuilding them from scratch.
private func recolored(_ attr: NSAttributedString?, _ color: UIColor) -> NSAttributedString? {
    guard let attr else { return nil }
    let result = NSMutableAttributedString(attributedString: attr)
    result.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: result.length))
    return result
}

// MARK: - ChatTextCell

/// Text-bubble message row: avatar (incoming only) + rounded bubble holding
/// body text and a trailing time/receipt line. One reuse identifier serves
/// both directions — `configure(vm:)` fully re-derives every visual property
/// (colors, avatar visibility, receipt presence) from the view model each
/// time, so there is no stale per-direction state to leak across reuse.
final class ChatTextCell: UITableViewCell {
    static let reuseID = "ChatTextCell"

    private let avatarView = UIImageView()
    private let bubbleView = UIView()
    private let bodyLabel = UILabel()
    private let timeLabel = UILabel()
    private let receiptLabel = UILabel()

    private var layoutResult: LayoutResult?

    // All bound views are added directly to `contentView` (not to
    // `bubbleView`), so `LayoutResult.frame(for:)`'s root-relative frames
    // apply to them as-is — no `relativeTo:` translation needed, unlike
    // FeedCell's link-preview card which nests real subviews inside a
    // positioned container.
    private lazy var bindings = LoomBindings {
        LoomBind(ChatKey.avatar, to: avatarView)
        LoomBind(ChatKey.bubble, to: bubbleView)
        LoomBind(ChatKey.body, to: bodyLabel)
        LoomBind(ChatKey.time, to: timeLabel)
        LoomBind(ChatKey.receipt, to: receiptLabel)
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.sd_cancelCurrentImageLoad()
        avatarView.image = nil
    }

    private func setupSubviews() {
        avatarView.layer.cornerRadius = ChatLayout.avatarSize / 2
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.backgroundColor = .systemGray5

        bubbleView.layer.cornerRadius = 16
        bubbleView.clipsToBounds = true

        bodyLabel.numberOfLines = 0
        timeLabel.numberOfLines = 1
        receiptLabel.numberOfLines = 1

        // z-order: bubble background behind its own text.
        contentView.addSubview(avatarView)
        contentView.addSubview(bubbleView)
        contentView.addSubview(bodyLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(receiptLabel)
    }

    func configure(vm: ChatMessageVM) {
        layoutResult = vm.layout
        let content = vm.content
        let isMe = content.message.sender?.isMe ?? false

        avatarView.isHidden = isMe
        if !isMe, let sender = content.message.sender {
            avatarView.sd_setImage(with: sender.avatarURL)
        }

        bubbleView.backgroundColor = isMe ? ChatBubblePalette.outgoingBackground : ChatBubblePalette.incomingBackground

        if isMe {
            bodyLabel.attributedText = recolored(content.bodyAttr, ChatBubblePalette.outgoingBody)
            timeLabel.attributedText = recolored(content.timeAttr, ChatBubblePalette.outgoingTime)
            receiptLabel.attributedText = recolored(
                content.receiptAttr,
                ChatBubblePalette.outgoingReceipt(for: content.message.status)
            )
        } else {
            bodyLabel.attributedText = content.bodyAttr
            timeLabel.attributedText = content.timeAttr
            receiptLabel.attributedText = nil
        }

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bindings.apply(layoutResult)
    }
}

// MARK: - ChatImageCell

/// Photo message row: same avatar/bubble arrangement as `ChatTextCell`, but
/// the bubble content is a fixed-size photo with the time/receipt overlaid
/// at its bottom-trailing corner on a dark pill (required for legibility —
/// `secondaryLabel`-weight text directly on an arbitrary photo is often
/// unreadable).
final class ChatImageCell: UITableViewCell {
    static let reuseID = "ChatImageCell"

    private let avatarView = UIImageView()
    private let photoView = UIImageView()
    /// Dark rounded pill sized (in `layoutSubviews`) to the union of the
    /// time/receipt frames, sitting behind them — not itself a bound key,
    /// since its frame is derived arithmetically from two known frames
    /// rather than measured or laid out independently.
    private let overlayPill = UIView()
    private let timeLabel = UILabel()
    private let receiptLabel = UILabel()

    private var layoutResult: LayoutResult?

    private lazy var bindings = LoomBindings {
        LoomBind(ChatKey.avatar, to: avatarView)
        LoomBind(ChatKey.image, to: photoView)
        LoomBind(ChatKey.time, to: timeLabel)
        LoomBind(ChatKey.receipt, to: receiptLabel)
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.sd_cancelCurrentImageLoad()
        avatarView.image = nil
        photoView.sd_cancelCurrentImageLoad()
        photoView.image = nil
    }

    private func setupSubviews() {
        avatarView.layer.cornerRadius = ChatLayout.avatarSize / 2
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.backgroundColor = .systemGray5

        photoView.layer.cornerRadius = 12
        photoView.clipsToBounds = true
        photoView.contentMode = .scaleAspectFill
        photoView.backgroundColor = .systemGray5

        overlayPill.backgroundColor = ChatBubblePalette.imageOverlayPill
        overlayPill.isUserInteractionEnabled = false

        timeLabel.numberOfLines = 1
        receiptLabel.numberOfLines = 1

        contentView.addSubview(avatarView)
        contentView.addSubview(photoView)
        contentView.addSubview(overlayPill)
        contentView.addSubview(timeLabel)
        contentView.addSubview(receiptLabel)
    }

    func configure(vm: ChatMessageVM) {
        layoutResult = vm.layout
        let content = vm.content
        let isMe = content.message.sender?.isMe ?? false

        avatarView.isHidden = isMe
        if !isMe, let sender = content.message.sender {
            avatarView.sd_setImage(with: sender.avatarURL)
        }

        if case .image(let url, _) = content.message.kind {
            photoView.sd_setImage(with: url)
        }

        timeLabel.attributedText = recolored(content.timeAttr, ChatBubblePalette.imageOverlayText)
        receiptLabel.attributedText = recolored(content.receiptAttr, ChatBubblePalette.imageOverlayText)
        // Incoming photos never have a receipt (task 02 only emits the
        // `.receipt` key for outgoing messages), but guard defensively so a
        // stray reused frame can't make an empty label paint a visible pill.
        receiptLabel.isHidden = content.receiptAttr == nil

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bindings.apply(layoutResult)

        // `.receipt` has no frame at all for incoming messages (the layout
        // never emits the key), so fall back to the time frame alone when
        // sizing the pill.
        guard let timeFrame = layoutResult?.frame(for: ChatKey.time) else {
            overlayPill.frame = .zero
            return
        }
        let receiptFrame = receiptLabel.isHidden ? nil : layoutResult?.frame(for: ChatKey.receipt)
        let unionFrame = receiptFrame.map { timeFrame.union($0) } ?? timeFrame
        let pillFrame = unionFrame.insetBy(dx: -6, dy: -3)
        overlayPill.frame = pillFrame
        overlayPill.layer.cornerRadius = pillFrame.height / 2
    }
}

// MARK: - ChatSystemCell

/// Centered, bubble-less notice row (date separators, "you started this
/// conversation", ...). No avatar, no bubble background — just one label.
final class ChatSystemCell: UITableViewCell {
    static let reuseID = "ChatSystemCell"

    private let systemLabel = UILabel()
    private var layoutResult: LayoutResult?

    private lazy var bindings = LoomBindings {
        LoomBind(ChatKey.system, to: systemLabel)
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        systemLabel.numberOfLines = 0
        contentView.addSubview(systemLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(vm: ChatMessageVM) {
        layoutResult = vm.layout
        systemLabel.attributedText = vm.content.systemAttr
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bindings.apply(layoutResult)
    }
}
