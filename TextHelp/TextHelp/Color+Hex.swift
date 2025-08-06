//
//  Color+Hex.swift
//  TextHelp
//
//  Adds convenience initialisers to SwiftUI’s `Color` type to allow
//  creation from hexadecimal colour strings.  Supports 6‑digit
//  (RGB) and 8‑digit (RGBA) hex codes with or without the leading
//  hash symbol.

import SwiftUI

extension Color {
    /// Create a colour from a hexadecimal string.  Accepts strings
    /// in the form `"#RRGGBB"`, `"RRGGBB"`, `"#RRGGBBAA"` or
    /// `"RRGGBBAA"`.  If the string is invalid black is used.
    init(hex: String) {
        var hexString = hex
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        let r, g, b, a: Double
        switch hexString.count {
        case 6:
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        case 8:
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}