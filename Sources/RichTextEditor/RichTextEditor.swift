import SwiftUI
import AppKit

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

    /// Note: change return type to NSScrollView so SwiftUI will embed the scroll view directly.
    public func makeNSView(context: Context) -> NSScrollView {
        // 1) Create the scroll view
        let scrollView = NSScrollView()
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
        // Let width track the scroll view’s content width
        textView.textContainer?.widthTracksTextView = true

        // Initialize with the bound attributed text
        textView.textStorage?.setAttributedString(attributedText)

        // Set delegate so we catch typing changes
        textView.delegate = context.coordinator

        // We want to know when the selection (caret) moves
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewSelectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        textView.postsFrameChangedNotifications = true
        textView.postsBoundsChangedNotifications = true

        // Embed the text view inside the scroll view
        scrollView.documentView = textView

        // Keep references in the coordinator
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Whenever the binding changes, update the text storage unconditionally.
        // (We could compare isEqual(to:), but simpler to always overwrite when the model changes.)
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        textView.textStorage?.setAttributedString(attributedText)
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
            // Make sure the caret index is in bounds
            guard selectedRange.location <= layoutManager.numberOfGlyphs else {
                return
            }

            // Compute the caret’s bounding rect within the text view’s coordinate system
            let caretRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: selectedRange.location, length: 0),
                in: textContainer
            )

            // The bottom‐most visible Y in the scroll view’s clip view
            let visibleRect = scrollView.contentView.bounds
            let visibleHeight = visibleRect.height
            let visibleOriginY = visibleRect.origin.y

            // The caret’s bottom Y in text‐view coordinates
            let caretBottomY = caretRect.maxY

            // How far down the caret is into the visible region
            let caretBottomInVisible = caretBottomY - visibleOriginY

            // If the caret is closer than `minimumBottomPadding` to the bottom edge, scroll
            let threshold = visibleHeight - parent.minimumBottomPadding
            if caretBottomInVisible > threshold {
                // Compute the new origin Y so the caret becomes threshold points from the bottom
                let targetY = caretBottomY - visibleHeight + parent.minimumBottomPadding
                // Clamp to valid scroll range
                let maxY = textView.bounds.height - visibleHeight
                let constrainedY = min(max(targetY, 0), maxY)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: constrainedY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }
}


#Preview {
    
    RichTextEditor(attributedText: .constant(NSAttributedString(string: "Editor text")), inspector: .constant(UUID()))
        .frame(width: 600, height: 400)
        .padding()
}
