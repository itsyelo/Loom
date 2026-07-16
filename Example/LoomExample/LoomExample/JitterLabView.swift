import UIKit
import Loom

/// An interactive lab for UILabel's numberOfLines-toggle jitter — the
/// "judge visually" instrument from the MultilineUILabelTips article.
///
/// The text deliberately mixes 28pt headline glyphs into 14pt body copy:
/// the worst case, where the first line jumps 3–6pt on collapse/expand.
/// Tap the text repeatedly with the lock OFF to see it; flip the switch
/// (one `lockLineHeight(toTallestOf:)` call) and it holds still.
final class JitterLabView: UIView {

    private enum Key: String, LoomKey {
        case title, hint, text, lockLabel, lockSwitch
        var loomKeyValue: String { rawValue }
    }

    /// Notifies the owning controller that the preferred height changed
    /// (collapse/expand or lock toggle both change it).
    var onHeightChanged: (() -> Void)?

    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let textLabel = UILabel()
    private let lockLabel = UILabel()
    private let lockSwitch = UISwitch()

    private var isExpanded = false
    private var isLocked = false

    private let bodyFont = UIFont.systemFont(ofSize: 14)
    private let headlineFont = UIFont.boldSystemFont(ofSize: 28)

    private let titleAttr = NSAttributedString(string: "Jitter Lab", attributes: [
        .font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: UIColor.label,
    ])
    private let hintAttr = NSAttributedString(
        string: "Tap the text below to collapse/expand. Lock OFF: the first "
            + "line jumps a few points (28pt glyphs in 14pt body — the worst "
            + "case). Lock ON: it holds still.",
        attributes: [
            .font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.secondaryLabel,
        ]
    )
    private let lockLabelAttr = NSAttributedString(
        string: "lockLineHeight(toTallestOf:)",
        attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: UIColor.label,
        ]
    )

    private lazy var bindings = LoomBindings {
        LoomBind(Key.title, to: titleLabel)
        LoomBind(Key.hint, to: hintLabel)
        LoomBind(Key.text, to: textLabel)
        LoomBind(Key.lockLabel, to: lockLabel)
        LoomBind(Key.lockSwitch, to: lockSwitch)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16

        titleLabel.attributedText = titleAttr
        hintLabel.attributedText = hintAttr
        hintLabel.numberOfLines = 0

        textLabel.numberOfLines = 2
        textLabel.isUserInteractionEnabled = true
        textLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(toggleExpanded))
        )

        lockLabel.attributedText = lockLabelAttr
        lockSwitch.addTarget(self, action: #selector(lockChanged), for: .valueChanged)

        for v in [titleLabel, hintLabel, textLabel, lockLabel, lockSwitch] as [UIView] {
            addSubview(v)
        }
        refreshText()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The demo string. The ONLY difference between locked and unlocked
    /// is the one-line library call.
    private func bodyAttr() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        if isLocked {
            style.lockLineHeight(toTallestOf: [bodyFont, headlineFont])
        }
        let text = "HEADLINE glyphs at 28pt inside 14pt body copy. Toggling "
            + "numberOfLines flips UILabel between its two vertical alignment "
            + "modes — keep your eye on this first line while tapping. A few "
            + "more sentences of filler give the expanded state enough lines "
            + "to make the difference easy to catch."
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: bodyFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ])
        attr.addAttribute(.font, value: headlineFont, range: NSRange(location: 0, length: 8))
        return attr
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        bindings.apply(loomLayout(content: content))
    }

    func preferredHeight(for width: CGFloat) -> CGFloat {
        LoomLayout(width: width, content: content).calculateHeight()
    }

    @LoomBuilder private func content() -> [LoomNode] {
        VStack(spacing: 10) {
            Text(titleAttr).key(Key.title)
            Text(hintAttr).key(Key.hint)
            Text(bodyAttr(), maxLines: isExpanded ? nil : 2).key(Key.text)
            HStack(align: .center) {
                Text(lockLabelAttr).key(Key.lockLabel)
                Spacer(0).flex(grow: 1)
                Fixed(width: 51, height: 31).key(Key.lockSwitch)
            }.margin(.top, 4)
        }.padding(16)
    }

    @objc private func toggleExpanded() {
        isExpanded.toggle()
        refreshText()
    }

    @objc private func lockChanged() {
        isLocked = lockSwitch.isOn
        refreshText()
    }

    private func refreshText() {
        textLabel.attributedText = bodyAttr()
        // Mirror Loom's maxLines — see MultilineUILabelTips.
        textLabel.numberOfLines = isExpanded ? 0 : 2
        setNeedsLayout()
        onHeightChanged?()
    }
}
