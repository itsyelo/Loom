import UIKit

/// Bottom message-composer bar: a self-growing text field in a rounded pill
/// plus a trailing send button, with a hairline separator on top.
///
/// This view is plain Auto Layout, not a Loom-laid-out row — it isn't list
/// content, and its height is dynamic (driven by the text view's own
/// `sizeThatFits`), which is exactly the "shrink-to-fit with a live-updating
/// constraint" case Auto Layout handles more naturally than a one-shot
/// `LoomLayout.calculate()` pass (see task 05 planning note in the task file).
///
/// `ChatViewController` pins this view's `bottomAnchor` to
/// `view.keyboardLayoutGuide.topAnchor`, which is what gives keyboard-
/// following behavior (including interactive dismiss tracking) for free, and
/// which also happens to resolve the "don't sit on top of the home
/// indicator when the keyboard is hidden" requirement: per
/// `UIKeyboardLayoutGuide`, the guide's `topAnchor` coincides with
/// `view.safeAreaLayoutGuide.bottomAnchor` whenever the keyboard isn't
/// visible, so no separate safe-area handling is needed in here.
final class ChatInputBar: UIView {

    /// Fires with the trimmed, non-empty text once the user taps send. The
    /// bar clears itself (text + height) immediately after invoking this.
    var onSend: ((String) -> Void)?

    // MARK: - Sizing

    private let font = UIFont.systemFont(ofSize: 16)
    private let textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    /// Roughly how many lines the pill grows to before it starts scrolling
    /// its own content instead of growing further.
    private let maxLines = 5

    private lazy var minTextViewHeight: CGFloat = {
        ceil(font.lineHeight) + textContainerInset.top + textContainerInset.bottom
    }()

    private lazy var maxTextViewHeight: CGFloat = {
        ceil(font.lineHeight) * CGFloat(maxLines) + textContainerInset.top + textContainerInset.bottom
    }()

    // MARK: - Subviews

    private let hairlineView = UIView()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)

    private var textViewHeightConstraint: NSLayoutConstraint!

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        hairlineView.backgroundColor = .separator
        hairlineView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairlineView)

        textView.font = font
        textView.textContainerInset = textContainerInset
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .systemBackground
        textView.layer.cornerRadius = minTextViewHeight / 2
        textView.clipsToBounds = true
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        placeholderLabel.text = "Message"
        placeholderLabel.font = font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        sendButton.tintColor = .systemBlue
        sendButton.isEnabled = false
        sendButton.alpha = disabledSendAlpha
        sendButton.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sendButton)

        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: minTextViewHeight)

        NSLayoutConstraint.activate([
            hairlineView.topAnchor.constraint(equalTo: topAnchor),
            hairlineView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairlineView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairlineView.heightAnchor.constraint(equalToConstant: 1 / max(UIScreen.main.scale, 1)),

            textView.topAnchor.constraint(equalTo: hairlineView.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textViewHeightConstraint,

            sendButton.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 6),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
            sendButton.heightAnchor.constraint(equalToConstant: 30),
            sendButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: -4),

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textContainerInset.left),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textContainerInset.top),
        ])
    }

    // MARK: - Send

    private let disabledSendAlpha: CGFloat = 0.35

    @objc private func didTapSend() {
        let trimmed = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        textView.text = ""
        placeholderLabel.isHidden = false
        updateSendButtonEnabled()
        updateHeight(animated: true)

        onSend?(trimmed)
    }

    // MARK: - Auto-grow

    private func updateSendButtonEnabled() {
        let hasText = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText
        sendButton.alpha = hasText ? 1 : disabledSendAlpha
    }

    private func updateHeight(animated: Bool) {
        let fittingHeight = textView.sizeThatFits(
            CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        ).height
        let clamped = min(max(fittingHeight, minTextViewHeight), maxTextViewHeight)
        textView.isScrollEnabled = fittingHeight > maxTextViewHeight

        guard textViewHeightConstraint.constant != clamped else { return }
        textViewHeightConstraint.constant = clamped

        guard animated else {
            layoutIfNeeded()
            return
        }
        // Animate the whole hierarchy up above this view (the superview's
        // constraints are what actually move the table view / bar as a
        // unit), not just this view's own subviews.
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.superview?.layoutIfNeeded()
        }
    }
}

// MARK: - UITextViewDelegate

extension ChatInputBar: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateSendButtonEnabled()
        updateHeight(animated: true)
    }
}
