import SwiftUI

final class TableOfContentsModel: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let range: NSRange
        let level: Int
        let title: String
    }

    @Published var items: [Item] = []
    var onSelect: ((NSRange) -> Void)?
}

struct TableOfContentsView: View {
    @ObservedObject var model: TableOfContentsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(model.items) { item in
                    Button {
                        model.onSelect?(item.range)
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
