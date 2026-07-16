import yoga
import Foundation

#if os(iOS) || os(tvOS)
import UIKit
#endif

final class YogaConfig: @unchecked Sendable {
    let ref: YGConfigRef
    private let lock = NSLock()
    private var scaleConfigured = false
    private var mainCaptureScheduled = false

    init() {
        ref = YGConfigNew()
    }

    deinit {
        YGConfigFree(ref)
    }

    func setPointScaleFactor(_ factor: Float) {
        lock.lock()
        defer { lock.unlock() }
        YGConfigSetPointScaleFactor(ref, factor)
        scaleConfigured = true
    }

    /// Ensure the point scale factor is configured before a layout pass.
    ///
    /// On the main thread this reads the screen scale directly. On a
    /// background thread it must NOT block on the main thread (a caller
    /// synchronously waiting for this layout on main would deadlock), so
    /// it applies a provisional 3.0 and schedules a one-time capture of
    /// the real value on main for subsequent layouts. Apps that start
    /// layout off-main before any main-thread layout should call
    /// ``Loom/configure(screenScale:)`` at startup to skip the
    /// provisional window.
    func ensureScaleConfigured() {
        #if os(iOS) || os(tvOS)
        lock.lock()
        if scaleConfigured {
            lock.unlock()
            return
        }
        if Thread.isMainThread {
            lock.unlock()
            let scale = MainActor.assumeIsolated { Float(UIScreen.main.scale) }
            setPointScaleFactor(scale)
        } else {
            let needsSchedule = !mainCaptureScheduled
            mainCaptureScheduled = true
            YGConfigSetPointScaleFactor(ref, 3.0)
            lock.unlock()
            if needsSchedule {
                DispatchQueue.main.async { [self] in
                    lock.lock()
                    let alreadyConfigured = scaleConfigured
                    lock.unlock()
                    guard !alreadyConfigured else { return }
                    setPointScaleFactor(Float(UIScreen.main.scale))
                }
            }
        }
        #else
        setPointScaleFactor(2.0)
        #endif
    }

    static let shared = YogaConfig()
}
