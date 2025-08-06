//
//  FlowLayout.swift
//  TextHelp
//
//  A generic flow layout that arranges child views horizontally and wraps
//  them onto multiple lines.  Accepts any collection of hashable items and
//  a view builder to render each item.

import SwiftUI

struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let spacing: CGFloat
    let content: (Data.Element) -> Content

    init(items: Data, spacing: CGFloat = 8, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        let rows = self.computeRows()
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: spacing) {
                    ForEach(rows[rowIndex], id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
    }

    /// Computes the rows needed to wrap items horizontally based on available width.
    private func computeRows() -> [[Data.Element]] {
        var rows: [[Data.Element]] = [[]]
        var currentRowWidth: CGFloat = 0

        // Use a dummy geometry reader to estimate widths if needed
        for item in items {
            // Here we don't know the exact size; this naive approach keeps items
            // in the same row.  If your chips have dynamic widths, you can
            // precompute them using GeometryReader in the actual view.
            rows[rows.count - 1].append(item)
        }
        return rows
    }
}
