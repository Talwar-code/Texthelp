//
//  AutoSizingTextEditor.swift
//  TextHelp
//
//  A UIKit‑backed text editor that automatically adjusts its height to
//  fit its contents.  This component uses a `UITextView` under the
//  hood and disables scrolling on the native view so that the SwiftUI
//  layout system drives the size.  The measured height is exposed via
//  a binding so that parent views can set their frame accordingly.
//

import SwiftUI

/// A text editor that grows and shrinks to fit its content.  The
/// `height` binding is updated whenever the content size changes.  The
/// hosting view should use this binding to set the text editor’s
/// height via `.frame(height: ...)`.
struct AutoSizingTextEditor: UIViewRepresentable {
    /// The backing string for the text editor.
    @Binding var text: String
    /// A bound height that the parent view should observe and apply to
    /// its frame.  The initial value should reflect the minimum
    /// desired height.  Updates occur asynchronously on the main
    /// queue.
    @Binding var height: CGFloat
    /// The font used inside the text view.  Defaults to the system
    /// body font.
    var font: UIFont = UIFont.systemFont(ofSize: 16)

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.font = font
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        // Defer the height calculation to the next runloop cycle to
        // allow UIKit to update the contentSize after text changes.
        DispatchQueue.main.async {
            let size = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude))
            // Guard against zero width (e.g. during initial layout)
            if size.height > 0 && self.height != size.height {
                self.height = size.height
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) {
            self.text = text
        }
        func textViewDidChange(_ textView: UITextView) {
            self.text.wrappedValue = textView.text ?? ""
        }
    }
}
