import SwiftUI

final class TableOfContentsModel: ObservableObject {
    /// Exactly what the sidebar renders — no character range. See `update`.
    struct Item: Identifiable, Equatable {
        /// The heading's ordinal position in the document. Stable across
        /// edits in a way a fresh UUID per rebuild was not: previously every
        /// rebuild minted new ids, so `ForEach` saw an entirely new set of
        /// rows and tore down and recreated the whole sidebar — on every
        /// keystroke, since `updateTOC` runs from `textDidChange`.
        let id: Int
        let level: Int
        let title: String
    }

    @Published private(set) var items: [Item] = []

    /// Character ranges for each item, parallel to `items`. Deliberately not
    /// published and not part of `Item`: every keystroke above a heading
    /// shifts its range, so including them would re-publish the outline
    /// constantly even though nothing the sidebar draws had changed.
    private var ranges: [NSRange] = []

    var onSelect: ((NSRange) -> Void)?

    func update(headings: [(range: NSRange, level: Int, title: String)]) {
        ranges = headings.map(\.range)
        let rebuilt = headings.enumerated().map { index, heading in
            Item(id: index, level: heading.level, title: heading.title)
        }
        // Only publish when the visible outline actually changed, which for
        // ordinary typing is almost never.
        if rebuilt != items { items = rebuilt }
    }

    func select(_ item: Item) {
        guard ranges.indices.contains(item.id) else { return }
        onSelect?(ranges[item.id])
    }
}

struct TableOfContentsView: View {
    @ObservedObject var model: TableOfContentsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(model.items) { item in
                    Button {
                        model.select(item)
                    } label: {
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .font(.system(size: fontSize(for: item.level), weight: item.level <= 2 ? .semibold : .regular))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, CGFloat(item.level - 1) * 12)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func fontSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 13
        case 2: return 12.5
        default: return 12
        }
    }
}
