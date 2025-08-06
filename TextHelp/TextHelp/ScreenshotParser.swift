//
//  ScreenshotParser.swift
//  TextHelp
//
//  Created by OpenAI Assistant on 2025‑07‑29.
//
//  This helper provides basic OCR and parsing for chat screenshots.  It uses
//  Apple’s Vision framework to recognise text within each image and then
//  attempts to extract conversation lines.  The topmost recognised line in
//  the first screenshot is treated as a best guess for the contact name.  A
//  more robust implementation would leverage bounding box analysis,
//  machine‑learning models or external services to more accurately
//  reconstruct the conversation structure.  However, this lightweight
//  approach demonstrates the concept without relying on external
//  dependencies.

import Foundation
import UIKit
import Vision

/// A result produced by parsing a set of chat screenshots.
struct ScreenshotParseResult {
    /// The messages extracted from the screenshots in chronological order.
    let messages: [Message]
    /// The contact name detected from the top of the first screenshot, if any.
    let contactName: String?
}

/// A utility responsible for performing OCR on screenshots and
/// converting the recognised text into structured `Message` objects.
enum ScreenshotParser {
    /// Parse an array of screenshots into messages.  Screenshots should be
    /// supplied in the order they were taken (latest first).  The parser
    /// attempts to build a conversation history by scanning for lines
    /// containing a colon (`:`) to separate the sender from the body.  If no
    /// colon is found the entire line is treated as the message body and
    /// the sender defaults to "Other".
    ///
    /// - Parameter images: The screenshots to parse, ordered from newest to
    ///   oldest.
    /// - Returns: A result containing the extracted messages and optional
    ///   contact name.
    static func parseScreenshots(_ images: [UIImage]) -> ScreenshotParseResult {
        var messages: [Message] = []
        var detectedContact: String? = nil
        // Start timestamps slightly in the past so ordering is preserved when
        // appending messages.  Each subsequent message advances by 0.1s.
        var time = Date().addingTimeInterval(-Double(images.count) * 0.1)
        // Words that often appear in screenshots but are not part of the
        // conversation (status bar labels, keyboard hints, etc.).  These
        // will be ignored during parsing and contact detection.
        let ignoredWords: Set<String> = [
            "delivered", "imessage", "i message", "read", "sms", "return", "space", "search", "send",
            "back", "forward", "delete", "copy", "more", "reply", "i'm", "i’m",
            "123", "456", "789", "abc", "emoji", "camera", "microphone", "app", "messages",
            // Additional tokens that sometimes appear from the keyboard or UI but aren’t part of the chat
            "the", "i", "i’m", "i'm"
        ]
        // Iterate through screenshots from oldest to newest to preserve order.
        for (index, image) in images.reversed().enumerated() {
            guard let cgImage = image.cgImage else { continue }
            let recognised = recogniseTextLines(from: cgImage)
            // On the newest screenshot attempt to detect the contact name/number.
            if index == 0 && detectedContact == nil {
                var numericCandidate: String? = nil
                outer: for item in recognised {
                    let raw = item.text
                    let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !candidate.isEmpty else { continue }
                    let lower = candidate.lowercased()
                    // Only consider lines centred horizontally.
                    let midX = item.bbox.midX
                    if midX < 0.2 || midX > 0.8 { continue }
                    // Ignore if it's in the ignored words list.
                    if ignoredWords.contains(lower) { continue }
                    // Skip avatar initials (1–2 letters with no spaces).
                    if candidate.count <= 2,
                       candidate.rangeOfCharacter(from: .letters) != nil,
                       candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                        continue
                    }
                    // Normalise by collapsing multiple spaces and stripping the '>' character.
                    var cleaned = candidate.replacingOccurrences(of: ">", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    guard !cleaned.isEmpty else { continue }
                    // Skip strings that look like timestamps (e.g. "4:06", "4:06 PM").
                    let tsPatterns = [
                        "^[0-9]{1,2}:[0-9]{2}(?:\\s?[APap][Mm])?$",
                        "^[0-9]{1,2}:[0-9]{2}\\s?[A-Za-z]$",
                        "^[0-9]{1,2}:[0-9]{2}$"
                    ]
                    var isTimestamp = false
                    for pattern in tsPatterns {
                        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                           regex.firstMatch(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.utf16.count)) != nil {
                            isTimestamp = true
                            break
                        }
                    }
                    if isTimestamp { continue }
                    // Skip candidates that are full sentences or very long.
                    let words = cleaned.split { $0 == " " || $0 == "\t" }
                    if words.count > 3 || cleaned.count > 30 { continue }
                    // Skip candidates containing punctuation likely not present in names.
                    let invalidCharacters = CharacterSet(charactersIn: ",!?@#$%^&*()+={}[]|\\/;:'")
                    if cleaned.rangeOfCharacter(from: invalidCharacters) != nil {
                        continue
                    }
                    // Skip strings containing a colon entirely.
                    if cleaned.contains(":") { continue }
                    // If the cleaned candidate contains any letter, accept it as the contact name.
                    if cleaned.rangeOfCharacter(from: .letters) != nil {
                        detectedContact = cleaned
                        break outer
                    }
                    // Otherwise, if comprised solely of phone characters, store as numeric fallback.
                    let phoneChars = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "+()- ."))
                    if cleaned.unicodeScalars.allSatisfy({ phoneChars.contains($0) }) {
                        let digitCount = cleaned.filter { $0.isNumber }.count
                        if digitCount >= 5 {
                            if numericCandidate == nil {
                                numericCandidate = cleaned
                            }
                        }
                    }
                }
                // If we didn't find a textual candidate but we have a numeric one, use it.
                if detectedContact == nil {
                    detectedContact = numericCandidate
                }
            }

            // Extract messages from this screenshot
            var currentSender: String? = nil
            var currentBody: String = ""
            var currentOrientation: String? = nil // "You" or "Other"
            for (lineIndex, item) in recognised.enumerated() {
                var trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                // Skip location lines such as "Florida City, FL" so they aren't treated as messages.
                // Regex uses double backslashes to escape \s and \d in Swift string literals.
                if let locationRegex = try? NSRegularExpression(pattern: "^[A-Za-z .]+,\\s*[A-Za-z]{2}(?:\\s+\\d{5})?$", options: .caseInsensitive),
                   locationRegex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
                    continue
                }
                // Determine orientation: messages on the right (midX > 0.6) are from the user.
                let orientation = item.bbox.midX > 0.6 ? "You" : "Other"
                let lower = trimmed.lowercased()
                // Skip avatar initials.
                if trimmed.count <= 2,
                   trimmed.rangeOfCharacter(from: .letters) != nil,
                   trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                    continue
                }
                // Skip ignored words entirely.
                if ignoredWords.contains(lower) { continue }
                // Skip timestamps (e.g. "4:06", "4:06 PM").
                let timestampPatterns = [
                    "^[0-9]{1,2}:[0-9]{2}(?:\\s?[APap][Mm])?$",
                    "^[0-9]{1,2}:[0-9]{2}\\s?[A-Za-z]$"
                ]
                var looksLikeTime = false
                for pattern in timestampPatterns {
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                       regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
                        looksLikeTime = true
                        break
                    }
                }
                if looksLikeTime { continue }
                // Skip lines containing '>' which often indicate truncated UI or quoting.
                if trimmed.contains(">") { continue }
                // Heuristically skip likely truncated lines appearing at the very top of the screenshot.
                let wordCount = trimmed.split { $0 == " " || $0 == "\t" }.count
                if currentBody.isEmpty && lineIndex < 2 && wordCount > 5 {
                    continue
                }
                // If the line contains a colon, assume "Sender: Body".
                if let colonRange = trimmed.range(of: ":") {
                    // Finalise the current message if we have one.
                    if !currentBody.isEmpty {
                        let senderName = currentSender ?? currentOrientation ?? "Other"
                        messages.append(Message(timestamp: time, sender: senderName, body: currentBody))
                        time.addTimeInterval(0.1)
                        currentBody = ""
                        currentSender = nil
                        currentOrientation = nil
                    }
                    let senderPart = String(trimmed[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let bodyPart = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    // Filter out entries where both sender and body look numeric.
                    if senderPart.rangeOfCharacter(from: .decimalDigits) != nil,
                       bodyPart.rangeOfCharacter(from: .decimalDigits) != nil {
                        continue
                    }
                    // Ignore reaction notifications.
                    let lowerBody = bodyPart.lowercased()
                    if lowerBody.hasPrefix("liked") || lowerBody.hasPrefix("loved") || lowerBody.hasPrefix("reacted") {
                        continue
                    }
                    currentSender = senderPart.isEmpty ? orientation : senderPart
                    currentOrientation = orientation
                    currentBody = bodyPart
                } else {
                    // No colon; treat as part of a message based on orientation.
                    // Skip very short tokens without letters (e.g. "123").
                    if trimmed.count <= 3 && trimmed.rangeOfCharacter(from: .letters) == nil {
                        continue
                    }
                    if currentBody.isEmpty {
                        currentSender = orientation
                        currentOrientation = orientation
                        currentBody = trimmed
                    } else if orientation == currentOrientation {
                        currentBody += " " + trimmed
                    } else {
                        let senderName = currentSender ?? currentOrientation ?? "Other"
                        messages.append(Message(timestamp: time, sender: senderName, body: currentBody))
                        time.addTimeInterval(0.1)
                        currentSender = orientation
                        currentOrientation = orientation
                        currentBody = trimmed
                    }
                }
            }
            // Finalise any pending message after processing all lines.
            if !currentBody.isEmpty {
                let senderName = currentSender ?? currentOrientation ?? "Other"
                messages.append(Message(timestamp: time, sender: senderName, body: currentBody))
                time.addTimeInterval(0.1)
            }
        }
        return ScreenshotParseResult(messages: messages, contactName: detectedContact)
    }

    /// Use Vision to recognise lines of text from a CGImage.  The results
    /// are sorted top‑to‑bottom based on the bounding box of each
    /// observation and include the bounding box so that horizontal
    /// position can be used to infer sender (left vs right) on iMessage
    /// style screenshots.
    private struct RecognisedLine {
        let text: String
        /// Normalised bounding box in Vision’s coordinate system where the
        /// origin is bottom‑left.
        let bbox: CGRect
    }

    /// Perform OCR on the provided image and return an array of
    /// recognised text lines together with their bounding boxes.
    private static func recogniseTextLines(from cgImage: CGImage) -> [RecognisedLine] {
        var recognised: [RecognisedLine] = []
        let request = VNRecognizeTextRequest { request, error in
            if let observations = request.results as? [VNRecognizedTextObservation] {
                for obs in observations {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    recognised.append(RecognisedLine(text: candidate.string, bbox: obs.boundingBox))
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        // Sort by y coordinate descending (top to bottom).  In Vision’s coordinate
        // system, larger y values correspond to higher text.
        return recognised.sorted { $0.bbox.midY > $1.bbox.midY }
    }
}
