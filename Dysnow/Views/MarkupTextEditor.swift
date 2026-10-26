import AppKit
import SwiftUI

/// The text editor: plain text, with the speech tags shown dimmed,
/// Control-Space to write them (see `MarkupCompleter`), and what changed
/// since `original` marked: changed and added text on a coloured ground,
/// showing what was there when hovered, a red mark where text was deleted,
/// and a menu on each to restore it or keep it.
struct MarkupTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    /// What the changes are shown against; empty for none.
    @Binding var original: String
    let syntax: MarkupSyntax
    var isEditable = true
    /// Made when Control-Space is pressed, with what to offer there.
    let completer: () -> MarkupCompleter

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkupTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        // Curly quotes and dashes would break the tags.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.followEditorFont()
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.makeCompleter = completer
        textView.syntax = syntax
        textView.original = original
        textView.keep = { [coordinator = context.coordinator] in coordinator.parent.original = $0 }
        textView.refreshMarks()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkupTextView else { return }
        context.coordinator.parent = self
        textView.makeCompleter = completer
        textView.isEditable = isEditable
        var highlight = false
        if textView.original != original {
            textView.original = original
            highlight = true
        }
        if textView.syntax.opener != syntax.opener {
            textView.syntax = syntax
            highlight = true
        }
        if textView.string != text {
            textView.string = text
            highlight = true
        }
        if highlight { textView.refreshMarks() }
        let length = (textView.string as NSString).length
        let wanted = NSRange(location: min(selection.location, length),
                             length: min(selection.length, length - min(selection.location, length)))
        if textView.selectedRange() != wanted {
            textView.setSelectedRange(wanted)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkupTextEditor

        init(_ parent: MarkupTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkupTextView else { return }
            textView.refreshMarks()
            parent.text = textView.string
            parent.selection = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            if parent.selection != range { parent.selection = range }
        }
    }
}

/// Completes the speech tags on Control-Space, or on the system's complete
/// command (Option-Escape), with a menu at the cursor when there is more
/// than one way to go on.
final class MarkupTextView: NSTextView, NSViewToolTipOwner {
    var makeCompleter: (() -> MarkupCompleter)?
    var syntax = MarkupSyntax.markdown
    /// The choices of the menu shown.
    private var offered: [MarkupCompleter.Choice] = []

    private var fontObserver: NSObjectProtocol?

