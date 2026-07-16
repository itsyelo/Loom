import UIKit
import Loom

/// Tab 3 — a gallery of layout capabilities. The ENTIRE scroll content is
/// described by one `LoomLayout`; every colored box / label is a plain
/// view bound to a `String` key. Rotate or resize to watch the single
/// layout pass re-place everything.
final class ShowcaseViewController: UIViewController {

    private let scrollView = UIScrollView()
    /// Creation order == z-order (backgrounds first, children above).
    private var orderedViews: [(key: String, view: UIView)] = []
    private var lastLaidOutWidth: CGFloat = 0

    private static let zAlignments: [(name: String, align: LoomZAlignment)] = [
        ("topLeft", .topLeft), ("topCenter", .topCenter), ("topRight", .topRight),
        ("centerLeft", .centerLeft), ("center", .center), ("centerRight", .centerRight),
        ("bottomLeft", .bottomLeft), ("bottomCenter", .bottomCenter), ("bottomRight", .bottomRight),
    ]
    private static let chips = [
        "Swift", "Yoga", "Flexbox", "RTL", "Core Text",
        "UIKit", "Async", "60 FPS", "Low-end", "Wrap",
    ]
    private static let justifies: [(name: String, justify: LoomJustify)] = [
        ("start", .start), ("center", .center), ("between", .spaceBetween),
    ]

    // Attributed strings for every Text node, built once.
    private let titleAttrs: [NSAttributedString]
    private let captionAbs: NSAttributedString
    private let captionPad: NSAttributedString
    private let chipAttrs: [NSAttributedString]
    private let padTextAttr: NSAttributedString

