import SwiftUI
import AppKit

/// A tiny NSScrollView subclass that will accept first responder and forward it
/// immediately to its `documentView` (the NSTextView).
public final class FocusingScrollView: NSScrollView {
    public  override var acceptsFirstResponder: Bool {
        return true
    }
    public  override func becomeFirstResponder() -> Bool {
        // If the documentView can become first responder, make it first‐responder instead.
        if let tv = self.documentView as? NSTextView, tv.acceptsFirstResponder {
            return tv.becomeFirstResponder()
        }
        return super.becomeFirstResponder()
    }

    // Also, if the user clicks anywhere in the scroll view, forward that click to the text view.
    public  override func hitTest(_ point: NSPoint) -> NSView? {
        // Convert to textView’s coordinate system and see if that subview wants the click:
        if let tv = self.documentView as? NSTextView {
            let tvPoint = self.convert(point, to: tv)
            if tv.bounds.contains(tvPoint) {
                return tv.hitTest(tvPoint)
            }
        }
        return super.hitTest(point)
    }
}

public struct RichTextEditor: NSViewRepresentable {
    @Binding public var attributedText: NSAttributedString
    @Binding public var inspectorVersion: UUID
    public var minimumBottomPadding: CGFloat

    public init(
        attributedText: Binding<NSAttributedString>,
        inspector: Binding<UUID>,
        minimumBottomPadding: CGFloat = 40
    ) {
        self._attributedText = attributedText
        self._inspectorVersion = inspector
        self.minimumBottomPadding = minimumBottomPadding
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Return the FocusingScrollView so clicks inside it can become first responder.
    public func makeNSView(context: Context) -> NSTextView {
        // 1) Create our custom scroll view
        let scrollView = FocusingScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // 2) Create the text view
        let textView = NSTextView()
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.textContainer?.widthTracksTextView = true

        // Initialize with the bound attributed text
        textView.textStorage?.setAttributedString(attributedText)

        // Set delegate to catch typing
        textView.delegate = context.coordinator

        // Let us know when the selection (caret) moves
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewSelectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        textView.postsFrameChangedNotifications = true
        textView.postsBoundsChangedNotifications = true

        // Embed the NSTextView into our focusing scroll view
        scrollView.documentView = textView

        // Store references in the coordinator
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return textView
    }

    public func updateNSView(_ nsView: NSTextView, context: Context) {
        // Whenever the binding changes, update the text storage unconditionally
      /*  guard let textView = nsView.documentView as? NSTextView else {
            return
        }
       */
        nsView.textStorage?.setAttributedString(attributedText)
    }

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var textView: NSTextView?
        var scrollView: NSScrollView?

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.attributedText = textView.attributedString()
            scrollCaretIfNeeded()
        }

        @objc func textViewSelectionDidChange(_ notification: Notification) {
            scrollCaretIfNeeded()
        }

        private func scrollCaretIfNeeded() {
            guard
                let textView = textView,
                let scrollView = scrollView,
                let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else {
                return
            }

            let selectedRange = textView.selectedRange()
            guard selectedRange.location <= layoutManager.numberOfGlyphs else {
                return
            }

            let caretRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: selectedRange.location, length: 0),
                in: textContainer
            )

            let visibleRect = scrollView.contentView.bounds
            let visibleHeight = visibleRect.height
            let visibleOriginY = visibleRect.origin.y

            let caretBottomY = caretRect.maxY
            let caretBottomInVisible = caretBottomY - visibleOriginY
            let threshold = visibleHeight - parent.minimumBottomPadding

            if caretBottomInVisible > threshold {
                let targetY = caretBottomY - visibleHeight + parent.minimumBottomPadding
                let maxY = textView.bounds.height - visibleHeight
                let constrainedY = min(max(targetY, 0), maxY)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: constrainedY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }
}
