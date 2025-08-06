//
//  DataManager.swift
//  TextHelp
//
//  Created by OpenAI Assistant on 2025‑07‑29.
//
//  Manages data access and AI integration.  Handles contacts and
//  messages, saving, loading, and calling the GPT API for various tasks.

import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
class DataManager: ObservableObject {
    /// A published list of all known contacts.  When updated, the UI
    /// automatically refreshes.
    @Published var contacts: [Contact]
    /// Hold on to Combine subscriptions so they live for the duration of
    /// asynchronous API calls.
    private var cancellables = Set<AnyCancellable>()

    /// Initialise by loading any previously persisted contacts.  If no
    /// data exists the contacts array will be empty.  Loading happens
    /// synchronously on construction so that the UI can immediately
    /// display previously saved conversations.
    init() {
        self.contacts = StorageManager.loadContacts()
    }

    /// Persist the contacts to disk.  This calls through to the
    /// StorageManager so that drafts and conversations survive app
    /// restarts.  In order to avoid overwriting the file when there are
    /// no changes, callers should ensure they mutate `contacts` before
    /// invoking this method.
    func persist() {
        StorageManager.saveContacts(contacts)
    }

    /// Import a set of chat screenshots.  The parser runs on a
    /// background queue to avoid blocking the main thread.  Once
    /// complete, the messages are merged into an existing contact or a
    /// new contact is created.  The style embedding for the contact is
    /// recomputed whenever new messages are appended.  The completion
    /// handler receives the final label used for the contact so that
    /// callers can navigate directly to the conversation view.
    func importScreenshots(_ images: [UIImage], label: String?, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Parse all images into structured messages and detect a
            // possible contact name.  The parser expects images ordered
            // from newest to oldest but still functions with any order.
            let result = ScreenshotParser.parseScreenshots(images)
            let parsedMessages = result.messages
            var contactName: String? = label
            if contactName == nil || contactName!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contactName = result.contactName
            }
            if contactName == nil || contactName!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contactName = "Unknown"
            }
            let finalLabel = contactName!.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Either append to an existing contact or create a new one
                if let index = self.contacts.firstIndex(where: { $0.label == finalLabel }) {
                    // Merge messages and re-sort
                    self.contacts[index].messages.append(contentsOf: parsedMessages)
                    self.contacts[index].messages.sort { $0.timestamp < $1.timestamp }
                    // Recompute the style embedding for improved replies
                    let embedding = EmbeddingService.generateEmbedding(messages: self.contacts[index].messages)
                    self.contacts[index].styleEmbedding = embedding
                } else {
                    var newContact = Contact(id: UUID(), label: finalLabel, messages: parsedMessages)
                    newContact.styleEmbedding = EmbeddingService.generateEmbedding(messages: parsedMessages)
                    self.contacts.append(newContact)
                }
                self.persist()
                completion(finalLabel)
            }
        }
    }

    /// Import a plain text transcript.  This helper uses the
    /// ConversationParser to turn a raw string into messages.  A
    /// timeframe can optionally be provided to narrow the messages
    /// imported.  If a contact with the given label exists, the
    /// messages are appended; otherwise a new contact is created.  The
    /// style embedding is recalculated whenever messages change.
    func importTranscript(_ transcript: String, label: String, handle: String?, from: Date?, to: Date?) {
        // Parse the transcript and filter by the provided timeframe
        let parsed = ConversationParser.parse(text: transcript, from: from, to: to)
        let finalLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : label
        if let index = contacts.firstIndex(where: { $0.label == finalLabel }) {
            contacts[index].messages.append(contentsOf: parsed)
            contacts[index].messages.sort { $0.timestamp < $1.timestamp }
            contacts[index].styleEmbedding = EmbeddingService.generateEmbedding(messages: contacts[index].messages)
        } else {
            var newContact = Contact(id: UUID(), label: finalLabel, messages: parsed)
            newContact.styleEmbedding = EmbeddingService.generateEmbedding(messages: parsed)
            contacts.append(newContact)
        }
        persist()
    }

    /// Generate one or more reply messages tailored to the given goal.
    /// The LLMService handles communication with the underlying model.
    /// Results are delivered via the completion handler on the main
    /// thread.  The generated messages are wrapped in `Message`
    /// structs with the current timestamp and the sender set to
    /// "Assistant".
    func generateReply(for contact: Contact, goal: String, multiStep: Bool, completion: @escaping (Result<[Message], Error>) -> Void) {
        let recent = Array(contact.messages.suffix(6))
        LLMService.shared.generateReply(contact: contact, recentMessages: recent, goal: goal, multiStep: multiStep)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionState in
                if case let .failure(error) = completionState {
                    completion(.failure(error))
                }
            }, receiveValue: { replies in
                let messages = replies.map { Message(timestamp: Date(), sender: "Assistant", body: $0) }
                completion(.success(messages))
            })
            .store(in: &cancellables)
    }

    /// Adjust a user‑provided message according to a set of
    /// instructions.  The adjusted message is returned via the
    /// completion handler.  Any errors from the model are propagated
    /// through the `Result` type.
    func adjustMessage(for contact: Contact, original: String, instructions: String, completion: @escaping (Result<String, Error>) -> Void) {
        LLMService.shared.adjustMessage(contact: contact, message: original, instructions: instructions)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionState in
                if case let .failure(error) = completionState {
                    completion(.failure(error))
                }
            }, receiveValue: { adjusted in
                completion(.success(adjusted))
            })
            .store(in: &cancellables)
    }

    /// Provide general advice or insight about a conversation based on
    /// a free‑form prompt.  The reply from the model is delivered on
    /// the main thread.  A small slice of the most recent messages is
    /// provided as context to the model to ground the advice.
    func textHelp(for contact: Contact, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        let recent = Array(contact.messages.suffix(6))
        LLMService.shared.textHelp(contact: contact, recentMessages: recent, prompt: prompt)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionState in
                if case let .failure(error) = completionState {
                    completion(.failure(error))
                }
            }, receiveValue: { reply in
                completion(.success(reply))
            })
            .store(in: &cancellables)
    }

    /// Ask the model for a set of three popular reply intents based on the
    /// latest messages.  The suggestions aim to capture the most likely
    /// goals a user might have when responding to the current
    /// conversation.  The model is prompted to return a comma‑ or
    /// newline‑separated list of short phrases (one to three words each).
    /// If the model call fails for any reason the provided fallback
    /// suggestions are returned instead.  Results are delivered on
    /// the main thread.
    func fetchReplySuggestions(for contact: Contact, completion: @escaping ([String]) -> Void) {
        // Use up to six of the most recent messages as context
        let recentMessages = Array(contact.messages.suffix(6))
        let fallback = ["Friendly", "Decline", "Make a plan"]
        // If the contact has no messages yet, return the fallback immediately
        guard !recentMessages.isEmpty else {
            completion(fallback)
            return
        }
        // Prompt the model to generate reply intents.  We instruct the
        // assistant to list three distinct reply goals separated by
        // commas or newlines.  The model should avoid explanatory
        // preamble and return only the phrases.
        let prompt = "Based on this conversation, suggest three different general goals the user might have for their reply. Each suggestion should be one to three words. Separate the suggestions with commas or new lines. Return only the suggestions, nothing else."
        LLMService.shared.textHelp(contact: contact, recentMessages: recentMessages, prompt: prompt)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionState in
                if case .failure(_) = completionState {
                    // In case of any error, use fallback
                    completion(fallback)
                }
            }, receiveValue: { response in
                // Split the response by commas or newlines into up to three parts
                let delimiters = CharacterSet(charactersIn: ",\n")
                let parts = response
                    .components(separatedBy: delimiters)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if parts.count >= 3 {
                    completion(Array(parts.prefix(3)))
                } else if parts.count > 0 {
                    // If fewer than three suggestions returned, pad with fallback
                    let padded = parts + fallback
                    completion(Array(padded.prefix(3)))
                } else {
                    completion(fallback)
                }
            })
            .store(in: &cancellables)
    }

    /// Adds a draft message to the specified contact and persists it.
    func saveDraft(_ messageText: String, to contact: Contact) {
        let draft = Message(timestamp: Date(), sender: "Draft", body: messageText)
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index].messages.append(draft)
            contacts[index].messages.sort { $0.timestamp < $1.timestamp }
            persist()
            // Notify listeners that a draft has been saved so that the UI can animate the
            // history tab or perform other actions.
            NotificationCenter.default.post(name: .draftSaved, object: nil)
        }
    }
}

// MARK: - Draft Saved Notification

extension Notification.Name {
    /// Notification posted whenever a draft is saved.  The `HomeView` listens
    /// for this event to animate the history tab icon, giving the user
    /// feedback that their draft has been added to the history.  This
    /// avoids tightly coupling the DataManager to the UI layer.
    static let draftSaved = Notification.Name("draftSaved")
}
