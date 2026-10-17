import AppKit

/// Pure placement logic for a newly opened document window, split out of
/// `MarkdownScrollView` so it can be unit tested without real windows.
///
/// Every new window starts from the same remembered frame. When several open
/// at once (e.g. two files opened together from Finder), the later ones would
/// land exactly on top of the first, so each is cascaded down and to the right
/// until it reaches a top-left corner no other document window occupies.
enum WindowFramePlacement {
    /// How far each cascaded window shifts right and down — roughly one title bar.
    static let cascadeOffset: CGFloat = 28
    /// Two windows whose top-left corners are this close count as stacked.
    static let matchTolerance: CGFloat = 2

    /// - Parameters:
    ///   - frame: the remembered frame the new window starts from.
    ///   - occupied: frames of the other document windows already open.
    ///   - visibleFrame: the screen's usable area; a cascade that would run off
    ///     its right or bottom edge wraps back to the top-left corner.
    static func placement(for frame: NSRect, avoiding occupied: [NSRect], within visibleFrame: NSRect?) -> NSRect {
        var candidate = frame
        // Each step either finds a free corner or moves past one occupied window,
        // so occupied.count + 1 steps always suffice without wrapping; the bound
        // also guarantees termination if wrapping lands back on a taken corner.
        for _ in 0...occupied.count {
            guard occupied.contains(where: { sharesTopLeft($0, candidate) }) else { return candidate }
            candidate.origin.x += cascadeOffset
            candidate.origin.y -= cascadeOffset
            if let visibleFrame, candidate.maxX > visibleFrame.maxX || candidate.minY < visibleFrame.minY {
                candidate.origin = NSPoint(x: visibleFrame.minX, y: visibleFrame.maxY - candidate.height)
            }
        }
        return candidate
    }

    private static func sharesTopLeft(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) <= matchTolerance && abs(a.maxY - b.maxY) <= matchTolerance
    }
}
