//
//  StorageManager.swift
//  TextHelp
//
//  Created by OpenAI Assistant on 2025‑07‑22.
//

import Foundation
import CryptoKit

/// A utility responsible for reading and writing data to the
/// application’s shared container.  This manager abstracts the
/// underlying file paths and handles basic encryption/decryption when
/// persisting sensitive information.
final class StorageManager {
    /// The identifier of the App Group used to share data between the
    /// main application and its share extension.  Be sure to replace
    /// `group.com.example.texthelp` with your own App Group identifier in
    /// the Xcode project’s Signing & Capabilities settings.  The App
    /// Group must be added to both the main target and the extension.
    static let appGroupIdentifier = "group.com.example.texthelp"

    /// The filename used to store the persistent contact list.
    private static let contactsFileName = "contacts.json"

    /// The filename used by the share extension to hand off the raw
    /// transcript.  After the main app processes the file it should be
    /// deleted to avoid reprocessing.
    private static let importFileName = "import.txt"

    // MARK: - Public API

    /// Load the list of contacts from disk.  If the file does not
    /// exist or fails to decode, an empty array is returned.
    static func loadContacts() -> [Contact] {
        guard let url = fileURL(for: contactsFileName) else { return [] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            // If encryption is enabled, decrypt the data here.  See
            // `encrypt(_:)` and `decrypt(_:)` below for an example.
            let decrypted = try decrypt(data)
            let contacts = try JSONDecoder().decode([Contact].self, from: decrypted)
            return contacts
        } catch {
            print("Failed to load contacts: \(error)")
            return []
        }
    }

    /// Persist the list of contacts to disk.  Any existing file will be
    /// overwritten.  This method encrypts the data before writing
    /// whenever encryption succeeds; if encryption fails, the plain
    /// payload is written to ensure data isn’t silently lost.
    static func saveContacts(_ contacts: [Contact]) {
        guard let url = fileURL(for: contactsFileName) else { return }
        do {
            let encoded = try JSONEncoder().encode(contacts)
            let encrypted = try encrypt(encoded)
            try encrypted.write(to: url, options: .atomic)
        } catch {
            print("Failed to save contacts: \(error)")
            // Fallback: attempt to write raw data to prevent data loss
            do {
                let encoded = try JSONEncoder().encode(contacts)
                try encoded.write(to: url, options: .atomic)
            } catch {
                print("Failed to write raw contacts: \(error)")
            }
        }
    }

    /// Save the raw text imported from the share extension.  The text is
    /// written into the shared container so that the main application can
    /// later parse and process it.  If the write fails the function
    /// returns `false`.
    static func saveImport(text: String) -> Bool {
        guard let url = fileURL(for: importFileName) else { return false }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("Failed to save import text: \(error)")
            return false
        }
    }

    /// Attempt to load a pending import file.  Once loaded the file is
    /// deleted to prevent duplicate processing.  Returns `nil` if no
    /// import exists.
    static func loadPendingImport() -> String? {
        guard let url = fileURL(for: importFileName) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            try FileManager.default.removeItem(at: url)
            return text
        } catch {
            print("Failed to load or remove import file: \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    /// Resolve the URL for a file in the app group container.
    private static func fileURL(for name: String) -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            print("App group container unavailable")
            return nil
        }
        return container.appendingPathComponent(name)
    }

    // MARK: - Encryption Helpers

    /// A static symmetric key used to encrypt and decrypt the contact
    /// database.  In production you should generate a unique key for
    /// each user and store it securely in the Keychain; this example
    /// hard‑codes a key for demonstration purposes.  Never ship an app
    /// with a fixed encryption key!
    private static let encryptionKey: SymmetricKey = {
        // In practice you’d derive this key using a user’s password or
        // biometric protected secret.  Here we generate a random key at
        // first launch and store it in UserDefaults for simplicity.
        if let base64 = UserDefaults.standard.string(forKey: "encryptionKey"),
           let data = Data(base64Encoded: base64) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data(Array($0)) }
        UserDefaults.standard.set(data.base64EncodedString(), forKey: "encryptionKey")
        return key
    }()

    /// Encrypt arbitrary data using AES‑GCM.  A 12‑byte nonce is generated
    /// for each message and prefixed to the ciphertext.  Throws if
    /// encryption fails.
    private static func encrypt(_ plaintext: Data) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: encryptionKey, nonce: nonce)
        // Convert the nonce into raw data.  AES.GCM.Nonce does not expose
        // a `data` property, so we derive it from the underlying bytes.
        let nonceData = nonce.withUnsafeBytes { Data($0) }
        // Return nonce + ciphertext + tag as a single blob.
        return nonceData + sealed.ciphertext + sealed.tag
    }

    /// Decrypt previously encrypted data.  Expects the input to be
    /// formatted as nonce + ciphertext + tag (see `encrypt`).  Throws if
    /// decryption fails.
    private static func decrypt(_ data: Data) throws -> Data {
        // AES.GCM.nonceSize (12), tagSize (16)
        let nonceSize = 12
        let tagSize = 16
        guard data.count > nonceSize + tagSize else { throw DecryptionError.invalidData }
        let nonceData = data.prefix(nonceSize)
        let ciphertext = data.dropFirst(nonceSize).dropLast(tagSize)
        let tag = data.suffix(tagSize)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealed, using: encryptionKey)
    }

    /// Local errors thrown during decryption.
    enum DecryptionError: Error {
        case invalidData
    }
}