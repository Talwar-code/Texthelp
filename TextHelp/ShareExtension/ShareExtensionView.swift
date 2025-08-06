//
//  ShareExtensionView.swift
//  TextHelp Share Extension
//
//  Created by OpenAI Assistant on 2025‑07‑22.
//

import SwiftUI

/// A simple SwiftUI view used inside the share extension to preview
/// incoming text and allow the user to continue or cancel.  When
/// continuing, the text will be written into the App Group so that
/// the main application can process it when launched.
struct ShareExtensionView: View {
    let text: String
    /// Completion handler invoked when the user accepts or cancels.
    var completion: (Bool) -> Void
    /// Limit the preview to a handful of lines so that long
    /// conversations don’t overwhelm the extension UI.
    private var previewLines: String {
        text.split(separator: "\n").prefix(5).joined(separator: "\n")
    }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Preview")
                    .font(Theme.headingFont(size: 24))
                    .foregroundColor(Theme.violet)
                ScrollView {
                    Text(previewLines)
                        .font(Theme.bodyFont())
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(12)
                .background(Theme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.violet.opacity(0.5), lineWidth: 1)
                )
                .cornerRadius(16)
                Spacer()
                HStack {
                    Button("Cancel") {
                        completion(false)
                    }
                    .font(Theme.bodyFont())
                    .foregroundColor(Theme.violet)
                    .padding()
                    .background(Theme.violet.opacity(0.2))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    Spacer()
                    Button("Next →") {
                        completion(true)
                    }
                    .font(Theme.bodyFont())
                    .foregroundColor(Theme.background)
                    .padding()
                    .background(Theme.teal)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                }
            }
            .padding()
            .background(Theme.background)
            .navigationTitle("Share to TextHelp")
        }
    }
}