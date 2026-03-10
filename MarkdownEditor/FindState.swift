import Foundation

final class FindState {
    var searchText: String = ""
    var matches: [NSRange] = []
    var currentMatchIndex: Int = 0

    func search(in text: NSString, for query: String) {
        matches.removeAll()
        currentMatchIndex = 0
        guard !query.isEmpty else { return }

        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.location < text.length {
            let found = text.range(
                of: query,
                options: .caseInsensitive,
                range: searchRange
            )
            guard found.location != NSNotFound else { break }
            matches.append(found)
            searchRange.location = NSMaxRange(found)
            searchRange.length = text.length - searchRange.location
        }
    }

    func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }
}
