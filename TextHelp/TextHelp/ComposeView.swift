//
//  ComposeView.swift
//  TextHelp
//
//  Updated for interactive suggestion chips, custom instructions, draft saving,
//  larger text boxes, consistent green bubbles, better keyboard handling, and
//  dynamic navigation header.  Use this file to replace the existing one.

import SwiftUI
import UIKit
import Combine

struct ComposeView: View {
    @EnvironmentObject private var dataManager: DataManager
    var contact: Contact

    // Tracks conversation messages
    @State private var messages: [Message] = []
    // Tracks dynamic suggestions from the AI
    @State private var replySuggestions: [String] = []
    // Fallback suggestions when AI fails or is loading
    private let fallbackSuggestions = ["Friendly", "Decline", "Make a plan"]
    // Whether the user has chosen to enter a custom goal instead of using a preset
    @State private var showCustomGoal: Bool = false

    // Unified mode selector
    enum Mode: String, CaseIterable, Identifiable {
        case reply = "Reply"
        case revise = "Refine"
        case insight = "Insight"
        var id: String { rawValue }
    }
    @State private var mode: Mode
    // For multi-step replies (unused, left for future)
    @State private var multiStep: Bool = false
    // Loading state
    @State private var isProcessing: Bool = false

    // Inputs and outputs for each mode
    @State private var goal: String = ""
    @State private var generatedReplies: [String] = []
    @State private var originalMessage: String = ""
    @State private var adjustedMessage: String? = nil
    @State private var helpPrompt: String = ""
    @State private var helpResponse: String? = nil
    @State private var helpConversation: String = ""

    // Custom tone and instructions
    @State private var showCustomTone: Bool = false
    @State private var customToneInstructions: String = ""

    // Chat history for multiple turns
    @State private var chatHistory: [ChatMessage] = []
    @State private var chatInput: String = ""

    // Dynamic heights for growing text editors
    @State private var goalHeight: CGFloat = 40
    @State private var originalHeight: CGFloat = 80
    @State private var customToneHeight: CGFloat = 80
    @State private var helpConversationHeight: CGFloat = 80
    @State private var helpPromptHeight: CGFloat = 80
    @State private var chatInputHeight: CGFloat = 40

    // ScrollView proxy for programmatic scrolling
    @State private var scrollProxy: ScrollViewProxy? = nil

    // Draft selected from History
    var draft: Message?

    init(contact: Contact, draft: Message? = nil, initialMode: Mode = .reply) {
        self.contact = contact
        self._mode = State(initialValue: initialMode)
        self.draft = draft
    }

    /// Returns an appropriate workshop title for the bottom chat box based on the current mode.
    private var workshopTitle: String {
        switch mode {
        case .reply:
            return "Workshop Reply"
        case .revise:
            return "Workshop Refinement"
        case .insight:
            return "Workshop Insight"
        }
    }

