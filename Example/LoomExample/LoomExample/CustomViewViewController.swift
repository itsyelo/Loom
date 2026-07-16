import UIKit
import Loom

// MARK: - Profile Card

/// A non-list Loom integration: the card describes its layout inline in
/// `layoutSubviews` via `UIView.loomLayout` — no cache, no pipeline, just
/// a synchronous calculation against `bounds.width`.
final class ProfileCardView: UIView {

    private enum Key: String, LoomKey {
        case avatar, badge, name, bio
        case stat0Value, stat0Caption, stat1Value, stat1Caption, stat2Value, stat2Caption
        case followBtn
        var loomKeyValue: String { rawValue }
    }

    private let avatarLabel = UILabel()
    private let badgeView = UIView()
    private let nameLabel = UILabel()
    private let bioLabel = UILabel()
    private let statValueLabels = [UILabel(), UILabel(), UILabel()]
    private let statCaptionLabels = [UILabel(), UILabel(), UILabel()]
    private let followButton = UIButton(type: .system)

    private let nameAttr = NSAttributedString(string: "Grace Hopper", attributes: [
        .font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.label,
    ])
    private let bioAttr: NSAttributedString = {
        // No locked line height: with TextKitMeasurer as the app-wide
        // default (see AppDelegate), measurement matches UILabel natively.
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return NSAttributedString(
            string: "Rear admiral, computer scientist. Invented the first compiler and "
                + "popularized machine-independent programming languages. \"The most "
                + "dangerous phrase is: we've always done it this way.\"",
            attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: style,
            ]
        )
    }()
    private let stats: [(value: String, caption: String)] = [
        ("128", "Posts"), ("5.4k", "Followers"), ("312", "Following"),
    ]
    private let followAttr = NSAttributedString(string: "Follow", attributes: [
        .font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.white,
    ])

    private lazy var bindings = LoomBindings {
        LoomBind(Key.avatar, to: avatarLabel)
        LoomBind(Key.badge, to: badgeView)
        LoomBind(Key.name, to: nameLabel)
        LoomBind(Key.bio, to: bioLabel)
        LoomBind(Key.stat0Value, to: statValueLabels[0])
        LoomBind(Key.stat1Value, to: statValueLabels[1])
        LoomBind(Key.stat2Value, to: statValueLabels[2])
        LoomBind(Key.stat0Caption, to: statCaptionLabels[0])
        LoomBind(Key.stat1Caption, to: statCaptionLabels[1])
        LoomBind(Key.stat2Caption, to: statCaptionLabels[2])
        LoomBind(Key.followBtn, to: followButton)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16

        avatarLabel.text = "GH"
        avatarLabel.textAlignment = .center
        avatarLabel.font = .boldSystemFont(ofSize: 24)
        avatarLabel.textColor = .white
        avatarLabel.backgroundColor = .systemIndigo
        avatarLabel.layer.cornerRadius = 36
        avatarLabel.clipsToBounds = true

        badgeView.backgroundColor = .systemGreen
        badgeView.layer.cornerRadius = 9
        badgeView.layer.borderWidth = 2
        badgeView.layer.borderColor = UIColor.secondarySystemGroupedBackground.cgColor

        nameLabel.attributedText = nameAttr
        bioLabel.attributedText = bioAttr
        bioLabel.numberOfLines = 3
        bioLabel.textAlignment = .center

        for (i, stat) in stats.enumerated() {
            statValueLabels[i].text = stat.value
            statValueLabels[i].font = .boldSystemFont(ofSize: 16)
            statValueLabels[i].textAlignment = .center
            statCaptionLabels[i].text = stat.caption
            statCaptionLabels[i].font = .systemFont(ofSize: 11)
            statCaptionLabels[i].textColor = .secondaryLabel
            statCaptionLabels[i].textAlignment = .center
        }

        followButton.setAttributedTitle(followAttr, for: .normal)
        followButton.backgroundColor = .systemBlue
        followButton.layer.cornerRadius = 8

        for v in [avatarLabel, badgeView, nameLabel, bioLabel, followButton] as [UIView] {
            addSubview(v)
        }
        for v in statValueLabels + statCaptionLabels { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        bindings.apply(loomLayout(content: content))
    }

    /// The layout is a plain function of width, so the owning controller
    /// can size the card with the same description it renders with.
    func preferredHeight(for width: CGFloat) -> CGFloat {
        LoomLayout(width: width, content: content).calculateHeight()
    }

    @LoomBuilder private func content() -> [LoomNode] {
        VStack(spacing: 12, align: .center) {
            ZStack(alignment: .bottomTrailing) {
                Fixed(width: 72, height: 72).key(Key.avatar)
                Fixed(width: 18, height: 18).key(Key.badge)
            }
            Text(nameAttr).key(Key.name)
            Text(bioAttr, maxLines: 3).key(Key.bio)

            // The parent VStack centers children (align: .center), so the
            // stats row must opt back into full width for flex/justify
            // to have space to distribute.
            HStack(spacing: 0, justify: .spaceEvenly) {
                statColumn(0, valueKey: Key.stat0Value, captionKey: Key.stat0Caption)
                statColumn(1, valueKey: Key.stat1Value, captionKey: Key.stat1Caption)
                statColumn(2, valueKey: Key.stat2Value, captionKey: Key.stat2Caption)
            }.alignSelf(.stretch).margin(.vertical, 4)

            Measured { _, _ in CGSize(width: 160, height: 36) }
                .key(Key.followBtn)
        }.padding(20)
    }

    private func statColumn(_ index: Int, valueKey: Key, captionKey: Key) -> LoomNode {
        let valueAttr = NSAttributedString(string: stats[index].value, attributes: [
            .font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: UIColor.label,
        ])
        let captionAttr = NSAttributedString(string: stats[index].caption, attributes: [
            .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.secondaryLabel,
        ])
        return VStack(spacing: 2, align: .center) {
            Text(valueAttr).key(valueKey)
            Text(captionAttr).key(captionKey)
        }.flex(grow: 1)
    }
}

