//
//  ScreenshotImportView.swift
//  TextHelp
//
//  Presents an interface for selecting chat screenshots from the user’s
//  photo library, optionally identifying the contact, and importing
//  the extracted conversation into the app.  This view is displayed
//  as a sheet from the home screen.

import SwiftUI
import PhotosUI

struct ScreenshotImportView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    /// The initial compose mode (Reply, Refine, or Insight)
    let mode: ComposeView.Mode
    /// Callback when import completes
    let onImport: ((String?) -> Void)?

    @State private var selections: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var detectedContact: String? = nil
    @State private var label: String = ""
    @State private var isImporting: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Upload a Message or Conversation")
                        .font(Theme.headingFont(size: 28))
                        .foregroundColor(Theme.teal)

                    // Select screenshots
                    PhotosPicker(selection: $selections,
                                 maxSelectionCount: 10,
                                 matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.teal)
                            Text(selections.isEmpty ? "Select screenshots"
                                 : "Update Conversation (\(selections.count))")
                                .font(Theme.bodyFont())
                                .foregroundColor(Theme.teal)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Theme.violet.opacity(0.2))
                        .cornerRadius(16)
                    }

                    // Preview images
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(images, id: \.self) { uiImage in
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 120, height: 220)
                                        .cornerRadius(12)
                                        .clipped()
                                }
                            }
                        }
                    }

                    // Ask for contact name or show detected one
                    if !images.isEmpty {
                        Text("Who is this conversation with?")
                            .font(Theme.headingFont(size: 20))
                            .foregroundColor(Theme.violet)
                        Text("Examples: Mom, Dad, Partner, Friend, Work")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                        if let detected = detectedContact {
                            Text("Detected contact: \(detected)")
                                .font(Theme.bodyFont())
                                .foregroundColor(Theme.teal)
                            Text("If this is incorrect you can edit the contact name later.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            TextField("Contact name (optional)", text: $label)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.bodyFont())
                                .autocapitalization(.words)
                            Text("You don’t have to label the contact, but identifying them helps the AI learn their style over time.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Import button
                    if !images.isEmpty {
                        Button(action: importScreens) {
                            HStack {
                                Spacer()
                                if isImporting {
                                    ProgressView()
                                } else {
                                    Text("Import Conversation")
                                        .font(Theme.bodyFont(size: 18))
                                }
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Theme.teal.opacity(0.2))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                        .disabled(isImporting)
                    }
                }
                .padding()
                .padding(.bottom, 200)
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationBarHidden(true)
            .onChange(of: selections) { newItems in
                Task {
                    images.removeAll()
                    detectedContact = nil
                    label = ""
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            images.append(uiImage)
                        }
                    }
                    // Run OCR on loaded images
                    if !images.isEmpty {
                        DispatchQueue.global(qos: .userInitiated).async {
                            let result = ScreenshotParser.parseScreenshots(images)
                            if let name = result.contactName {
                                DispatchQueue.main.async {
                                    detectedContact = name
                                    if label.isEmpty { label = name }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Import the selected screenshots, using DataManager.
    private func importScreens() {
        guard !images.isEmpty else { return }
        isImporting = true
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let manager = _dataManager.wrappedValue
        manager.importScreenshots(images, label: trimmedLabel.isEmpty ? nil : trimmedLabel) { importedLabel in
            isImporting = false
            onImport?(importedLabel)
            dismiss()
        }
    }
}

// The DataManager type in this project already defines a full
// `importScreenshots(_:label:completion:)` implementation.  The
// fallback below was originally provided as a convenience when
// developing the UI without the full DataManager, but once
// DataManager gained its own implementation this resulted in a
// duplicate symbol error at compile time.  To avoid conflicts we
// remove the fallback entirely and rely on the primary
// implementation defined in DataManager.swift.

// extension DataManager {
//     /// A simplified fallback for projects that do not implement
//     /// `importScreenshots` themselves.  It creates a contact if
//     /// necessary, persists the contacts list, and calls the
//     /// completion handler with the final label.  If your
//     /// DataManager provides its own import logic, remove or
//     /// disable this fallback to avoid duplicate definitions.
//     func importScreenshots(_ images: [UIImage], label: String?, completion: @escaping (String?) -> Void) {
//         let contactLabel = (label?.isEmpty ?? true) ? "Unknown" : label!
//         if contacts.firstIndex(where: { $0.label == contactLabel }) == nil {
//             // Provide a UUID for the id parameter
//             contacts.append(Contact(id: UUID(), label: contactLabel, messages: []))
//         }
//         persist()
//         completion(contactLabel)
//     }
// }
