import UIKit
import CoreText
import Loom
import SDWebImage

// MARK: - Layout Keys

enum FeedKey: String, LoomKey {
    case avatar, badge, name, time, body
    case likeBtn, commentBtn, shareBtn
    case repostBtn, bookmarkBtn, moreBtn
    case card, cardImage, cardTitle, cardDesc, cardDomain
    case cardImageOverlay, cardDomainBadge

    var loomKeyValue: String { rawValue }
}

// MARK: - Cell

final class FeedCell: UITableViewCell {
    static let reuseID = "FeedCell"

    private let avatarView = UIImageView()
    private let badgeView = UIView()
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()
    private let bodyLabel = UILabel()
    private let cardView = LinkPreviewCard()
    private let separator = UIView()

    private let actionButtons: [(key: FeedKey, button: UIButton)] = {
        let titles = ["♡ Like", "💬 Comment", "↗ Share", "🔁 Repost", "🔖 Bookmark", "•••"]
        let keys: [FeedKey] = [.likeBtn, .commentBtn, .shareBtn, .repostBtn, .bookmarkBtn, .moreBtn]
        return zip(keys, titles).map { key, title in
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13)
            btn.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.2)
            btn.layer.cornerRadius = 4
            return (key, btn)
        }
    }()

    var layoutResult: LayoutResult?
    private lazy var bindings = LoomBindings {
        LoomBind(FeedKey.avatar, to: avatarView)
        LoomBind(FeedKey.badge, to: badgeView)
        LoomBind(FeedKey.name, to: nameLabel)
        LoomBind(FeedKey.time, to: timeLabel)
        LoomBind(FeedKey.body, to: bodyLabel)
        LoomBind(FeedKey.likeBtn, to: actionButtons[0].button)
        LoomBind(FeedKey.commentBtn, to: actionButtons[1].button)
        LoomBind(FeedKey.shareBtn, to: actionButtons[2].button)
        LoomBind(FeedKey.repostBtn, to: actionButtons[3].button)
        LoomBind(FeedKey.bookmarkBtn, to: actionButtons[4].button)
        LoomBind(FeedKey.moreBtn, to: actionButtons[5].button)
    }

    private lazy var cardBindings = LoomBindings {
        LoomBind(FeedKey.cardImage, to: cardView.imageView)
        LoomBind(FeedKey.cardImageOverlay, to: cardView.imageOverlay)
        LoomBind(FeedKey.cardDomainBadge, to: cardView.domainBadgeLabel)
        LoomBind(FeedKey.cardTitle, to: cardView.titleLabel)
        LoomBind(FeedKey.cardDesc, to: cardView.descLabel)
        LoomBind(FeedKey.cardDomain, to: cardView.domainLabel)
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
        cardView.prepareForReuse()
    }

    private func setupSubviews() {
        avatarView.layer.cornerRadius = 20
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.backgroundColor = .systemGray5

        badgeView.backgroundColor = .systemGreen
        badgeView.layer.cornerRadius = 6
        badgeView.layer.borderWidth = 2
        badgeView.layer.borderColor = UIColor.systemBackground.cgColor

        nameLabel.numberOfLines = 1

        separator.backgroundColor = .separator

        for v in [avatarView, badgeView, nameLabel, timeLabel, bodyLabel, cardView, separator] as [UIView] {
            contentView.addSubview(v)
        }
        for (_, btn) in actionButtons {
            contentView.addSubview(btn)
        }
    }

    func configure(content: FeedContent, result: LayoutResult, expanded: Bool) {
        self.layoutResult = result

        // Keep UILabel's line cap in sync with Loom's — otherwise UIKit ignores
        // Loom's two-line frame and renders extra lines outside the measured bounds.
        bodyLabel.numberOfLines = expanded ? 0 : 2

        avatarView.sd_setImage(with: content.post.avatarURL)
        nameLabel.attributedText = content.nameAttr
        bodyLabel.attributedText = content.bodyAttr
        timeLabel.attributedText = content.timeAttr

        if let preview = content.post.linkPreview {
            cardView.isHidden = false
            cardView.configure(with: preview)
        } else {
            cardView.isHidden = true
        }

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        bindings.apply(layoutResult)

        if !cardView.isHidden, let cardFrame = layoutResult?.frame(for: FeedKey.card) {
            cardView.frame = cardFrame
            cardBindings.apply(layoutResult, relativeTo: FeedKey.card)
        }

        separator.frame = CGRect(
            x: 12, y: contentView.bounds.height - 0.5,
            width: contentView.bounds.width - 24, height: 0.5
        )
    }

    // MARK: - Layout Builder

    /// Build the cell layout from pre-built content. The attributed strings
    /// live on ``FeedContent`` — built once per post — so repeated layout
    /// calculations (and the framesetter cache) reuse the same instances.
    static func buildLayout(
        content: FeedContent,
        width: CGFloat,
        expanded: Bool = false,
        direction: LoomDirection = .inherit
    ) -> LoomLayout {
        let nameAttr = content.nameAttr
        let bodyAttr = content.bodyAttr
        let timeAttr = content.timeAttr
        let post = content.post

        return LoomLayout(width: width, direction: direction) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 10, align: .center) {
                    ZStack(alignment: .bottomRight) {
                        Fixed(width: 40, height: 40).key(FeedKey.avatar)
                        Fixed(width: 12, height: 12).key(FeedKey.badge)
                    }
                    Text(nameAttr).key(FeedKey.name).flex(grow: 0, shrink: 1)
                    Spacer(0).flex(grow: 1, shrink: 0)
                    Text(timeAttr).key(FeedKey.time).flex(shrink: 0)
                }.padding(.horizontal, 12).padding(.vertical, 10)

                // Body — collapsed: exactly 2 lines; expanded: full text.
                // maxLines (not maxSize) so the collapsed height snaps to the real
                // 2-line rendering height; binding code must mirror numberOfLines.
                Text(bodyAttr, maxLines: expanded ? nil : 2)
                    .key(FeedKey.body)
                    .flex(grow: 0)
                    .margin(.horizontal, 12)
                    .margin(.bottom, 8)

                // Link preview card (conditional)
                if let preview = post.linkPreview {
                    cardNode(preview)
                        .key(FeedKey.card)
                        .margin(.horizontal, 12)
                        .margin(.bottom, 8)
                }

                // Action bar — wrap if needed
                HStack(spacing: 8, lineSpacing: 8, align: .center, wrap: .wrap) {
                    buttonNode("♡ Like").key(FeedKey.likeBtn)
                    buttonNode("💬 Comment").key(FeedKey.commentBtn)
                    buttonNode("↗ Share").key(FeedKey.shareBtn)
                    buttonNode("🔁 Repost").key(FeedKey.repostBtn)
                    buttonNode("🔖 Bookmark").key(FeedKey.bookmarkBtn)
                    buttonNode("•••").key(FeedKey.moreBtn)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Attributed Strings

    static func nameAttr(_ post: Post) -> NSAttributedString {
        NSAttributedString(string: post.authorName, attributes: [
            .font: UIFont.boldSystemFont(ofSize: 15),
            .foregroundColor: UIColor.label
        ])
    }

    static func bodyAttr(_ post: Post) -> NSAttributedString {
        let text = post.bodyText
        let result = NSMutableAttributedString()

        // Base style
        let baseFont = UIFont.systemFont(ofSize: 14)
        let boldFont = UIFont.boldSystemFont(ofSize: 14)
        let italicFont = UIFont.italicSystemFont(ofSize: 14)
        let monoFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8
        // No locked line height: sizing agreement comes from the app-wide
        // TextKitMeasurer (see AppDelegate). The remaining reason to lock
        // would be UILabel's numberOfLines toggle jitter (problem B in
        // MultilineUILabelTips) — at these 13–14pt fonts it measures
        // ~1–2pt and was judged acceptable. If the design moves to large
        // mixed fonts (3–6pt jitter), re-introduce it with one line:
        //   paragraphStyle.lockLineHeight(toTallestOf: [baseFont, boldFont, italicFont, monoFont])

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle,
            .kern: 0.2
        ]

        result.append(NSAttributedString(string: text, attributes: baseAttrs))

        // Simulate rich text: style @mentions, #hashtags, URLs, and `code`
        let nsText = text as NSString

        // @mentions → bold + tint
        let mentionPattern = try? NSRegularExpression(pattern: "@\\w+")
        for match in mentionPattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? [] {
            result.addAttributes([
                .font: boldFont,
                .foregroundColor: UIColor.systemBlue
            ], range: match.range)
        }

        // #hashtags → bold + tint
        let hashtagPattern = try? NSRegularExpression(pattern: "#\\w+")
        for match in hashtagPattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? [] {
            result.addAttributes([
                .font: boldFont,
                .foregroundColor: UIColor.systemIndigo
            ], range: match.range)
        }

        // URLs → underline + tint
        let urlPattern = try? NSRegularExpression(pattern: "https?://\\S+")
        for match in urlPattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? [] {
            result.addAttributes([
                .foregroundColor: UIColor.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: match.range)
        }

        // `code` → monospace + background
        let codePattern = try? NSRegularExpression(pattern: "`[^`]+`")
        for match in codePattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? [] {
            result.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor.systemOrange,
                .backgroundColor: UIColor.systemGray6
            ], range: match.range)
        }

        // *italic* → italic
        let italicPattern = try? NSRegularExpression(pattern: "\\*[^*]+\\*")
        for match in italicPattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? [] {
            result.addAttributes([.font: italicFont], range: match.range)
        }

        return result
    }

    static func timeAttr(_ post: Post) -> NSAttributedString {
        NSAttributedString(string: post.timeText, attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.secondaryLabel
        ])
    }

    // MARK: - Card Node

    private static func cardNode(_ preview: LinkPreview) -> LoomNode {
        let titleAttr = NSAttributedString(string: preview.title, attributes: [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.label
        ])
        let descAttr = NSAttributedString(string: preview.description, attributes: [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.secondaryLabel
        ])
        let domainAttr = NSAttributedString(string: preview.domain, attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.tertiaryLabel
        ])

        let domainBadgeAttr = NSAttributedString(string: "  \(preview.domain)  ", attributes: [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.white
        ])

        return VStack(spacing: 0) {
            // Image area with overlay + domain badge (ZStack)
            ZStack(alignment: .bottomLeft) {
                // Image (first child sizes the container)
                Spacer(0).size(height: preview.imageHeight)
                    .key(FeedKey.cardImage)
                // Semi-transparent overlay at bottom
                Spacer(0).size(height: 32)
                    .key(FeedKey.cardImageOverlay)
                // Domain badge at bottom-left
                Text(domainBadgeAttr)
                    .key(FeedKey.cardDomainBadge)
                    .margin(.left, 8)
                    .margin(.bottom, 8)
            }

            // Text content below image
            VStack(spacing: 4) {
                Text(titleAttr).key(FeedKey.cardTitle)
                Text(descAttr).key(FeedKey.cardDesc).maxSize(height: 40)
                Text(domainAttr).key(FeedKey.cardDomain)
            }.padding(10)
        }
    }

    // MARK: - Button Node

    private static func buttonNode(_ title: String) -> LoomNode {
        let font = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let attrTitle = NSAttributedString(string: title, attributes: [.font: font])
        let hPadding: CGFloat = 12
        let height: CGFloat = 36

        return Measured { _, _ -> CGSize in
            let textSize = TextMeasurer.measure(attrTitle, maxWidth: .greatestFiniteMagnitude, maxHeight: height)
            return CGSize(width: textSize.width + hPadding * 2, height: height)
        }
    }
}