// MARK: - View Controller

/// Tab 4 — `UIView.loomLayout` outside of lists, runtime switches for
/// ``LoomDebugOptions`` (frame borders / key labels / timing logs), and
/// the Jitter Lab (`JitterLabView`) for judging the numberOfLines-toggle
/// jitter described in MultilineUILabelTips.
final class CustomViewViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let card = ProfileCardView()
    private let optionsStack = UIStackView()
    private let jitterLab = JitterLabView()

    private let options: [(title: String, option: LoomDebugOptions)] = [
        ("Frame borders", .showFrameBorders),
        ("Key labels", .showKeys),
        ("Log layout time", .logLayoutTime),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Custom View"
        view.backgroundColor = .systemGroupedBackground
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.addSubview(card)

        optionsStack.axis = .vertical
        optionsStack.spacing = 8
        scrollView.addSubview(optionsStack)

        for (i, entry) in options.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal

            let label = UILabel()
            label.text = entry.title
            label.font = .systemFont(ofSize: 15)

            let toggle = UISwitch()
            toggle.tag = i
            toggle.isOn = Loom.debugOptions.contains(entry.option)
            toggle.addTarget(self, action: #selector(optionToggled(_:)), for: .valueChanged)

            row.addArrangedSubview(label)
            row.addArrangedSubview(toggle)
            optionsStack.addArrangedSubview(row)
        }

        scrollView.addSubview(jitterLab)
        jitterLab.onHeightChanged = { [weak self] in
            self?.view.setNeedsLayout()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        let inset: CGFloat = 16
        let width = view.bounds.width - inset * 2

        card.frame = CGRect(
            x: inset, y: 16,
            width: width, height: card.preferredHeight(for: width)
        )
        optionsStack.frame = CGRect(
            x: inset, y: card.frame.maxY + 24,
            width: width, height: CGFloat(options.count) * 39
        )
        jitterLab.frame = CGRect(
            x: inset, y: optionsStack.frame.maxY + 24,
            width: width, height: jitterLab.preferredHeight(for: width)
        )
        scrollView.contentSize = CGSize(
            width: view.bounds.width, height: jitterLab.frame.maxY + 24
        )
    }

    @objc private func optionToggled(_ sender: UISwitch) {
        let option = options[sender.tag].option
        if sender.isOn {
            Loom.debugOptions.insert(option)
        } else {
            Loom.debugOptions.remove(option)
        }
        // Overlays are applied during bindings.apply — relayout the card.
        card.setNeedsLayout()
    }
}
