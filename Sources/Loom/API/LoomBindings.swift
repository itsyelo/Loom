#if canImport(UIKit)
import UIKit

/// A single key-to-view binding.
public struct LoomBind {
    let keyValue: String
    weak var view: UIView?

    public init(_ key: some LoomKey, to view: UIView) {
        self.keyValue = key.loomKeyValue
        self.view = view
    }
}

/// A collection of key-to-view bindings that can apply a LayoutResult
/// to all bound views in one call.
public struct LoomBindings {
    private var entries: [LoomBind]

    public init(@LoomBindingsBuilder _ builder: () -> [LoomBind]) {
        self.entries = builder()
    }

    /// Apply all bound frames from the given result.
    /// Views whose key is not found are skipped. Deallocated views are skipped.
    public func apply(_ result: LayoutResult?) {
        guard let result else { return }
        for entry in entries {
            guard let view = entry.view,
                  let frame = result.frames[entry.keyValue] else { continue }
            view.frame = frame

            #if DEBUG
            validateTextFrame(of: view, frame: frame, key: entry.keyValue)
            applyDebugOverlay(to: view, key: entry.keyValue)
            #endif
        }
    }

    #if DEBUG
    /// Warn (once per key) when a bound UILabel needs more height than its
    /// measured frame provides — the label will truncate a line early.
    ///
    /// This is the loud version of a silent failure: the usual cause is a
    /// measurement/rendering mismatch (Core Text metrics vs UILabel's
    /// TextKit). Fix by setting `Loom.defaultTextMeasurer =
    /// TextKitMeasurer.shared`, or lock the string's line height — see
    /// <doc:MultilineUILabelTips>. If the height cap is intentional
    /// (`.maxSize(height:)`), mirror it via `numberOfLines` to silence.
    private func validateTextFrame(of view: UIView, frame: CGRect, key: String) {
        guard let label = view as? UILabel,
              frame.width > 0, frame.height > 0,
              let text = label.attributedText, text.length > 0 else { return }

        let needed = label.sizeThatFits(
            CGSize(width: frame.width, height: .greatestFiniteMagnitude)
        )
        guard needed.height - frame.height > 1.0 else { return }

        MainActor.assumeIsolated {
            guard !Self.warnedTextFrameKeys.contains(key) else { return }
            Self.warnedTextFrameKeys.insert(key)
            print(String(
                format: "[Loom] ⚠️ Text frame for key '%@' is %.1fpt shorter than "
                    + "UILabel needs (%.1f < %.1f) — the last line will be cut. "
                    + "Likely a measurement/rendering mismatch: set "
                    + "Loom.defaultTextMeasurer = TextKitMeasurer.shared, or lock "
                    + "the string's line height. See the MultilineUILabelTips article. "
                    + "(Intentional cap? Mirror it via numberOfLines to silence.)",
                key, needed.height - frame.height, frame.height, needed.height
            ))
        }
    }

    @MainActor private static var warnedTextFrameKeys = Set<String>()
    #endif

    /// Apply frames relative to a container key.
    public func apply(_ result: LayoutResult?, relativeTo containerKey: some LoomKey) {
        guard let result,
              let relative = result.relative(to: containerKey) else { return }
        apply(relative)
    }

    /// Apply frames with animation.
    public func applyAnimated(
        _ result: LayoutResult?,
        duration: TimeInterval = 0.25,
        completion: (() -> Void)? = nil
    ) {
        UIView.animate(withDuration: duration, animations: {
            self.apply(result)
        }, completion: { _ in
            completion?()
        })
    }

    #if DEBUG
    private static let debugBorderTag = 0x4C_4F4F_4D // "LOOM" in hex
    private static let debugLabelTag = 0x4C_4F4F_4E  // "LOON"

    private func applyDebugOverlay(to view: UIView, key: String) {
        let options = Loom.debugOptions
        guard !options.isEmpty else {
            removeDebugOverlay(from: view)
            return
        }

        if options.contains(.showFrameBorders) {
            view.layer.borderWidth = 1
            view.layer.borderColor = debugColor(for: key).cgColor
        } else {
            view.layer.borderWidth = 0
        }

        if options.contains(.showKeys) {
            let label: UILabel
            if let existing = view.viewWithTag(Self.debugLabelTag) as? UILabel {
                label = existing
            } else {
                label = UILabel()
                label.tag = Self.debugLabelTag
                label.font = .systemFont(ofSize: 8, weight: .bold)
                label.textAlignment = .center
                label.layer.cornerRadius = 2
                label.clipsToBounds = true
                view.addSubview(label)
            }
            let color = debugColor(for: key)
            label.text = " \(key) "
            label.textColor = .white
            label.backgroundColor = color.withAlphaComponent(0.8)
            label.sizeToFit()
            label.frame.origin = .zero
        } else if let existing = view.viewWithTag(Self.debugLabelTag) {
            existing.removeFromSuperview()
        }
    }

    private func removeDebugOverlay(from view: UIView) {
        view.layer.borderWidth = 0
        view.viewWithTag(Self.debugLabelTag)?.removeFromSuperview()
    }

    private func debugColor(for key: String) -> UIColor {
        let hue = CGFloat(abs(key.hashValue) % 360) / 360.0
        return UIColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1.0)
    }
    #endif
}

// MARK: - Result Builder

@resultBuilder
public struct LoomBindingsBuilder {
    public static func buildBlock(_ components: [LoomBind]...) -> [LoomBind] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: LoomBind) -> [LoomBind] {
        [expression]
    }

    public static func buildOptional(_ component: [LoomBind]?) -> [LoomBind] {
        component ?? []
    }

    public static func buildEither(first component: [LoomBind]) -> [LoomBind] {
        component
    }

    public static func buildEither(second component: [LoomBind]) -> [LoomBind] {
        component
    }
}
#endif
