import UIKit

// MARK: - MockChat

/// Deterministic full conversation timeline plus a paging API over it.
///
/// The whole ~600-message timeline is generated once, from a fixed anchor
/// `Date` (never `Date()`), so the demo looks identical on every launch —
/// no clock-dependent drift between the initial screenful and a later
/// "load earlier history" page. `initialHistory` and `earlierPage` both
/// slice the same backing array rather than generating pages
/// independently, which keeps ids and ordering trivially consistent.
enum MockChat {

    // MARK: Participants

    static let me = ChatUser(
        id: "user-me",
        name: "Me",
        avatarURL: avatarURL(seed: "photo-1500648767791-00dcc994a43e"),
        isMe: true
    )

    static let bot = ChatUser(
        id: "user-nova",
        name: "Nova",
        avatarURL: avatarURL(seed: "photo-1438761681033-6461ffad8d80"),
        isMe: false
    )

    // MARK: Paging API

    /// The most recent `count` messages, oldest-first — ready to hand
    /// straight to a bottom-anchored table as the initial screenful.
    static func initialHistory(count: Int) -> [ChatMessage] {
        Array(fullTimeline.suffix(count))
    }

    /// Up to `limit` messages immediately preceding `id`, oldest-first.
    /// Returns `nil` when `id` is already the first message in the
    /// conversation, i.e. there is no earlier page left to fetch.
    static func earlierPage(before id: String, limit: Int) -> [ChatMessage]? {
        guard let index = fullTimeline.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        let start = max(0, index - limit)
        return Array(fullTimeline[start..<index])
    }

    // MARK: - Timeline generation