    var body: some View {
        // Compose view consists of a pinned header and a scrollable content
        VStack(alignment: .leading, spacing: 0) {
            // Pinned header
            Text("Recent messages with \(contact.label)")
                .font(Theme.headingFont(size: 24))
                .foregroundColor(Theme.teal)
                .padding(.top, 16)
                .padding(.horizontal)
                .background(Theme.background)
            // Scrollable content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Conversation preview or fallback text input
                        if messages.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Paste or type your conversation (optional)")
                                    .font(Theme.bodyFont())
                                    .foregroundColor(.secondary)
                                ZStack(alignment: .topLeading) {
                                    AutoSizingTextEditor(text: $helpConversation, height: $helpConversationHeight, font: UIFont.systemFont(ofSize: 16))
                                        .frame(minHeight: 80, maxHeight: min(200, helpConversationHeight))
                                        .padding(8)
                                        .background(Theme.background)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Theme.violet.opacity(0.5), lineWidth: 1)
                                        )
                                        .cornerRadius(16)
                                    if helpConversation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("Paste or type your conversation…")
                                            .font(Theme.bodyFont())
                                            .foregroundColor(.secondary)
                                            .padding(16)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(messages) { message in
                                        MessageRow(message: message,
                                                   isUser: message.sender.lowercased() == "you",
                                                   onTap: {
                                            if mode == .revise {
                                                originalMessage = message.body
                                            }
                                        })
                                        .frame(maxWidth: .infinity,
                                               alignment: message.sender.lowercased() == "you" ? .trailing : .leading)
                                    }
                                }
                            }
                            .frame(minHeight: 150, maxHeight: 350)
                            .padding(.vertical, 4)
                        }

                        // Mode picker (Reply, Refine, Insight)
                        Picker("Mode", selection: $mode) {
                            ForEach(Mode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .accentColor(Theme.teal)
                        .padding(.top, 16)

                        // Mode-specific UI
                        Group {
                            switch mode {
                            case .reply:
                                replySection
                            case .revise:
                                reviseSection
                            case .insight:
                                insightSection
                            }
                        }

                        // Multi-turn chat for clarifications
                        if !chatHistory.isEmpty {
                            Text("Refine your reply")
                                .font(Theme.headingFont(size: 20))
                                .foregroundColor(Theme.violet)
                            ForEach(chatHistory) { msg in
                                HStack {
                                    if msg.role == "user" { Spacer() }
                                    VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 4) {
                                        Text(msg.text)
                                            .font(Theme.bodyFont())
                                            .foregroundColor(msg.role == "user" ? Theme.background : Color.white)
                                            .padding(10)
                                            .background(msg.role == "user" ? Theme.userBubble : Theme.otherBubble)
                                            .cornerRadius(16)
                                    }
                                    if msg.role == "assistant" { Spacer() }
                                }
                            }
                        }

                        // Chat input at bottom if there are generated, refined, or insight messages
                        if !generatedReplies.isEmpty || adjustedMessage != nil || helpResponse != nil {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workshopTitle)
                                    .font(Theme.headingFont(size: 18))
                                    .foregroundColor(Theme.violet)
                                HStack {
                                    AutoSizingTextEditor(text: $chatInput, height: $chatInputHeight, font: UIFont.systemFont(ofSize: 16))
                                        .frame(minHeight: 40, maxHeight: min(120, chatInputHeight))
                                        .padding(8)
                                        .background(Theme.background)
                                        .overlay(RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Theme.violet.opacity(0.5), lineWidth: 1))
                                        .cornerRadius(12)
                                    Button(action: {
                                        hideKeyboard()
                                        sendChat()
                                        scrollToBottom()
                                    }) {
                                        Image(systemName: "paperplane.fill")
                                            .foregroundColor(Theme.background)
                                            .padding(12)
                                            .background(Theme.teal)
                                            .clipShape(Circle())
                                    }
                                    .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                                }
                            }
                        }

                        // Bottom spacer for scroll target
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                    // Extra bottom padding to avoid the keyboard covering content
                    .padding(.bottom, 300)
                }
                .background(Theme.background)
                .onAppear {
                    self.scrollProxy = proxy
                }
            }
        }
        .background(Theme.background)
        .navigationBarHidden(false)
        .onTapGesture {
            self.hideKeyboard()
        }
        .onAppear {
            loadMessages()
            if draft != nil {
                originalMessage = draft?.body ?? ""
                mode = .revise
            }
            dataManager.fetchReplySuggestions(for: contact) { suggestions in
                replySuggestions = suggestions.isEmpty ? fallbackSuggestions : suggestions
            }
        }
    }

    // Load and sort messages from the data manager
    private func loadMessages() {
        messages = contact.messages.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Reply Section

    private var replySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What would you like to say?")
                .font(Theme.headingFont(size: 20))
                .foregroundColor(Theme.violet)

            // Suggestions and custom goal chips displayed in a wrap‑around grid.
            let columns: [GridItem] = [GridItem(.adaptive(minimum: 80), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(replySuggestions, id: \.self) { suggestion in
                    Button(action: {
                        hideKeyboard()
                        showCustomGoal = false
                        goal = suggestion
                        generateReply()
                    }) {
                        Text(suggestion)
                            .font(Theme.bodyFont())
                            .foregroundColor(Theme.background)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.teal)
                            .cornerRadius(16)
                    }
                }
                // Custom goal entry
                Button(action: {
                    hideKeyboard()
                    showCustomGoal.toggle()
                    if showCustomGoal {
                        goal = ""
                    }
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Custom…")
                    }
                    .font(Theme.bodyFont())
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.secondaryAccent)
                    .cornerRadius(16)
                }
            }
            .padding(.vertical, 4)

            // Custom goal text editor when user opts to type a goal
            if showCustomGoal {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $goal)
                        .font(Theme.bodyFont())
                        .frame(minHeight: 200)
                        .padding(8)
                        .background(Theme.background)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                                    .stroke(Theme.violet.opacity(0.5), lineWidth: 1))
                        .cornerRadius(16)
                        .onTapGesture { }
                    if goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Describe what you want to convey…")
                            .font(Theme.bodyFont())
                            .foregroundColor(.secondary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Generate reply button
            Button(action: {
                hideKeyboard()
                generateReply()
            }) {
                HStack {
                    Spacer()
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("Generate Reply")
                            .font(Theme.bodyFont(size: 18))
                            .foregroundColor(Theme.background)
                    }
                    Spacer()
                }
            }
            .padding()
            .background(Theme.teal)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            .disabled(isProcessing || (showCustomGoal && goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

            // Display generated replies with save buttons
            if !generatedReplies.isEmpty {
                Text("Assistant’s Reply")
                    .font(Theme.headingFont(size: 20))
                    .foregroundColor(Theme.violet)
                ForEach(generatedReplies.indices, id: \.self) { idx in
                    VStack(spacing: 8) {
                        TextEditor(text: Binding(
                            get: { generatedReplies[idx] },
                            set: { generatedReplies[idx] = $0 }
                        ))
                        .font(Theme.bodyFont())
                        .frame(minHeight: 200)
                        .padding(8)
                        .background(Theme.background)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                                    .stroke(Theme.violet.opacity(0.5), lineWidth: 1))
                        .cornerRadius(16)
                        Button(action: {
                            dataManager.saveDraft(generatedReplies[idx], to: contact)
                        }) {
                            HStack {
                                Spacer()
                                Text("Save Draft")
                                    .font(Theme.bodyFont(size: 16))
                                    .foregroundColor(Theme.background)
                                Spacer()
                            }
                        }
                        .padding(8)
                        .background(Theme.teal)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                }
            }
        }
    }

    // MARK: - Refine Section

    private var reviseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your draft")
                .font(Theme.headingFont(size: 20))
                .foregroundColor(Theme.violet)

            // Draft input with placeholder and dynamic height
            ZStack(alignment: .topLeading) {
                AutoSizingTextEditor(text: $originalMessage, height: $originalHeight, font: UIFont.systemFont(ofSize: 16))
                    .frame(minHeight: 80, maxHeight: min(200, originalHeight))
                    .padding(8)
                    .background(Theme.background)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.violet.opacity(0.5), lineWidth: 1))
                    .cornerRadius(16)
                    .onTapGesture { }
                if originalMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Tap on a message above to review it or type/paste a message for help.")
                        .font(Theme.bodyFont())
                        .foregroundColor(.secondary)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }

            // Tone presets and custom toggle displayed in a grid
            let toneColumns: [GridItem] = [GridItem(.adaptive(minimum: 80), spacing: 8)]
            LazyVGrid(columns: toneColumns, alignment: .leading, spacing: 8) {
                ForEach(["Softer", "Shorter", "More Direct"], id: \.self) { tone in
                    Button(action: {
                        hideKeyboard()
                        applyTonePreset(tone)
                    }) {
                        Text(tone)
                            .font(Theme.bodyFont())
                            .foregroundColor(Theme.background)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.teal)
                            .cornerRadius(16)
                    }
                }
                Button(action: {
                    hideKeyboard()
                    showCustomTone.toggle()
                    if showCustomTone {
                        customToneInstructions = ""
                    }
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Custom…")
                    }
                    .font(Theme.bodyFont())
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.secondaryAccent)
                    .cornerRadius(16)
                }
            }

            // Custom tone input with dynamic height
            if showCustomTone {
                ZStack(alignment: .topLeading) {
                    AutoSizingTextEditor(text: $customToneInstructions, height: $customToneHeight, font: UIFont.systemFont(ofSize: 16))
                        .frame(minHeight: 80, maxHeight: min(200, customToneHeight))
                        .padding(8)
                        .background(Theme.background)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                                    .stroke(Theme.violet.opacity(0.5), lineWidth: 1))
                        .cornerRadius(16)
                    if customToneInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Describe how you want the message refined…")
                            .font(Theme.bodyFont())
                            .foregroundColor(.secondary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Single action button with dynamic title
            Button(action: {
                hideKeyboard()
                if showCustomTone {
                    adjustWithCustomTone()
                } else {
                    adjust()
                }
            }) {
                HStack {
                    Spacer()
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text(showCustomTone ? "Apply Custom Tone" : "Refine Message")
                            .font(Theme.bodyFont(size: 18))
                            .foregroundColor(Theme.background)
                    }
                    Spacer()
                }
            }
            .padding()
            .background(Theme.teal)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            .disabled(isProcessing || originalMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (showCustomTone && customToneInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

            // Show the refined result and save option
            if let refined = adjustedMessage {
                Text("Assistant’s Refinement")
                    .font(Theme.headingFont(size: 20))
                    .foregroundColor(Theme.violet)
                TextEditor(text: Binding(get: {
                    refined
                }, set: { newVal in
                    adjustedMessage = newVal
                }))
                .font(Theme.bodyFont())
                .frame(minHeight: 200)
                .padding(8)
                .background(Theme.background)
                .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.violet.opacity(0.5), lineWidth: 1))
                .cornerRadius(16)
                Button(action: {
                    dataManager.saveDraft(refined, to: contact)
                }) {
                    HStack {
                        Spacer()
                        Text("Save Draft")
                            .font(Theme.bodyFont(size: 18))
                            .foregroundColor(Theme.background)
                        Spacer()
                    }
                }
                .padding()
                .background(Theme.teal)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            }
        }
    }

    // MARK: - Insight Section

    private var insightSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What do you want to know?")
                .font(Theme.headingFont(size: 20))
                .foregroundColor(Theme.violet)

            // Quick-pick questions and custom toggle displayed in a grid.
            let insightOptions = ["Better closing line", "Tone check: is this rude?", "Next steps?", "Summarize thread"]
            let insightCols: [GridItem] = [GridItem(.adaptive(minimum: 120), spacing: 8)]
            LazyVGrid(columns: insightCols, alignment: .leading, spacing: 8) {
                ForEach(insightOptions, id: \.self) { quick in
                    Button(action: {
                        hideKeyboard()
                        helpPrompt = quick
                        help()
                    }) {
                        Text(quick)
                            .font(Theme.bodyFont())
                            .foregroundColor(Theme.background)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.teal)
                            .cornerRadius(16)
                    }
                }
                Button(action: {
                    hideKeyboard()
                    helpPrompt = ""
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Custom…")
                    }
                    .font(Theme.bodyFont())
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.secondaryAccent)
                    .cornerRadius(16)
                }
            }

            // Insight prompt editor with dynamic height
            ZStack(alignment: .topLeading) {
                AutoSizingTextEditor(text: $helpPrompt, height: $helpPromptHeight, font: UIFont.systemFont(ofSize: 16))
                    .frame(minHeight: 80, maxHeight: min(200, helpPromptHeight))
                    .padding(8)
                    .background(Theme.background)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.violet.opacity(0.5), lineWidth: 1))
                    .cornerRadius(16)
                if helpPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Ask a question about this conversation…")
                        .font(Theme.bodyFont())
                        .foregroundColor(.secondary)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }

            // Get insight button
            Button(action: {
                hideKeyboard()
                help()
            }) {
                HStack {
                    Spacer()
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("Get Insight")
                            .font(Theme.bodyFont(size: 18))
                            .foregroundColor(Theme.background)
                    }
                    Spacer()
                }
            }
            .padding()
            .background(Theme.teal)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            .disabled(isProcessing || helpPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Display insight result with save option
            if let insight = helpResponse {
                Text("Assistant’s Insight")
                    .font(Theme.headingFont(size: 20))
                    .foregroundColor(Theme.violet)
                TextEditor(text: Binding(get: {
                    insight
                }, set: { newVal in
                    helpResponse = newVal
                }))
                .font(Theme.bodyFont())
                .frame(minHeight: 200)
                .padding(8)
                .background(Theme.background)
                .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.violet.opacity(0.5), lineWidth: 1))
                .cornerRadius(16)
                Button(action: {
                    dataManager.saveDraft(insight, to: contact)
                }) {
                    HStack {
                        Spacer()
                        Text("Save Draft")
                            .font(Theme.bodyFont(size: 18))
                            .foregroundColor(Theme.background)
                        Spacer()
                    }
                }
                .padding()
                .background(Theme.teal)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
            }
        }
    }

    // MARK: - Interaction Helpers

    private func generateReply() {
        guard !isProcessing else { return }
        isProcessing = true
        generatedReplies = []
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        dataManager.generateReply(for: contact, goal: trimmedGoal.isEmpty ? "Friendly" : trimmedGoal, multiStep: multiStep) { result in
            isProcessing = false
            switch result {
            case .success(let messages):
                generatedReplies = messages.map { $0.body }
            case .failure(let error):
                generatedReplies = ["Error: \(error.localizedDescription)"]
            }
            scrollToBottom()
        }
    }

    private func applyTonePreset(_ preset: String) {
        let instruction: String
        switch preset {
        case "Softer":
            instruction = "Please make this softer."
        case "Shorter":
            instruction = "Please make this shorter."
        case "More Direct":
            instruction = "Please make this more direct."
        default:
            instruction = ""
        }
        guard !originalMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isProcessing = true
        dataManager.adjustMessage(for: contact, original: originalMessage, instructions: instruction) { result in
            isProcessing = false
            switch result {
            case .success(let adjusted):
                adjustedMessage = adjusted
            case .failure(let error):
                adjustedMessage = "Error: \(error.localizedDescription)"
            }
            scrollToBottom()
        }
    }

    private func adjust() {
        let defaultInstruction = "Please improve tone, clarity and friendliness while preserving intent."
        guard !originalMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isProcessing = true
        dataManager.adjustMessage(for: contact, original: originalMessage, instructions: defaultInstruction) { result in
            isProcessing = false
            switch result {
            case .success(let adjusted):
                adjustedMessage = adjusted
            case .failure(let error):
                adjustedMessage = "Error: \(error.localizedDescription)"
            }
            scrollToBottom()
        }
    }

    private func adjustWithCustomTone() {
        guard !customToneInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isProcessing = true
        dataManager.adjustMessage(for: contact, original: originalMessage, instructions: customToneInstructions) { result in
            isProcessing = false
            showCustomTone = false
            switch result {
            case .success(let adjusted):
                adjustedMessage = adjusted
            case .failure(let error):
                adjustedMessage = "Error: \(error.localizedDescription)"
            }
            scrollToBottom()
        }
    }

    private func help() {
        var prompt = helpPrompt
        if !helpConversation.isEmpty {
            prompt = helpConversation + "\n\n" + prompt
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isProcessing = true
        dataManager.textHelp(for: contact, prompt: prompt) { result in
            isProcessing = false
            switch result {
            case .success(let reply):
                helpResponse = reply
            case .failure(let error):
                helpResponse = "Error: \(error.localizedDescription)"
            }
            scrollToBottom()
        }
    }

    private func sendChat() {
        let trimmed = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatHistory.append(ChatMessage(role: "user", text: trimmed))
        chatInput = ""
        isProcessing = true
        dataManager.textHelp(for: contact, prompt: trimmed) { result in
            isProcessing = false
            switch result {
            case .success(let reply):
                chatHistory.append(ChatMessage(role: "assistant", text: reply))
            case .failure(let error):
                chatHistory.append(ChatMessage(role: "assistant", text: "Error: \(error.localizedDescription)"))
            }
            scrollToBottom()
        }
    }

    // Internal chat message representation
    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: String
        let text: String
    }

    /// Scrolls to the bottom of the ScrollView containing the conversation and assistant
    /// responses.  Uses the stored `scrollProxy` to jump to the view with the
    /// identifier "bottom".
    private func scrollToBottom() {
        DispatchQueue.main.async {
            if let proxy = scrollProxy {
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

/// A single message row in the conversation preview.
private struct MessageRow: View {
    let message: Message
    let isUser: Bool
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack {
            if isUser { Spacer() }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .font(Theme.bodyFont())
                    .foregroundColor(isUser ? Theme.background : Color.white)
                    .padding(12)
                    .background(isUser ? Theme.userBubble : Theme.otherBubble)
                    .cornerRadius(20)
                Text(message.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !isUser { Spacer() }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Keyboard Dismissal Helper

extension View {
    /// Hides the keyboard by sending a resignFirstResponder action to the
    /// current first responder.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
