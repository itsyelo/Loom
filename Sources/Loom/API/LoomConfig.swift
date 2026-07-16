import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#endif

public enum Loom {
    /// Configure the screen scale factor for pixel-aligned layout rounding.
    /// If not called, Loom auto-detects from UIScreen.main.scale on first use.
    public static func configure(screenScale: CGFloat) {
        YogaConfig.shared.setPointScaleFactor(Float(screenScale))
    }

    /// Debug options. Only effective in DEBUG builds.
    /// ```swift
    /// #if DEBUG
    /// Loom.debugOptions = [.showFrameBorders, .showKeys, .logLayoutTime]
    /// #endif
    /// ```
    nonisolated(unsafe) public static var debugOptions: LoomDebugOptions = []

    /// The measurer used by ``Text(_:maxLines:measurer:)`` nodes that don't
    /// specify one explicitly.
    ///
    /// Defaults to ``TextMeasurer/shared`` (Core Text + framesetter cache).
    /// When binding to `UILabel`, set this once at launch to make every
    /// `Text` node measure with UILabel's own layout engine — no
    /// locked-line-height discipline needed (see <doc:MultilineUILabelTips>):
    ///
    /// ```swift
    /// // application(_:didFinishLaunchingWithOptions:)
    /// Loom.defaultTextMeasurer = TextKitMeasurer.shared
    /// ```
    ///
    /// The value is captured when a `Text` node is **built**, so set it
    /// before constructing layouts (app launch is the right place).
    /// Thread-safe.
    public static var defaultTextMeasurer: any TextMeasuring {
        get { defaultMeasurerBox.value }
        set { defaultMeasurerBox.value = newValue }
    }

    private static let defaultMeasurerBox = LockedBox<any TextMeasuring>(TextMeasurer.shared)

    /// The system's preferred layout direction. Safe to call from any
    /// thread. Used by ``LoomLayout`` when its `direction` is left as
    /// ``LoomDirection/inherit`` (the default) — most apps therefore
    /// pick up RTL automatically without per-call configuration.
    ///
    /// On the main thread, returns
    /// `UIApplication.shared.userInterfaceLayoutDirection`, which
    /// reflects the application's effective display direction
    /// (including any `UIView.appearance().semanticContentAttribute`
    /// override). Off the main thread, falls back to
    /// `Locale.characterDirection(forLanguage:)` because
    /// `UIApplication.shared` is main-thread-only — this honors the
    /// user's locale but ignores app-level overrides.
    ///
    /// If your app forces a direction via `UISemanticContentAttribute`
    /// and you call Loom layout off-main, read this on main once and
    /// pass the value through `LoomLayout(width:direction:)` explicitly
    /// to avoid the dual-path divergence. See <doc:RTLSupport>.
    public static var systemDirection: LoomDirection {
        #if canImport(UIKit)
        if Thread.isMainThread {
            let dir = MainActor.assumeIsolated {
                UIApplication.shared.userInterfaceLayoutDirection
            }
            return dir == .rightToLeft ? .rtl : .ltr
        }
        #endif
        let lang: String
        if #available(iOS 16.0, macOS 13.0, *) {
            lang = Locale.current.language.languageCode?.identifier
                ?? Locale.preferredLanguages.first
                ?? "en"
        } else {
            lang = Locale.current.languageCode
                ?? Locale.preferredLanguages.first
                ?? "en"
        }
        return Locale.characterDirection(forLanguage: lang) == .rightToLeft
            ? .rtl : .ltr
    }
}

/// Minimal lock-guarded mutable box for global configuration values.
private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) {
        self.stored = value
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}

public struct LoomDebugOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Show colored borders around every view with a bound key.
    public static let showFrameBorders = LoomDebugOptions(rawValue: 1 << 0)

    /// Show key name label at the top-left corner of every bound view.
    public static let showKeys = LoomDebugOptions(rawValue: 1 << 1)

    /// Log layout calculation time to console.
    public static let logLayoutTime = LoomDebugOptions(rawValue: 1 << 2)
}
