import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)

import UIKit

#endif
/// A tiny NSScrollView subclass that will accept first responder and forward it
/// immediately to its `documentView` (the NSTextView).
///
///

#if os(macOS)
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
#endif

#if os(iOS)


/// A SwiftUI wrapper around UITextView that two-way-binds to an NSAttributedString.
/// On iOS, UITextView supports editing attributedText (fonts, colors, attributes).
public struct RichTextEditor: UIViewRepresentable {
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

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = UIColor.clear
        textView.delegate = context.coordinator
        textView.attributedText = attributedText
        textView.typingAttributes = defaultTypingAttributes()
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        // Observe selection change for caret-scrolling
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionDidChange(_:)),
            name: UITextView.textDidChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionDidChange(_:)),
            name: UITextView.textDidBeginEditingNotification,
            object: textView
        )
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        // If inspector changed (attributes updated), reapply attributedText
        if !uiView.attributedText.isEqual(to: attributedText) {
            let selectedRange = uiView.selectedRange
            uiView.attributedText = attributedText
            uiView.selectedRange = selectedRange
        }
        // Ensure typingAttributes match current caret attributes
        uiView.typingAttributes = defaultTypingAttributes()
    }

    /// Build default typing attributes from the current attributedText at caret (or start)
    private func defaultTypingAttributes() -> [NSAttributedString.Key: Any] {
        // If attributedText has content, read the attributes at location 0
        if attributedText.length > 0 {
            let attrs = attributedText.attributes(at: 0, effectiveRange: nil)
            return attrs
        }
        // Fallback to system font if empty
        return [
            .font: UIFont.systemFont(ofSize: UIFont.systemFontSize),
            .foregroundColor: UIColor.label
        ]
    }

    public class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        public func textViewDidChange(_ textView: UITextView) {
            // Push the updated attributedText back to SwiftUI
            parent.attributedText = textView.attributedText
            scrollCaretIfNeeded(textView)
        }

        @objc func selectionDidChange(_ notification: Notification) {
            if let tv = notification.object as? UITextView {
                scrollCaretIfNeeded(tv)
            }
        }

        private func scrollCaretIfNeeded(_ textView: UITextView) {
            // Compute caret rect in textView coordinates
            guard let selectedRange = textView.selectedTextRange else { return }
            let caretRect = textView.caretRect(for: selectedRange.end)
            let visibleRect = CGRect(
                x: textView.contentOffset.x,
                y: textView.contentOffset.y,
                width: textView.bounds.width,
                height: textView.bounds.height
            )

            // If caret is too close to bottom, scroll so it stays above minimumBottomPadding
            let padding = parent.minimumBottomPadding
            let caretMaxY = caretRect.maxY
            let visibleMaxY = visibleRect.maxY

            if caretMaxY > visibleMaxY - padding {
                // Scroll so that caretMaxY == visibleMaxY - padding
                var newOffset = textView.contentOffset
                newOffset.y = caretMaxY - (visibleRect.height - padding)
                newOffset.y = max(0, min(newOffset.y, textView.contentSize.height - visibleRect.height))
                textView.setContentOffset(newOffset, animated: false)
            }
        }
    }
}

#endif
