//
//  ImportView.swift
//  TextHelp
//
//  Presents a summary of messages imported through the share extension.
//  The user can identify the contact, pick a timeframe, and save the
//  transcript to the app.

import SwiftUI
import Foundation

struct ImportView: View {
    @EnvironmentObject private var dataManager: DataManager
    /// Preview of the imported transcript.
    let preview: String
    /// Initially detected contact (phone number or name).
    let detectedHandle: String?
    @Environment(\.dismiss) private var dismiss

    /// Contact label chosen or typed by the user.
    @State private var label: String = ""
    /// Predefined role chips.
    private let roles: [String] = ["Mom", "Dad", "GF/BF", "Friend", "Work", "Other…"]
    /// Selected timeframe.
    @State private var selection: TimeSelection = .lastHour
    /// Custom timeframe start (for `.custom`).
    @State private var customFrom: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    /// Custom timeframe end (for `.custom`).
    @State private var customTo: Date = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Preview of imported conversation")
                    .font(Theme.headingFont(size: 22))
                    .foregroundColor(Theme.violet)
                Text(preview)
                    .font(Theme.bodyFont())
                    .foregroundColor(.secondary)
                    .lineLimit(5)
                    .padding(12)
                    .background(Theme.background)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.violet.opacity(0.5), lineWidth: 1))
                    .cornerRadius(16)

                // Contact identification
                Text("Who is this conversation with?")
                    .font(Theme.headingFont(size: 22))
                    .foregroundColor(Theme.violet)

                // Display role chips using a grid
                let columns: [GridItem] = [GridItem(.adaptive(minimum: 80), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(roles, id: \.self) { role in
                        Button {
                            label = role
                        } label: {
                            Text(role)
                                .font(Theme.bodyFont())
                                .foregroundColor(Theme.background)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(label == role ? Theme.teal : Theme.violet.opacity(0.5))
                                .cornerRadius(16)
                        }
                    }
                }

                // Custom label entry
                TextField("Custom label", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.words)
                    .font(Theme.bodyFont())

                // Time selection
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Import timeframe", selection: $selection) {
                        Text("Last hour").tag(TimeSelection.lastHour)
                        Text("Today").tag(TimeSelection.today)
                        Text("Yesterday").tag(TimeSelection.yesterday)
                        Text("Custom…").tag(TimeSelection.custom)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .accentColor(Theme.teal)

                    // Custom timeframe date pickers
                    if selection == .custom {
                        DatePicker("From", selection: $customFrom, displayedComponents: .date)
                        DatePicker("To", selection: $customTo, displayedComponents: .date)
                    }
                }

                // Import button
                Button(action: confirmImport) {
                    HStack {
                        Spacer()
                        Text("Import Messages")
                            .font(Theme.bodyFont(size: 18))
                        Spacer()
                    }
                }
                .padding()
                .background(Theme.teal.opacity(0.2))
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)

                // Cancel button
                Button(role: .destructive) {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(Theme.bodyFont())
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Import Conversation")
        .onAppear {
            // Prepopulate label if detectedHandle is present and not a timestamp
            if let handle = detectedHandle, label.isEmpty {
                let timeRegex = try! NSRegularExpression(pattern: #"^[0-9]{1,2}:[0-9]{2}.*$"#, options: .caseInsensitive)
                if timeRegex.firstMatch(in: handle, options: [], range: NSRange(location: 0, length: handle.utf16.count)) == nil {
                    label = handle
                }
            }
        }
    }

    /// Calculate timeframe and import the transcript.
    private func confirmImport() {
        let now = Date()
        var from: Date? = nil
        var to: Date? = nil
        switch selection {
        case .lastHour:
            from = Calendar.current.date(byAdding: .hour, value: -1, to: now)
            to = now
        case .today:
            from = Calendar.current.startOfDay(for: now)
            to = now
        case .yesterday:
            let startOfToday = Calendar.current.startOfDay(for: now)
            from = Calendar.current.date(byAdding: .day, value: -1, to: startOfToday)
            to = startOfToday
        case .custom:
            from = customFrom
            to = customTo
        }

        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let manager = _dataManager.wrappedValue
        // Use DataManager’s real implementation to import the transcript
        manager.importTranscript(
            preview,
            label: trimmed.isEmpty ? "Unknown" : trimmed,
            handle: nil as String?,
            from: from,
            to: to
        )
        dismiss()
    }

    /// Time selection enum
    private enum TimeSelection: Equatable {
        case lastHour
        case today
        case yesterday
        case custom
    }
}

// The DataManager type in this project already defines a full
// `importTranscript(_:label:handle:from:to:)` implementation.  The
// fallback below was originally provided as a convenience when
// developing the UI without the full DataManager, but once
// DataManager gained its own implementation this resulted in a
// duplicate symbol error at compile time.  To avoid conflicts we
// remove the fallback entirely and rely on the primary
// implementation defined in DataManager.swift.

// extension DataManager {
//     /// A simplified fallback for projects that do not implement
//     /// `importTranscript` themselves.  It converts each line of
//     /// the transcript into a Message, appends to an existing contact
//     /// or creates a new one, persists the contacts list, and
//     /// returns.  If your DataManager provides its own import
//     /// logic, remove or disable this fallback to avoid duplicate
//     /// definitions.
//     func importTranscript(_ transcript: String, label: String, handle: String?, from: Date?, to: Date?) {
//         let lines = transcript.split(separator: "\n").map { String($0) }
//         let messages = lines.map { Message(timestamp: Date(), sender: "Other", body: $0) }
//         if let idx = contacts.firstIndex(where: { $0.label == label }) {
//             contacts[idx].messages.append(contentsOf: messages)
//             contacts[idx].messages.sort { $0.timestamp < $1.timestamp }
//         } else {
//             contacts.append(Contact(id: UUID(), label: label, messages: messages))
//         }
//         persist()
//     }
// }
