import UIKit

// MARK: - ChatUser

/// A participant in the conversation — either "me" (the current user, right-
/// aligned bubbles) or the other party (left-aligned bubbles, avatar shown).
struct ChatUser {
    let id: String
    let name: String
    let avatarURL: URL
    let isMe: Bool
}

// MARK: - DeliveryStatus

/// Delivery state for a message sent by "me". The cell maps this to a
/// single-check / double-check / read receipt glyph next to the timestamp.
enum DeliveryStatus {
    case sending
    case sent
    case read
}

// MARK: - ChatMessageKind

/// The content payload of a message.
///
/// Text and image content is the raw model data only — building attributed
/// strings and computing bubble layout happens one level up, in the view
/// model (task 02). Image messages carry the already-known pixel size so
/// the layout pass can size the bubble from the model alone, with no
/// network round trip and no async re-layout once the image arrives.
enum ChatMessageKind {
    case text(String)
    case image(url: URL, size: CGSize)
    /// Centered, bubble-less text — used for both day separators ("Monday,
    /// January 5") and one-off notices ("You started this conversation").
    case system(String)
}

// MARK: - ChatMessage

/// One row of the conversation timeline.
struct ChatMessage {
    /// Stable identifier, e.g. "msg-42". Doubles as the pipeline's row key
    /// and as the pagination anchor for `MockChat.earlierPage(before:)`.
    let id: String
    /// `nil` for system messages (date separators, notices) — they have no
    /// sender and render without an avatar or bubble.
    let sender: ChatUser?
    let timestamp: Date
    let kind: ChatMessageKind
    var status: DeliveryStatus
}
