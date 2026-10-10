import Foundation

// Added for Luik (not part of upstream SwiftTerm): read-only access to the cursor position and to
// buffer rows in scroll-invariant coordinates, used to log the command the user ran — see
// LoggingTerminalView in the Luik target.
public extension Terminal {
    /// Row of the cursor counted from the start of the scrollback (the coordinate system of
    /// `getScrollInvariantLine(row:)`), so it keeps pointing at the same text when the screen scrolls.
    var cursorScrollInvariantRow: Int {
        buffer.yBase + buffer.y + buffer.linesTop
    }

    /// Column of the cursor, 0-based.
    var cursorColumn: Int {
        buffer.x
    }

    /// Text of a scroll-invariant row, optionally cut at `endCol`; nil when the row has left the scrollback.
    func scrollInvariantLineText(row: Int, endCol: Int = -1, trimRight: Bool = true) -> String? {
        guard let line = getScrollInvariantLine(row: row) else { return nil }
        return line.translateToString(trimRight: trimRight, startCol: 0, endCol: endCol)
    }

    /// True when the scroll-invariant row is the soft-wrapped continuation of the row above it.
    func scrollInvariantLineIsWrapped(row: Int) -> Bool {
        getScrollInvariantLine(row: row)?.isWrapped ?? false
    }
}
