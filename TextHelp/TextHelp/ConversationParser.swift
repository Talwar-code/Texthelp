//
//  ConversationParser.swift
//  TextHelp
//
//  Created by OpenAI Assistant on 2025‑07‑22.
//

import Foundation

/// A helper responsible for parsing plain text transcripts exported from
/// messaging applications into structured `Message` arrays.  The parser
/// recognizes lines of the form:
///
/// ```
/// [03/21/25, 2:14 PM] Alice: Hey, are you free tonight?
/// [03/21/25, 2:15 PM] You: Sure — what time?
/// ```
///
/// Each line begins with a timestamp in square brackets, followed by the
/// sender’s name, a colon and then the body of the message.  Timestamps
/// are converted into `Date` objects using a `DateFormatter`.  Lines
/// failing to match this pattern are ignored.  Callers can filter
/// messages to a specific timeframe by providing optional `from` and
/// `to` dates.
struct ConversationParser {
    /// Parse the raw text export into an array of `Message` objects.  If
    /// `from` and/or `to` are supplied, only messages whose timestamps
    /// fall within the range are returned.
    ///
    /// - Parameters:
    ///   - text: The entire contents of the exported conversation file.
    ///   - from: Optional lower bound for the timestamp of messages to keep.
    ///   - to: Optional upper bound for the timestamp of messages to keep.
    /// - Returns: An array of messages sorted by timestamp ascending.
    static func parse(text: String, from: Date? = nil, to: Date? = nil) -> [Message] {
        var messages: [Message] = []

        // Define a date formatter capable of parsing the timestamps used in
        // exports.  Apple's Messages uses the en_US_POSIX locale.  Many
        // exports also include a non‑breaking space between the time and
        // the AM/PM indicator (U+202F).  We normalise such spaces to
        // ordinary spaces before parsing.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Accept either two‑digit or one‑digit hours and minutes with AM/PM.
        formatter.dateFormat = "MM/dd/yy, h:mm a"

        // Regular expression capturing the components of each line.  We use
        // non‑greedy matching for the message body to avoid consuming
        // subsequent lines.  The pattern is anchored to the start of the
        // line.
        let pattern = "^\\[(.+?),\\s*(.+?)\\]\\s*(.+?):\\s*(.+)$"
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        } catch {
            print("Failed to create regex: \(error)")
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges == 5 else { continue }
            let dateString = nsText.substring(with: match.range(at: 1))
            let timeString = nsText.substring(with: match.range(at: 2))
            let sender = nsText.substring(with: match.range(at: 3))
            let body = nsText.substring(with: match.range(at: 4))

            // Combine date and time, then normalise narrow non‑breaking spaces (U+202F) to ordinary spaces.
            // The `\u{202F}` escape represents the Unicode narrow no‑break space, which some exports
            // use between the time and the AM/PM indicator.  Without normalising this character the
            // DateFormatter would fail to parse the timestamp.
            let timestampString = "\(dateString), \(timeString)".replacingOccurrences(of: "\u{202F}", with: " ")
            guard let date = formatter.date(from: timestampString) else { continue }

            // Apply timeframe filtering if provided.
            if let from = from, date < from { continue }
            if let to = to, date > to { continue }

            let message = Message(timestamp: date, sender: sender, body: body)
            messages.append(message)
        }
        // Sort messages by timestamp ascending.
        messages.sort { $0.timestamp < $1.timestamp }
        return messages
    }
}