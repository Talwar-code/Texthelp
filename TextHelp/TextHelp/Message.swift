//
//  Message.swift
//  TextHelp
//
//  Created by OpenAI Assistant on 2025‑07‑22.
//

import Foundation

/// Represents a single text message in a conversation.
///
/// Messages are imported from plain text exports produced by Messages or
/// other chat applications.  Each message carries a timestamp, the sender’s
/// name (or "You" for the user’s own messages) and the body of the message.
struct Message: Identifiable, Codable {
    var id: UUID = UUID()
    /// The time at which this message was sent.  Dates are parsed from
    /// strings such as `03/21/25, 2:14 PM` using a `DateFormatter` in
    /// `ConversationParser`.
    var timestamp: Date
    /// The display name of the message’s author.  For exports from
    /// Messages the user’s own lines often begin with "You:" while lines
    /// from the other party contain their name.
    var sender: String
    /// The textual content of the message.
    var body: String
}