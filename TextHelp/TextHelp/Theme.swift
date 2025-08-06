//
//  Theme.swift
//  TextHelp
//
//  Defines the visual style for the TextHelp application, including
//  colours and fonts.  The dark charcoal background and emerald and
//  violet accents are specified here so that they can be reused
//  throughout the SwiftUI views.

import SwiftUI

struct Theme {
    /// Primary background colour for the entire app (dark charcoal)
    static let background = Color(hex: "#1A1A1D")
    /// Primary accent colour used across the application for active
    /// elements such as the segmented control and primary buttons.  A
    /// bright emerald (#1DD185) delivers high contrast against the dark
    /// background while remaining softer than the original neon teal.
    static let teal = Color(hex: "#1DD185")
    /// Secondary accent used for less prominent highlights and inactive
    /// elements.  This is derived from the primary accent with a
    /// decreased opacity to tone it down.  It is used for inactive
    /// segmented tabs and secondary buttons.
    static let secondaryAccent = Color(hex: "#1DD185").opacity(0.6)
    /// Vibrant violet accent used for supplementary highlights such as
    /// section headers and avatar backgrounds.  This provides visual
    /// variety while keeping the colour palette limited.
    static let violet = Color(hex: "#B934FF")
    /// Brighter violet used for message bubbles and other UI where
    /// higher contrast is needed.  This colour is a slightly lighter
    /// variant of the primary violet to improve legibility against
    /// dark text.
    static let brightViolet = Color(hex: "#C263F2")

    /// Colour used for the user's message bubble.  This mirrors the
    /// primary accent.  In earlier versions this used an opacity of 0.8
    /// but feedback showed the colour lacked vibrancy and was
    /// inconsistent with other green accents.  We now use the full
    /// `teal` colour so that all green elements (buttons, chips and
    /// bubbles) share the same bright hue.  The foreground text on
    /// this bubble should contrast appropriately (e.g. dark text on a
    /// light bubble).
    static let userBubble = teal

    /// Colour used for the contact's message bubble.  This uses the
    /// brighter violet variant to ensure the body text remains legible.
    static let otherBubble = brightViolet

    /// Heading font.  If the Montserrat font is included in the
    /// project assets it will be used; otherwise the system bold
    /// font of equivalent size acts as a fallback.
    static func headingFont(size: CGFloat = 48) -> Font {
        if let _ = UIFont(name: "Montserrat-Bold", size: size) {
            return Font.custom("Montserrat-Bold", size: size)
        }
        return Font.system(size: size, weight: .bold)
    }
    /// Body font.  If the Inter font is available it will be used;
    /// otherwise the system font is used.
    static func bodyFont(size: CGFloat = 16) -> Font {
        if let _ = UIFont(name: "Inter-Regular", size: size) {
            return Font.custom("Inter-Regular", size: size)
        }
        return Font.system(size: size)
    }
}
