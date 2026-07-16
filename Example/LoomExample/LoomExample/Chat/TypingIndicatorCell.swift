import UIKit
import SDWebImage

/// The "bot is typing" row — the one table row that is deliberately *outside*
/// the Loom pipeline (see the planning decision at the top of task 06's task
/// file). It never carries a `ChatMessageVM`, has no `LoomLayout`/
/// `LayoutResult`, and is positioned with plain frame math in
/// `layoutSubviews` — a fixed-height row with three pulsing dots doesn't
/// need measurement, so routing it through Loom would just be ceremony.
///
/// `ChatViewController` treats this as an always-last, boolean-gated row
/// (`isTypingIndicatorVisible`); it is inserted/deleted like any other table
/// row, but its height (`rowHeight`) is a compile-time constant rather than
/// something read off a view model.
final class TypingIndicatorCell: UITableViewCell {
    static let reuseID = "TypingIndicatorCell"
    /// Fixed row height — no measurement, no Loom layout, just a constant
    /// `heightForRowAt` can return directly for this row.
    static let rowHeight: CGFloat = 56

    private let avatarView = UIImageView()
    private let bubbleView = UIView()
    private let dots: [UIView] = (0..<3).map { _ in UIView() }

    private static let avatarSize = ChatLayout.avatarSize
    private static let dotSize: CGFloat = 7
    private static let dotSpacing: CGFloat = 5
    private static let bubbleHPadding: CGFloat = 14
    private static let bubbleVPadding: CGFloat = 12
    private static let rowHorizontalPadding: CGFloat = 12
    private static let avatarGap: CGFloat = 8
    private static let pulseAnimationKey = "typingDotPulse"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        avatarView.layer.cornerRadius = Self.avatarSize / 2
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.backgroundColor = .systemGray5
        avatarView.sd_setImage(with: MockChat.bot.avatarURL)

        bubbleView.backgroundColor = .secondarySystemBackground
        bubbleView.layer.cornerRadius = 16

        for dot in dots {
            dot.backgroundColor = .tertiaryLabel
            dot.layer.cornerRadius = Self.dotSize / 2
            bubbleView.addSubview(dot)
        }

        contentView.addSubview(avatarView)
        contentView.addSubview(bubbleView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = contentView.bounds.height

        avatarView.frame = CGRect(
            x: Self.rowHorizontalPadding,
            y: (height - Self.avatarSize) / 2,
            width: Self.avatarSize,
            height: Self.avatarSize
        )

        let bubbleWidth = Self.bubbleHPadding * 2 + Self.dotSize * 3 + Self.dotSpacing * 2
        let bubbleHeight = Self.bubbleVPadding * 2 + Self.dotSize
        bubbleView.frame = CGRect(
            x: avatarView.frame.maxX + Self.avatarGap,
            y: (height - bubbleHeight) / 2,
            width: bubbleWidth,
            height: bubbleHeight
        )

        for (index, dot) in dots.enumerated() {
            let x = Self.bubbleHPadding + CGFloat(index) * (Self.dotSize + Self.dotSpacing)
            dot.frame = CGRect(x: x, y: Self.bubbleVPadding, width: Self.dotSize, height: Self.dotSize)
        }
    }

    /// Cell reuse (this row is deleted/re-inserted every time the indicator
    /// toggles, and the table's reuse pool can hand back the same instance)
    /// detaches the cell from the window while it's out of circulation, and
    /// CA's implicit teardown on detach can drop the repeating animations.
    /// Restarting from `didMoveToWindow` (rather than `configure`, which
    /// this cell doesn't even have — there's no view model to bind) covers
    /// both the first display and every subsequent reuse.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    private func startAnimating() {
        for (index, dot) in dots.enumerated() {
            guard dot.layer.animation(forKey: Self.pulseAnimationKey) == nil else { continue }
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = 0.75
            animation.toValue = 1.15
            animation.duration = 0.5
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // Stagger each dot's start so the three pulse in sequence
            // rather than in unison.
            animation.beginTime = CACurrentMediaTime() + Double(index) * 0.15
            dot.layer.add(animation, forKey: Self.pulseAnimationKey)
        }
    }

    private func stopAnimating() {
        for dot in dots {
            dot.layer.removeAnimation(forKey: Self.pulseAnimationKey)
        }
    }
}
