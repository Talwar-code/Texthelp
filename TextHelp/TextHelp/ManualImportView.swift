//
//  ManualImportView.swift
//  TextHelp
//
//  Created by OpenAI Assistant on 2025‑07‑29.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import UIKit
import ZIPFoundation


/// A view that lets the user manually add a chat to the app without using
/// the share extension.  Users can paste text from the clipboard or pick
/// a text file from the Files app.  Once text is provided, tapping
/// “Next” will feed the imported transcript into the existing import
/// workflow.
struct ManualImportView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var transcript: String = ""
    @State private var showingFileImporter: Bool = false
    @State private var label: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste or select your conversation")
                    .font(.headline)

                TextEditor(text: $transcript)
                    .frame(minHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3))
                    )

                TextField("Contact name (optional)", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.words)

                HStack {
                    Button(action: pasteFromClipboard) {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                            Text("Paste")
                        }
                    }
                    Spacer()
                    Button(action: { showingFileImporter = true }) {
                        HStack {
                            Image(systemName: "folder")
                            Text("Pick File")
                        }
                    }
                }
                .padding(.vertical, 8)

                Spacer()

                Button(action: proceedToImport) {
                    HStack {
                        Spacer()
                        Text("Next")
                        Spacer()
                    }
                }
                .padding()
                .background(Color.accentColor.opacity(0.2))
                .cornerRadius(8)
                .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle("Add Chat")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [UTType.plainText, UTType.text, UTType.json, UTType.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    loadFile(from: url)
                case .failure:
                    break
                }
            }
        }
    }

    private func loadFile(from url: URL) {
        let secured: Bool
        #if !targetEnvironment(simulator)
        secured = url.startAccessingSecurityScopedResource()
        #else
        secured = false
        #endif
        defer {
            if secured { url.stopAccessingSecurityScopedResource() }
        }
        let ext = url.pathExtension.lowercased()
        if ext == "txt" || ext == "text" {
            if let content = try? String(contentsOf: url) {
                transcript = content
            }
            return
        }
        if ext == "json" {
            if let data = try? Data(contentsOf: url),
               let content = String(data: data, encoding: .utf8) {
                transcript = content
            }
            return
        }
        if ext == "zip" {
            if let extracted = extractFirstTextFile(from: url) {
                transcript = extracted
            }
            return
        }
    }

    private func extractFirstTextFile(from url: URL) -> String? {
        if #available(iOS 16.0, *) {
            do {
                guard let archive = try? Archive(url: url, accessMode: .read) else { return nil }
                for entry in archive where entry.path.lowercased().hasSuffix(".txt") {
                    var data = Data()
                    _ = try archive.extract(entry) { part in
                        data.append(part)
                    }
                    return String(data: data, encoding: .utf8)
                }
            } catch {
                return nil
            }
        }
        return nil
    }

    private func pasteFromClipboard() {
        if let clip = UIPasteboard.general.string {
            transcript = clip
        }
    }

    private func proceedToImport() {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let contactLabel = trimmed.isEmpty ? "Unknown" : trimmed
        dataManager.importTranscript(transcript, label: contactLabel, handle: nil, from: nil, to: nil)
        dismiss()
    }
}
