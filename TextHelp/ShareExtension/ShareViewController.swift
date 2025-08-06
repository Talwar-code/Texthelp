//
//  ShareViewController.swift
//  TextHelp Share Extension
//
//  Created by OpenAI Assistant on 2025‑07‑22.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Foundation
import ZIPFoundation



/// The main view controller for the share extension.  It receives
/// incoming text from the host application, displays a simple
/// preview and hands the text off to the app group so that the main
/// application can import it.  A SwiftUI view (`ShareExtensionView`)
/// provides the user interface.
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Observe for a custom notification to close the extension
        NotificationCenter.default.addObserver(forName: .closeShareExtension, object: nil, queue: .main) { [weak self] _ in
            self?.close()
        }

        // Begin loading the shared content
        handleIncomingText()
    }

    /// Attempt to retrieve plain text from the host application.  If
    /// successful we present a SwiftUI view that shows a preview and
    /// allows the user to continue.  Otherwise we close the extension.
    private func handleIncomingText() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            close()
            return
        }
        // First, try to load plain text directly
        let textType = UTType.plainText.identifier
        if itemProvider.hasItemConformingToTypeIdentifier(textType) {
            itemProvider.loadItem(forTypeIdentifier: textType, options: nil) { [weak self] (item, error) in
                if let _ = error {
                    self?.close()
                    return
                }
                guard let text = item as? String else {
                    self?.close()
                    return
                }
                DispatchQueue.main.async {
                    self?.presentPreview(for: text)
                }
            }
            return
        }
        // If not plain text, attempt to load a file URL
        let fileType = UTType.fileURL.identifier
        if itemProvider.hasItemConformingToTypeIdentifier(fileType) {
            itemProvider.loadItem(forTypeIdentifier: fileType, options: nil) { [weak self] (item, error) in
                if let _ = error {
                    self?.close()
                    return
                }
                guard let url = (item as? URL) else {
                    self?.close()
                    return
                }
                // Attempt to read the contents of the file.  Support plain text and JSON files.
                var content: String? = nil
                let ext = url.pathExtension.lowercased()
                if ext == "txt" || ext == "text" {
                    content = try? String(contentsOf: url)
                } else if ext == "json" {
                    if let data = try? Data(contentsOf: url) {
                        content = String(data: data, encoding: .utf8)
                    }
                } else if ext == "zip" {
                    // Extract the first .txt from a zip archive on supported platforms
                    content = self?.extractFirstTextFile(from: url)
                }
                guard let text = content else {
                    self?.close()
                    return
                }
                DispatchQueue.main.async {
                    self?.presentPreview(for: text)
                }
            }
            return
        }
        // Unsupported type
        close()
    }

    /// Extract the first `.txt` file from a ZIP archive at the given URL and
    /// return its contents as a string.  Uses Foundation’s Archive API
    /// when available.  Returns nil on failure.
    private func extractFirstTextFile(from url: URL) -> String? {
        if #available(iOS 16.6, *) {
            do {
                guard let archive = try? Archive(url: url, accessMode: .read) else { return nil }
                for entry in archive {
                    if entry.path.lowercased().hasSuffix(".txt") {
                        var data = Data()
                        _ = try archive.extract(entry) { part in
                            data.append(part)
                        }
                        return String(data: data, encoding: .utf8)
                    }
                }
            } catch {
                return nil
            }
        }
        return nil
    }

    /// Present the SwiftUI preview for the imported text.
    private func presentPreview(for text: String) {
        let previewView = ShareExtensionView(text: text) { accepted in
            // Save or discard based on the user's action
            if accepted {
                _ = StorageManager.saveImport(text: text)
            }
            // Post notification to close
            NotificationCenter.default.post(name: .closeShareExtension, object: nil)
        }
        let hosting = UIHostingController(rootView: previewView)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        hosting.view.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        hosting.didMove(toParent: self)
    }

    /// Dismiss the share extension and return control to the host app.
    private func close() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

extension Notification.Name {
    static let closeShareExtension = Notification.Name("CloseShareExtension")
}