    init() {
        func title(_ s: String) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [
                .font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: UIColor.label,
            ])
        }
        func caption(_ s: String) -> NSAttributedString {
            // No paragraph-style discipline needed: the app sets
            // Loom.defaultTextMeasurer = TextKitMeasurer.shared at launch,
            // so measurement matches UILabel natively.
            NSAttributedString(string: s, attributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.secondaryLabel,
            ])
        }
        titleAttrs = [
            "ZStack — 9 alignments (wraps)",
            "Absolute position — explicit 0 pins the edge",
            "HStack wrap — measured chips",
            "Leaf padding — key = content area",
            "aspectRatio — 16:9 and 1:1, widths from flex",
            "justify — main-axis distribution",
        ].map(title)
        captionAbs = caption("The container centers its child (justify/align .center); "
            + "the red dot is pinned top-right by .position(top: 0, right: 0).")
        captionPad = caption("The label is bound to the Text key — it lands on the "
            + "content area inside the padded (tinted) wrapper.")
        chipAttrs = Self.chips.map {
            NSAttributedString(string: $0, attributes: [
                .font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor.white,
            ])
        }
        padTextAttr = NSAttributedString(
            string: "Text(...).padding(12).key(...) — Loom auto-wraps padded leaves; "
                + "the key's frame is the text itself, not the padded box.",
            attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.label,
            ]
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - View setup

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Showcase"
        view.backgroundColor = .systemBackground
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        createBoundViews()
    }

    private func createBoundViews() {
        // §1 ZStack tiles
        addLabel("title-1", titleAttrs[0])
        for i in 0..<9 {
            addBox("z\(i)-bg", color: .systemGray5, corner: 10)
            addBox("z\(i)-dot", color: .systemPink, corner: 8)
        }
        // §2 absolute position (background first, children above)
        addLabel("title-2", titleAttrs[1])
        addLabel("caption-2", captionAbs, lines: 0)
        addBox("abs-box", color: .systemGray6, corner: 10, border: true)
        addBox("abs-center", color: .systemTeal, corner: 6, text: "centered")
        addBox("abs-dot", color: .systemRed, corner: 11)
        // §3 wrap chips
        addLabel("title-3", titleAttrs[2])
        for (i, attr) in chipAttrs.enumerated() {
            addBox("chip\(i)", color: .systemIndigo, corner: 14, attrText: attr)
        }
        // §4 leaf padding
        addLabel("title-4", titleAttrs[3])
        addLabel("caption-4", captionPad, lines: 0)
        addBox("pad-box", color: UIColor.systemYellow.withAlphaComponent(0.25), corner: 10)
        addLabel("pad-text", padTextAttr, lines: 0)
        // §5 aspect ratio
        addLabel("title-5", titleAttrs[4])
        addBox("ar-a", color: .systemBlue, corner: 10, text: "16 : 9")
        addBox("ar-b", color: .systemOrange, corner: 10, text: "1 : 1")
        // §6 justify rows
        addLabel("title-6", titleAttrs[5])
        for (r, j) in Self.justifies.enumerated() {
            addBox("j\(r)-bg", color: .systemGray6, corner: 8)
            for c in 0..<3 {
                addBox("j\(r)-\(c)", color: .systemGreen, corner: 6,
                       text: c == 0 ? j.name : nil)
            }
        }
    }

    private func addBox(
        _ key: String, color: UIColor, corner: CGFloat,
        border: Bool = false, text: String? = nil,
        attrText: NSAttributedString? = nil
    ) {
        let label = UILabel()
        label.backgroundColor = color
        label.layer.cornerRadius = corner
        label.clipsToBounds = true
        label.textAlignment = .center
        label.font = .boldSystemFont(ofSize: 11)
        label.textColor = .white
        label.text = text
        if let attrText { label.attributedText = attrText }
        if border {
            label.layer.borderWidth = 1
            label.layer.borderColor = UIColor.separator.cgColor
        }
        orderedViews.append((key, label))
        scrollView.addSubview(label)
    }

    private func addLabel(_ key: String, _ attr: NSAttributedString, lines: Int = 1) {
        let label = UILabel()
        label.attributedText = attr
        label.numberOfLines = lines
        orderedViews.append((key, label))
        scrollView.addSubview(label)
    }

    // MARK: - Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        let width = view.bounds.width
        guard width > 0, width != lastLaidOutWidth else { return }
        lastLaidOutWidth = width

        let result = buildLayout(width: width).calculate()
        for (key, boundView) in orderedViews {
            boundView.frame = result.frame(for: key) ?? .zero
        }
        scrollView.contentSize = CGSize(width: width, height: result.height)
    }

    private func buildLayout(width: CGFloat) -> LoomLayout {
        LoomLayout(width: width) {
            VStack(spacing: 28) {
                // §1 ZStack alignments in a wrapping row
                VStack(spacing: 10) {
                    Text(titleAttrs[0]).key("title-1")
                    HStack(spacing: 12, lineSpacing: 12, wrap: .wrap) {
                        for (i, entry) in Self.zAlignments.enumerated() {
                            ZStack(alignment: entry.align) {
                                Fixed(width: 76, height: 76).key("z\(i)-bg")
                                Fixed(width: 16, height: 16).key("z\(i)-dot")
                            }
                        }
                    }
                }

                // §2 absolute position with explicit-zero offsets
                VStack(spacing: 10) {
                    Text(titleAttrs[1]).key("title-2")
                    Text(captionAbs).key("caption-2")
                    VStack(justify: .center, align: .center) {
                        Fixed(width: 120, height: 32).key("abs-center")
                        Fixed(width: 22, height: 22)
                            .position(type: .absolute, top: 0, right: 0)
                            .key("abs-dot")
                    }.size(height: 96).key("abs-box")
                }

                // §3 wrapping measured chips
                VStack(spacing: 10) {
                    Text(titleAttrs[2]).key("title-3")
                    HStack(spacing: 8, lineSpacing: 8, wrap: .wrap) {
                        for (i, attr) in chipAttrs.enumerated() {
                            Self.chipNode(attr).key("chip\(i)")
                        }
                    }
                }

                // §4 padded leaf — key lands on the content area
                VStack(spacing: 10) {
                    Text(titleAttrs[3]).key("title-4")
                    Text(captionPad).key("caption-4")
                    VStack {
                        Text(padTextAttr).padding(12).key("pad-text")
                    }.key("pad-box")
                }

                // §5 aspect ratio driven by flexible widths
                VStack(spacing: 10) {
                    Text(titleAttrs[4]).key("title-5")
                    HStack(spacing: 12) {
                        VStack {}.flex(grow: 2).aspectRatio(16.0 / 9.0).key("ar-a")
                        VStack {}.flex(grow: 1).aspectRatio(1).key("ar-b")
                    }
                }

                // §6 justify variants
                VStack(spacing: 10) {
                    Text(titleAttrs[5]).key("title-6")
                    for (r, entry) in Self.justifies.enumerated() {
                        HStack(spacing: 8, justify: entry.justify) {
                            for c in 0..<3 {
                                Fixed(width: 72, height: 26).key("j\(r)-\(c)")
                            }
                        }.padding(6).key("j\(r)-bg")
                    }
                }
            }.padding(16)
        }
    }

    private static func chipNode(_ attr: NSAttributedString) -> LoomNode {
        Measured { _, _ in
            let textSize = TextMeasurer.measure(
                attr, maxWidth: .greatestFiniteMagnitude, maxHeight: 28
            )
            return CGSize(width: textSize.width + 20, height: 28)
        }
    }
}
