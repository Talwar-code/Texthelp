//
//  HistoryView.swift
//  TextHelp
//
//  Created by Arjun Talwar on 8/4/25.
//


//
//  HistoryView.swift
//  TextHelp
//
//  Shows a list of draft messages saved from Reply, Refine, or Insight.
//  Users can tap a draft to re-enter it in ComposeView’s Revise mode,
//  continuing to refine and save back.

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var dataManager: DataManager

    var body: some View {
        NavigationStack {
            List {
                ForEach(dataManager.contacts) { contact in
                    // Filter only drafts (sender == "Draft")
                    let drafts = contact.messages.filter { $0.sender == "Draft" }
                    if !drafts.isEmpty {
                        Section(header: Text(contact.label)) {
                            ForEach(drafts) { draft in
                                NavigationLink {
                                    ComposeView(contact: contact, draft: draft, initialMode: .revise)
                                        .environmentObject(dataManager)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(draft.body)
                                            .font(Theme.bodyFont())
                                            .lineLimit(2)
                                        Text(draft.timestamp, style: .relative)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .onDelete { idxSet in
                                for idx in idxSet {
                                    let removed = drafts[idx]
                                    if let contactIndex = dataManager.contacts.firstIndex(where: { $0.id == contact.id }),
                                       let draftIndex = dataManager.contacts[contactIndex].messages.firstIndex(where: { $0.id == removed.id }) {
                                        dataManager.contacts[contactIndex].messages.remove(at: draftIndex)
                                    }
                                }
                                dataManager.persist()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Drafts")
        }
    }
}
