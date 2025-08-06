//
//  HomeView.swift
//  TextHelp
//
//  Presents a single Compose card and a tab bar to navigate between
//  Compose and History.

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var dataManager: DataManager
    @State private var selectedTab = 0
    @State private var showingImportSheet = false
    // Maintains the navigation path for programmatic navigation when a new
    // conversation is imported.  Without this we cannot push a
    // ComposeView after the sheet dismisses.
    @State private var navigationPath = NavigationPath()

    /// When true, the history tab icon scales up briefly to indicate a new draft has
    /// been saved.  The animation is triggered by observing the `.draftSaved`
    /// notification from DataManager.  After a short delay the value resets
    /// to false so that the icon returns to its normal size.
    @State private var animateHistoryIcon: Bool = false

    /// Text entered into the search field.  Use this to filter the list of
    /// contacts displayed on the home screen.  An empty search string
    /// returns all contacts.
    @State private var searchText: String = ""

    /// Computes the list of contacts matching the search query.  A
    /// contact matches if either the label or the body of the last
    /// real message contains the query text.  If no query is present the
    /// entire contact list is returned.
    private var filteredContacts: [Contact] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return dataManager.contacts }
        return dataManager.contacts.filter { contact in
            let nameMatch = contact.label.lowercased().contains(query)
            // Find the most recent non-draft, non-assistant message
            let lastReal = contact.messages.last(where: { msg in
                let senderLower = msg.sender.lowercased()
                return senderLower != "draft" && senderLower != "assistant"
            })
            let messageMatch = lastReal?.body.lowercased().contains(query) ?? false
            return nameMatch || messageMatch
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Compose tab with a NavigationStack and explicit navigation path
            NavigationStack(path: $navigationPath) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Intro header
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Welcome to TextHelp")
                                .font(Theme.headingFont(size: 28))
                                .foregroundColor(Theme.teal)
                            Text("AI‑powered message crafting")
                                .font(Theme.bodyFont())
                                .foregroundColor(.secondary)
                        }
                        // Compose button: opens the screenshot import sheet
                        Button(action: {
                            showingImportSheet = true
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Compose")
                                    .font(Theme.headingFont(size: 26))
                                    .foregroundColor(Theme.background)
                                Text("Upload a screenshot or pick a thread to start.")
                                    .font(Theme.bodyFont())
                                    .foregroundColor(Theme.background.opacity(0.8))
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.teal)
                            .cornerRadius(20)
                            .shadow(color: Theme.teal.opacity(0.4), radius: 4, x: 0, y: 2)
                        }

                        // Search bar to filter conversations
                        TextField("Search threads", text: $searchText)
                            .font(Theme.bodyFont())
                            .padding(12)
                            .background(Theme.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Theme.violet.opacity(0.5), lineWidth: 1)
                            )
                            .cornerRadius(16)
                            .foregroundColor(Theme.teal)

                        // Recent threads list
                        if dataManager.contacts.isEmpty {
                            // There are no conversations at all
                            Text("No conversations yet. Import a screenshot to get started!")
                                .font(Theme.bodyFont())
                                .foregroundColor(.secondary)
                        } else if filteredContacts.isEmpty {
                            // There are contacts, but none match the search query
                            Text("No threads match your search.")
                                .font(Theme.bodyFont())
                                .foregroundColor(.secondary)
                        } else {
                            Text("Recent Threads")
                                .font(Theme.headingFont(size: 22))
                                .foregroundColor(Theme.teal)
                            VStack(spacing: 12) {
                                ForEach(filteredContacts) { contact in
                                    NavigationLink(value: contact) {
                                        HStack(alignment: .top) {
                                            // Avatar circle with initials
                                            Circle()
                                                .fill(Theme.violet.opacity(0.7))
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    Text(String(contact.label.prefix(2)))
                                                        .font(Theme.bodyFont(size: 18))
                                                        .foregroundColor(Theme.background)
                                                )
                                            VStack(alignment: .leading, spacing: 4) {
                                                // Contact name
                                                Text(contact.label)
                                                    .font(Theme.headingFont(size: 20))
                                                    .foregroundColor(Theme.teal)
                                                // Last message snippet from a real sender
                                                if let lastReal = contact.messages.last(where: { msg in
                                                    let senderLower = msg.sender.lowercased()
                                                    return senderLower != "draft" && senderLower != "assistant"
                                                }) {
                                                    Text(lastReal.body)
                                                        .font(Theme.bodyFont())
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                } else {
                                                    Text("No messages yet")
                                                        .font(Theme.bodyFont())
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                            // Timestamp of last real message
                                            if let lastReal = contact.messages.last(where: { msg in
                                                let senderLower = msg.sender.lowercased()
                                                return senderLower != "draft" && senderLower != "assistant"
                                            }) {
                                                Text(dateAgo(lastReal.timestamp))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding()
                                        .background(Theme.background)
                                        .cornerRadius(16)
                                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 120)
                }
                .navigationDestination(for: Contact.self) { contact in
                    ComposeView(contact: contact)
                        .environmentObject(dataManager)
                }
                // Sheet for importing screenshots.  Once the import completes we
                // append the resulting contact onto the navigation path so the
                // user is taken directly into the conversation view.
                .sheet(isPresented: $showingImportSheet) {
                    ScreenshotImportView(mode: .reply) { importedLabel in
                        if let label = importedLabel,
                           let contact = dataManager.contacts.first(where: { $0.label == label }) {
                            // Delay pushing until the sheet has fully dismissed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                navigationPath.append(contact)
                            }
                        }
                    }
                    .environmentObject(dataManager)
                }
            }
            .tabItem {
                Label("Compose", systemImage: "square.and.pencil")
            }
            .tag(0)

            // History tab shows saved drafts
            HistoryView()
                .environmentObject(dataManager)
                .tabItem {
                    Label {
                        Text("History")
                    } icon: {
                        Image(systemName: "clock")
                            .scaleEffect(animateHistoryIcon ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 0.4), value: animateHistoryIcon)
                    }
                }
                .tag(1)
        }
        // Listen for draft saved notifications and trigger the history tab icon animation
        .onReceive(NotificationCenter.default.publisher(for: .draftSaved)) { _ in
            // Bump the history icon when a draft is saved
            animateHistoryIcon = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                animateHistoryIcon = false
            }
        }
    }

    /// Returns a relative time string (e.g., "2h", "3d") for display alongside the last message.
    private func dateAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minute = 60.0
        let hour = minute * 60
        let day = hour * 24
        if interval < minute {
            let seconds = Int(interval)
            return "\(seconds)s"
        } else if interval < hour {
            let minutes = Int(interval / minute)
            return "\(minutes)m"
        } else if interval < day {
            let hours = Int(interval / hour)
            return "\(hours)h"
        } else {
            let days = Int(interval / day)
            return "\(days)d"
        }
    }
}