    private static let dayCount = 15

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Fixed anchor so every timestamp below is derived arithmetically
    /// instead of from `Date()` — this is what makes the timeline
    /// byte-for-byte identical across runs.
    private static let anchorDate: Date = {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9, minute: 0))!
    }()

    private static let dateSeparatorFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    /// `true` marks a slot as sent by "me"; the pattern is deliberately
    /// bursty (runs of 1-3 from the same sender) rather than strict
    /// alternation, so the rendered timeline reads like a real chat.
    private static let senderPattern: [Bool] = [
        false, false, true, true, false, true, false, false, true, false, true, true, true, false,
    ]

    private static let textPool: [String] = [
        "Morning! ☀️ Ready for the demo today?",
        "早上好呀，早点出发比较稳 🚗",
        "Sure — see you at 9. Coffee first? ☕️",
        "当然可以，老地方见 😄",
        "Here's the snippet I mentioned:\n```\nlet layout = LoomLayout(width: 320) { ... }.calculate()\n```\nRuns fully off the main thread.",
        "Nice, that's exactly the API I needed. Docs: https://github.com/itsyelo/Loom",
        "刚看了一下文档，写得很清楚。https://github.com/itsyelo/Loom 这个 pipeline 的思路很赞 👍",
        "Quick question — does `Text(attr, maxLines:)` clip or ellipsize by default?",
        "Ellipsizes with `.byTruncatingTail` unless you override the line break mode.",
        "Got it, thanks! 🙏",
        "长消息测试一下：\n第一行内容\n第二行内容，带一点 emoji 😊\n第三行还有一个链接 https://example.com/reference\n最后附上一段 `inline code` 看看排版效果。",
        "😂😂😂 that's hilarious",
        "lol",
        "Sent you the file, check your email 📎",
        "Got it, thanks a lot! Will review after lunch 🍜",
        "顺便问一下，下午的会议改到几点了？",
        "改到 3 点了，地点不变 📍",
        "Perfect, see you then.",
        "Reminder: standup in 10 minutes ⏰",
        "On my way 🏃",
        "Can you take a look at this PR when you get a chance? https://github.com/itsyelo/Loom/pull/42",
        "Sure, I'll review it tonight. `LGTM` pending the layout tests passing.",
        "Appreciate it 🙌",
        "Happy Friday! 🎉 Any weekend plans?",
        "周末打算休息一下，你呢？",
        "Same here, maybe a short hike 🥾",
    ]

    private static let imagePool: [(id: String, width: CGFloat, height: CGFloat)] = [
        ("photo-1519681393784-d120267933ba", 1600, 1067),  // landscape
        ("photo-1441974231531-c6227db76b6e", 1067, 1600),  // portrait
        ("photo-1470770841072-f978cf4d019e", 1200, 1200),  // square
        ("photo-1500534623283-312aade485b7", 1600, 900),   // wide landscape
        ("photo-1506905925346-21bda4d32df4", 900, 1600),   // tall portrait
        ("photo-1441716844725-09cedc13a4e7", 1400, 933),   // landscape
    ]

    /// The full conversation, oldest-first. Built once and reused by both
    /// paging entry points.
    static let fullTimeline: [ChatMessage] = generateTimeline()

    private static func generateTimeline() -> [ChatMessage] {
        var messages: [ChatMessage] = []
        var sequence = 0
        var day = anchorDate

        func nextID() -> String {
            defer { sequence += 1 }
            return "msg-\(sequence)"
        }

        for dayIndex in 0..<dayCount {
            messages.append(
                ChatMessage(
                    id: nextID(),
                    sender: nil,
                    timestamp: day,
                    kind: .system(dateSeparatorFormatter.string(from: day)),
                    status: .read
                )
            )

            // A single one-off notice at the very start of the
            // conversation, rather than on every day.
            if dayIndex == 0 {
                messages.append(
                    ChatMessage(
                        id: nextID(),
                        sender: nil,
                        timestamp: day.addingTimeInterval(30),
                        kind: .system("🔒 Messages in this conversation are end-to-end encrypted."),
                        status: .read
                    )
                )
            }

            let messagesToday = 28 + (dayIndex * 7) % 24  // 28...51, deterministic per day
            var secondsIntoDay: TimeInterval = 90

            for slot in 0..<messagesToday {
                let isMe = senderPattern[(dayIndex + slot) % senderPattern.count]
                let sender = isMe ? me : bot
                let timestamp = day.addingTimeInterval(secondsIntoDay)
                secondsIntoDay += TimeInterval(20 + (slot * 13) % 90)  // 20...109s between messages

                let kind = messageKind(dayIndex: dayIndex, slot: slot)
                let status: DeliveryStatus = isMe ? deliveryStatus(dayIndex: dayIndex, slot: slot) : .sent

                messages.append(
                    ChatMessage(id: nextID(), sender: sender, timestamp: timestamp, kind: kind, status: status)
                )
            }

            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        return messages
    }

    /// Roughly 1 in 9 messages is an image; never the first slot of the
    /// day, so every day's cluster opens with text.
    private static func messageKind(dayIndex: Int, slot: Int) -> ChatMessageKind {
        if slot > 0 && (dayIndex * 5 + slot) % 9 == 0 {
            let image = imagePool[(dayIndex + slot) % imagePool.count]
            return .image(
                url: imageURL(id: image.id, width: image.width, height: image.height),
                size: CGSize(width: image.width, height: image.height)
            )
        }
        return .text(textPool[(dayIndex * 11 + slot * 3) % textPool.count])
    }

    private static func deliveryStatus(dayIndex: Int, slot: Int) -> DeliveryStatus {
        (dayIndex + slot) % 4 == 0 ? .sent : .read
    }

    private static func avatarURL(seed: String) -> URL {
        URL(string: "https://images.unsplash.com/\(seed)?w=96&h=96&fit=crop&crop=faces")!
    }

    private static func imageURL(id: String, width: CGFloat, height: CGFloat) -> URL {
        URL(string: "https://images.unsplash.com/\(id)?w=\(Int(width))&h=\(Int(height))&fit=crop")!
    }
}
