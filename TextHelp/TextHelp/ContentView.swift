//
//  ContentView.swift
//  TextHelp
//
//  This legacy root view now simply delegates to HomeView.
//  It remains in the project to satisfy existing references.

import SwiftUI

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}
