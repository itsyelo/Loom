import Foundation

// MARK: - BotScript

/// Deterministic script source for the bot's replies, used by the
/// streaming-reply demo (task 06).
///
/// `reply(to:)` is a pure function of its input: the same user text always
/// selects the same canned reply. Selection is done with a small FNV-1a
/// style hash rather than `String.hashValue` — Swift randomizes string
/// hashing per process launch for hash-flooding resistance, which would
/// make "same input -> same reply" unreliable across runs of the app.
enum BotScript {
    private static let replies: [String] = [
        "Got it — give me a second to look that up. 🤔",
        "That's a great question! Short answer: yes, and here's why.\n\nLoom pre-computes the whole layout tree off the main thread, so `heightForRowAt` never has to guess — it just reads a value that's already sitting on the view model.",
        "😄 lol, fair point.",
        "Sure thing, sending it over now 📎",
        "Here's a quick example:\n```\nlet result = LoomLayout(width: width) {\n    Text(attr, maxLines: 3)\n}.calculate()\n```\nThat call is thread-safe and can run anywhere.",
        "Not sure yet — let me check and get back to you.",
        "Absolutely, 100% agree with that. 👍",
        // This long CJK reply once rendered with its last line visually
        // truncated: without a locked line height, the measuring pass (SF
        // metrics) and UILabel's rendering pass (PingFang fallback metrics)
        // disagreed on line geometry. Fixed by lockLineHeight in
        // ChatMessageContent.bodyAttr — kept long here as a regression case.
        "打字有点慢，稍等一下我把这段说清楚：这个方案的核心在于把布局计算完全挪到后台线程，主线程只做一次性的属性读取，所以永远不会出现临时测量导致的掉帧。",
        "Yep, that should work. Let me know if it doesn't! 🙌",
        "Interesting — I hadn't thought about that angle before.",
    ]

    /// Deterministically selects one of the fixed replies for `userText`.
    static func reply(to userText: String) -> String {
        guard !replies.isEmpty else { return "" }
        let index = Int(stableHash(userText) % UInt64(replies.count))
        return replies[index]
    }

    /// Slices `reply` into small runs of 2-6 characters so a caller can
    /// "type" the reply out incrementally (see task 06's typing indicator
    /// / streaming publish). Splits on `Character` (grapheme cluster)
    /// boundaries so multi-scalar emoji are never torn in half.
    static func chunks(of reply: String) -> [String] {
        let characters = Array(reply)
        guard !characters.isEmpty else { return [] }

        // Fixed, content-independent cycle of chunk sizes — all within the
        // required 2-6 range — so chunking stays deterministic too.
        let sizePattern = [3, 5, 2, 4, 6, 3, 4, 2, 5]

        var result: [String] = []
        var start = 0
        var patternIndex = 0
        while start < characters.count {
            let size = sizePattern[patternIndex % sizePattern.count]
            let end = min(start + size, characters.count)
            result.append(String(characters[start..<end]))
            start = end
            patternIndex += 1
        }
        return result
    }

    /// FNV-1a over UTF-8 bytes — stable across process launches, unlike
    /// `String.hashValue` (which Swift seeds randomly per run).
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01B3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
