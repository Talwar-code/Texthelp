//
//  EmbeddingService.swift
//  TextHelp
//
//  Created by OpenAI Assistant on 2025‑07‑29.
//

import Foundation

/// A simple embedding service that generates a fixed‑length vector from
/// a sequence of messages.  This implementation does not rely on
/// external machine learning services; instead it computes a few
/// aggregate statistics (such as punctuation counts, capitalization,
/// average length) to approximate a conversational style.  A real
/// application could replace this with a call to a cloud embedding
/// API (e.g. OpenAI’s Embedding API) and persist the resulting vector
/// securely.
struct EmbeddingService {
    /// Generate a 5‑dimensional embedding from the provided messages.
    /// - Parameter messages: The messages whose text should be analyzed.
    /// - Returns: A vector of doubles capturing simple stylistic
    ///   features: average exclamation marks per message, average
    ///   question marks per message, uppercase ratio, average character
    ///   length per message, and average word count per message.
    static func generateEmbedding(messages: [Message]) -> [Double] {
        guard !messages.isEmpty else { return [] }
        var exclamations = 0
        var questions = 0
        var uppercaseCount = 0
        var totalChars = 0
        var totalWords = 0
        for message in messages {
            let body = message.body
            exclamations += body.filter { $0 == "!" }.count
            questions += body.filter { $0 == "?" }.count
            uppercaseCount += body.filter { $0.isUppercase }.count
            totalChars += body.count
            totalWords += body.split(whereSeparator: { $0 == " " || $0.isNewline }).count
        }
        let count = Double(messages.count)
        let totalCharsD = Double(max(totalChars, 1))
        let avgExclamations = Double(exclamations) / count
        let avgQuestions = Double(questions) / count
        let uppercaseRatio = Double(uppercaseCount) / totalCharsD
        let avgLength = Double(totalChars) / count
        let avgWords = Double(totalWords) / count
        return [avgExclamations, avgQuestions, uppercaseRatio, avgLength, avgWords]
    }
}