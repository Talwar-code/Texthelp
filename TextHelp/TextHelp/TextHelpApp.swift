//
//  TextHelpApp.swift
//  TextHelp
//
//  Created by OpenAI Assistant on 2025‑07‑22.
//

import SwiftUI

/// The top level entry point for the TextHelp application.
///
/// This struct initialises a `DataManager` and injects it into the
/// environment so that all child views have access to the contact list,
/// pending imports and any other persistent data.  The `@main` attribute
/// tells SwiftUI that this is the starting point of the app.
@main
struct TextHelpApp: App {
    /// A shared data manager responsible for loading and saving contacts,
    /// processing imports from the share extension and coordinating with
    /// the language model.
    @StateObject private var dataManager = DataManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
                // With screenshot‑based imports there is no need to check for
                // pending share extension files on launch.
                // Apply the dark colour scheme globally
                .preferredColorScheme(.dark)
                // Set the global tint colour to the neon teal accent
                .tint(Theme.teal)
                // Set the global background colour
                .background(Theme.background)
        }
    }
}