import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

/// A thread-safe LRU cache for ``LayoutResult`` values, keyed by a
/// caller-supplied `Hashable` id plus the layout width.
///
/// Ids are compared via `Hashable` equality (wrapped in `AnyHashable`),
/// so distinct ids never collide regardless of their string description,
/// and ``invalidate(id:)`` removes exactly the entries for that id.
///
/// When the entry count exceeds `countLimit`, the least recently used
/// entries are evicted. On iOS/tvOS the cache also empties itself on
/// `UIApplication.didReceiveMemoryWarningNotification`.
public final class LayoutCache: @unchecked Sendable {
    private struct Key: Hashable {
        let id: AnyHashable
        let width: CGFloat
    }

    private final class Entry {
        let result: LayoutResult
        var tick: UInt64
        init(result: LayoutResult, tick: UInt64) {
            self.result = result
            self.tick = tick
        }
    }

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var tick: UInt64 = 0
    private let countLimit: Int
    private var memoryWarningObserver: (any NSObjectProtocol)?

    public init(countLimit: Int = 200) {
        self.countLimit = max(1, countLimit)
        #if canImport(UIKit)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidateAll()
        }
        #endif
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func get(id: some Hashable, width: CGFloat) -> LayoutResult? {
        let key = Key(id: AnyHashable(id), width: width)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        tick += 1
        entry.tick = tick
        return entry.result
    }

    public func set(id: some Hashable, width: CGFloat, result: LayoutResult) {
        let key = Key(id: AnyHashable(id), width: width)
        lock.lock()
        defer { lock.unlock() }
        tick += 1
        entries[key] = Entry(result: result, tick: tick)
        evictIfNeeded()
    }

    /// Invalidate all cached layouts for the given id (any width).
    public func invalidate(id: some Hashable) {
        let target = AnyHashable(id)
        lock.lock()
        defer { lock.unlock() }
        for key in entries.keys where key.id == target {
            entries.removeValue(forKey: key)
        }
    }

    public func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    /// Remove least-recently-used entries until within `countLimit`.
    /// Must be called with `lock` held.
    private func evictIfNeeded() {
        while entries.count > countLimit {
            guard let oldest = entries.min(by: { $0.value.tick < $1.value.tick }) else { return }
            entries.removeValue(forKey: oldest.key)
        }
    }

    /// Convenience: get cached or calculate and store.
    public func resolve(
        id: some Hashable,
        width: CGFloat,
        builder: () -> LoomLayout
    ) -> LayoutResult {
        if let cached = get(id: id, width: width) {
            return cached
        }
        let result = builder().calculate()
        set(id: id, width: width, result: result)
        return result
    }

    /// Convenience: get cached height or calculate and store.
    public func height(
        for id: some Hashable,
        width: CGFloat,
        builder: () -> LoomLayout
    ) -> CGFloat {
        resolve(id: id, width: width, builder: builder).height
    }

    /// Pre-calculate on a background queue. Results are stored in cache.
    public func precalculate(
        id: some Hashable & Sendable,
        width: CGFloat,
        on queue: DispatchQueue = .global(),
        builder: @Sendable @escaping () -> LoomLayout
    ) {
        queue.async { [self] in
            let result = builder().calculate()
            self.set(id: id, width: width, result: result)
        }
    }

    /// Invalidate, recalculate, and store. Returns the new result.
    @discardableResult
    public func update(
        id: some Hashable,
        width: CGFloat,
        builder: () -> LoomLayout
    ) -> LayoutResult {
        invalidate(id: id)
        return resolve(id: id, width: width, builder: builder)
    }

    // MARK: - Async API

    /// Async resolve: returns cached result or calculates on a background thread.
    @available(iOS 13.0, macOS 10.15, *)
    public func resolveAsync(
        id: some Hashable & Sendable,
        width: CGFloat,
        builder: @Sendable @escaping () -> LoomLayout
    ) async -> LayoutResult {
        if let cached = get(id: id, width: width) {
            return cached
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let result = builder().calculate()
                self.set(id: id, width: width, result: result)
                continuation.resume(returning: result)
            }
        }
    }

    /// Batch async pre-calculation using TaskGroup.
    @available(iOS 13.0, macOS 10.15, *)
    public func precalculateAsync<ID: Hashable & Sendable>(
        ids: [ID],
        width: CGFloat,
        builder: @Sendable @escaping (ID) -> LoomLayout
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                guard get(id: id, width: width) == nil else { continue }
                group.addTask { [self] in
                    let result = builder(id).calculate()
                    self.set(id: id, width: width, result: result)
                }
            }
        }
    }
}
