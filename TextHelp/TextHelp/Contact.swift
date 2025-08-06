//
//  Contact.swift
//  TextHelp
//
//  Created by OpenAI Assistant on 2025‑07‑22.
//

import Foundation

/// Represents a person or conversation partner within the application.
struct Contact: Identifiable, Codable, Hashable {
    var id: UUID
    var label: String
    var handle: String?
    var messages: [Message]
    var styleEmbedding: [Double]?
}

// MARK: - Hashable Conformance
extension Contact {
    /// Two contacts are considered equal if they share the same identifier.
    static func == (lhs: Contact, rhs: Contact) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hash the contact using its unique identifier.  This allows
    /// `Contact` to be used with `navigationDestination(item:)` and
    /// other APIs that require `Hashable`.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
