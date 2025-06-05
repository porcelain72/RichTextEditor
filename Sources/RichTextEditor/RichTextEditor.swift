import SwiftUI
import AppKit

public struct RichTextEditor: NSViewRepresentable {
    @Binding public var attributedText: NSAttributedString
    public var minimumBottomPadding: CGFloat

    public init(attributedText: Binding<NSAttributedString>, minimumBottomPadding: CGFloat = 40) {
        self._attributedText = attributedText
        self.minimumBottomPadding = minimumBottomPadding
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSTextView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textStorage?.setAttributedString(attributedText)
        textView.delegate = context.coordinator
        textView.postsFrameChangedNotifications = true
        textView.postsBoundsChangedNotifications = true
        textView.backgroundColor = .clear
        textView.textContainer?.widthTracksTextView = true

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewSelectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return textView
    }

    public func updateNSView(_ nsView: NSTextView, context: Context) {
        // Only update from outside changes
        nsView.textStorage?.setAttributedString(attributedText)
/*
        if !nsView.attributedString().isEqual(to: attributedText) {
            nsView.textStorage?.setAttributedString(attributedText)
        }
 */
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

        func scrollCaretIfNeeded() {
            guard let textView = textView, let scrollView = scrollView else { return }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let selectedRange = textView.selectedRange()
            guard selectedRange.location <= layoutManager.numberOfGlyphs else { return }

            let caretRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: selectedRange.location, length: 0),
                in: textContainer
            )

            let caretBottomInTextView = caretRect.maxY
            let textViewVisibleHeight = scrollView.contentView.bounds.height
            let textViewVisibleOriginY = scrollView.contentView.bounds.origin.y

            let caretBottomInVisible = caretBottomInTextView - textViewVisibleOriginY
            let shouldScroll = caretBottomInVisible > textViewVisibleHeight - parent.minimumBottomPadding

            if shouldScroll {
                let targetY = caretBottomInTextView - textViewVisibleHeight + parent.minimumBottomPadding
                let constrainedY = max(0, min(targetY, textView.bounds.height - textViewVisibleHeight))
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: constrainedY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }
}


#Preview {
    
    RichTextEditor(attributedText: .constant(NSAttributedString(string: "Editor text")))
        .frame(width: 600, height: 400)
        .padding()
}