    /// Takes the font from the settings, now and whenever they change. The
    /// editor follows them itself: were the font handed down from SwiftUI,
    /// each change in the Settings window would redraw the main window, and
    /// bring it in front of the Settings window.
    func followEditorFont() {
        font = EditorSettings.font
        guard fontObserver == nil else { return }
        fontObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                              object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.font != EditorSettings.font else { return }
                self.font = EditorSettings.font
                self.refreshMarks()
            }
        }
    }

    /// Texts longer than this are not coloured: going through them on each
    /// key pressed would slow typing down.
    private static let highlightLimit = 300_000

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control,
           event.charactersIgnoringModifiers == " " {
            completeMarkup(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func complete(_ sender: Any?) {
        completeMarkup(sender)
    }

    /// The Speech menu's Complete Markup, and Control-Space.
    @objc func completeMarkup(_ sender: Any?) {
        guard let completer = makeCompleter?(), let range = Range(selectedRange(), in: string) else { return }
        let choices = completer.choices(in: string, selection: range)
        switch choices.count {
        case 0:
            NSSound.beep()
        case 1:
            make(choices[0])
        default:
            offer(choices)
        }
    }

    private func offer(_ choices: [MarkupCompleter.Choice]) {
        offered = choices
        let menu = NSMenu()
        for (index, choice) in choices.enumerated() {
            let item = NSMenuItem(title: choice.title, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        // Positioned on its first item, which is then the one chosen.
        menu.popUp(positioning: menu.items.first, at: caretPoint, in: self)
    }

    @objc private func pick(_ item: NSMenuItem) {
        guard offered.indices.contains(item.tag) else { return }
        let choice = offered[item.tag]
        offered = []
        // After the menu has closed: the next one may open right away.
        Task { @MainActor in self.make(choice) }
    }

    private func make(_ choice: MarkupCompleter.Choice) {
        // The choices were made of the text as it is: the menu is modal.
        guard choice.edit.range.upperBound <= string.endIndex else { return }
        let edited = NSRange(choice.edit.range, in: string)
        guard shouldChangeText(in: edited, replacementString: choice.edit.replacement) else { return }
        replaceCharacters(in: edited, with: choice.edit.replacement)
        didChangeText()
        setSelectedRange(NSRange(location: edited.location + choice.edit.selection.lowerBound,
                                 length: choice.edit.selection.count))
        if choice.completesFurther {
            Task { @MainActor in self.completeMarkup(nil) }
        }
    }

    /// Just below the cursor, where the menu goes.
    private var caretPoint: NSPoint {
        let screenRect = firstRect(forCharacterRange: NSRange(location: selectedRange().location, length: 0),
                                   actualRange: nil)
        guard let window, screenRect != .zero else { return NSPoint(x: textContainerInset.width, y: 0) }
        let rect = convert(window.convertFromScreen(screenRect), from: nil)
        return NSPoint(x: rect.minX, y: isFlipped ? rect.maxY + 2 : rect.minY - 2)
    }

    // MARK: Marks

    /// What the changes are shown against; empty for none.
    var original = ""
    /// Called with a new original, when changes are kept.
    var keep: ((String) -> Void)?
    private var hunks: [TextChanges.Hunk] = []

    /// Shows the tags dimmed, so the text stands out, and the changes since
    /// the original.
    func refreshMarks() {
        guard let storage = textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        let text = string
        let small = storage.length <= Self.highlightLimit
        hunks = small && !original.isEmpty ? TextChanges.hunks(from: original, to: text) : []
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: whole)
        storage.removeAttribute(.backgroundColor, range: whole)
        if small {
            for tag in syntax.tags(in: text) {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                     range: NSRange(tag.range, in: text))
            }
            for hunk in hunks where !hunk.isDeletion {
                storage.addAttribute(.backgroundColor, value: Self.changeColor, range: hunk.current)
            }
        }
        storage.endEditing()
        refreshToolTips()
        needsDisplay = true
    }

    private static let changeColor = NSColor.systemYellow.withAlphaComponent(0.35)
    private static let deletionColor = NSColor.systemRed

    /// The rectangles a range of the text takes, in this view: one a line.
    private func rects(of range: NSRange) -> [NSRect] {
        guard let window else { return [] }
        var rects: [NSRect] = []
        var rest = range
        repeat {
            var actual = NSRange()
            let screen = firstRect(forCharacterRange: rest, actualRange: &actual)
            guard screen != .zero else { break }
            rects.append(convert(window.convertFromScreen(screen), from: nil))
            guard actual.length > 0, NSMaxRange(actual) < NSMaxRange(rest) else { break }
            rest = NSRange(location: NSMaxRange(actual), length: NSMaxRange(rest) - NSMaxRange(actual))
        } while rects.count < 200
        return rects
    }

    /// Where a deletion is marked: a thin bar at the place.
    private func deletionMark(_ hunk: TextChanges.Hunk) -> NSRect? {
        rects(of: NSRange(location: hunk.current.location, length: 0)).first.map {
            NSRect(x: $0.minX - 2, y: $0.minY, width: 4, height: max($0.height, 12))
        }
    }

    /// One tool tip over the whole text, saying what is under the mouse.
    /// It is put back when the mouse moves onto another change, so that the
    /// tip shows anew.
    private func refreshToolTips() {
        removeAllToolTips()
        if !hunks.isEmpty { addToolTip(bounds, owner: self, userData: nil) }
    }

    /// The change the mouse was last over.
    private var hovered: NSRange?
    private var moves: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let moves { removeTrackingArea(moves) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        moves = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard !hunks.isEmpty else { return }
        let over = hunk(at: convert(event.locationInWindow, from: nil))?.current
        if over != hovered {
            hovered = over
            refreshToolTips()
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        guard let hunk = hunk(at: point) else { return "" }
        if hunk.isDeletion { return "Deleted: \u{201C}\(hunk.originalText)\u{201D}" }
        if hunk.isAddition { return "Added" }
        return "Was: \u{201C}\(hunk.originalText)\u{201D}"
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !hunks.isEmpty { refreshToolTips() }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Self.deletionColor.setFill()
        for hunk in hunks where hunk.isDeletion {
            guard let mark = deletionMark(hunk), mark.intersects(dirtyRect) else { continue }
            NSBezierPath(roundedRect: NSRect(x: mark.midX - 1, y: mark.minY, width: 2, height: mark.height),
                         xRadius: 1, yRadius: 1).fill()
            // A small wedge under the line, pointing up at the place.
            let wedge = NSBezierPath()
            wedge.move(to: NSPoint(x: mark.midX - 4, y: mark.maxY + 3))
            wedge.line(to: NSPoint(x: mark.midX + 4, y: mark.maxY + 3))
            wedge.line(to: NSPoint(x: mark.midX, y: mark.maxY - 2))
            wedge.close()
            wedge.fill()
        }
    }

    /// The change at a point of the view: one the point is in, or a
    /// deletion mark it is on.
    private func hunk(at point: NSPoint) -> TextChanges.Hunk? {
        if let deletion = hunks.first(where: { $0.isDeletion && (deletionMark($0)?.insetBy(dx: -3, dy: 0).contains(point) ?? false) }) {
            return deletion
        }
        let index = characterIndexForInsertion(at: point)
        return hunks.first { !$0.isDeletion && rects(of: $0.current).contains { $0.contains(point) } }
            ?? hunks.first { !$0.isDeletion && NSLocationInRange(index, $0.current) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard !original.isEmpty else { return menu }
        var items: [NSMenuItem] = []
        if let hunk = hunk(at: convert(event.locationInWindow, from: nil)) {
            let restore = NSMenuItem(title: hunk.isAddition ? "Remove What Was Added" : "Restore the Original",
                                     action: #selector(restoreChange(_:)), keyEquivalent: "")
            restore.representedObject = hunk.current
            let keep = NSMenuItem(title: "Keep This Change", action: #selector(keepChange(_:)), keyEquivalent: "")
            keep.representedObject = hunk.current
            items += [restore, keep]
        }
        if !hunks.isEmpty {
            items.append(NSMenuItem(title: "Restore All Changes", action: #selector(restoreAllChanges(_:)),
                                    keyEquivalent: ""))
            items.append(NSMenuItem(title: "Keep All Changes", action: #selector(keepAllChanges(_:)),
                                    keyEquivalent: ""))
        }
        guard !items.isEmpty else { return menu }
        for (index, item) in items.enumerated() {
            item.target = self
            menu.insertItem(item, at: index)
        }
        menu.insertItem(.separator(), at: items.count)
        return menu
    }

    private func changeAt(_ item: NSMenuItem) -> TextChanges.Hunk? {
        guard let range = item.representedObject as? NSRange else { return nil }
        return hunks.first { $0.current == range }
    }

    /// Puts back what was there, as an edit that can be undone.
    @objc private func restoreChange(_ item: NSMenuItem) {
        guard let hunk = changeAt(item) else { return }
        replace(hunk.current, with: hunk.originalText)
    }

    @objc private func keepChange(_ item: NSMenuItem) {
        guard let hunk = changeAt(item) else { return }
        keep?(TextChanges.keeping(hunk, of: original, current: string))
    }

    @objc func restoreAllChanges(_ sender: Any?) {
        guard !original.isEmpty, string != original else { return }
        replace(NSRange(location: 0, length: (string as NSString).length), with: original)
    }

    @objc func keepAllChanges(_ sender: Any?) {
        keep?(string)
    }

    private func replace(_ range: NSRange, with replacement: String) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        replaceCharacters(in: range, with: replacement)
        didChangeText()
    }
}
