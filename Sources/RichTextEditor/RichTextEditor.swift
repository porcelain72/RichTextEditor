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


final class HostingTextView: NSTextView {
    weak var coordinator: RichTextEditor.Coordinator?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        coordinator?.applyDisplayOverride()
    }
}

public struct RichTextEditor: NSViewRepresentable {
    @ObservedObject public var content: RichTextModel
   
  
    @Binding public var inspectorVersion: UUID
    public var minimumBottomPadding: CGFloat
    public var undoManager: UndoManager? = nil  // ← Add this

    public init(
        content: RichTextModel,
        inspector: Binding<UUID>,
        minimumBottomPadding: CGFloat = 40,
        undoManager: UndoManager? = nil
    ) {
        self.content = content
        self._inspectorVersion = inspector
        self.minimumBottomPadding = minimumBottomPadding
        self.undoManager = undoManager
    }

    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    /// Return the FocusingScrollView so clicks inside it can become first responder.
    public func makeNSView(context: Context) -> NSScrollView {
        // 1) Create our custom scroll view
        let scrollView = FocusingScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.autoresizesSubviews = true
        
        // 2) Create the text view
        let textView = HostingTextView()
        textView.coordinator = context.coordinator

        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true


        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]  // Ensure it resizes with the scrollView
        
        // Initialize with the bound attributed text
        textView.textStorage?.setAttributedString(content.attributedString)
        
        // Set delegate to catch typing
        textView.delegate = context.coordinator
        
        // Let us know when the selection (caret) moves
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewSelectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        //textView.postsBoundsChangedNotifications = true
        
    

        // Embed the NSTextView into our focusing scroll view
        scrollView.documentView = textView
        textView.frame = scrollView.contentView.bounds
        
        // Store references in the coordinator
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }
    
    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Skip update if user is editing
        if context.coordinator.isProgrammaticUpdate { return }

        let currentStored = context.coordinator.parent.content.attributedString
        let currentVisible = textView.attributedString()

        if currentStored != currentVisible {
            context.coordinator.isProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(currentStored)
            context.coordinator.lastSyncedTextHash = currentStored.hashValue
            context.coordinator.applyDisplayOverride()
            context.coordinator.isProgrammaticUpdate = false
        }
    }



    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        
        private var updateWorkItem: DispatchWorkItem?
        fileprivate var lastSyncedTextHash: Int = 0
        fileprivate var isProgrammaticUpdate = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }
        
        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            updateWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }

                let currentText = textView.attributedString()
                let previousText = self.parent.content.attributedString

                if currentText != previousText {
                    // Register undo
                    if let undoManager = self.parent.undoManager {
                        undoManager.registerUndo(withTarget: self.parent.content) { target in
                            target.attributedString = previousText
                        }
                        undoManager.setActionName("Edit Text")
                    }

                    self.parent.content.attributedString = currentText
                }
            }

            updateWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)

            scrollCaretIfNeeded()
        }


        
        @objc func textViewSelectionDidChange(_ notification: Notification) {
            // Scroll after selection settles (prevent multiple rapid scrolls)
            DispatchQueue.main.async {
                self.scrollCaretIfNeeded()
            }
        }
        
        func applyDisplayOverride() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }

            textStorage.beginEditing()
            textStorage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
                if value != nil {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                }
            }
            textStorage.endEditing()
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
            guard selectedRange.location <= layoutManager.numberOfGlyphs else { return }
            
            layoutManager.ensureLayout(for: textContainer)
            
            let caretRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: selectedRange.location, length: 0),
                in: textContainer
            )
            
            // Convert to scroll view coordinate space
            let caretInView = textView.convert(caretRect, to: scrollView.contentView)
            
            let visibleRect = scrollView.contentView.bounds
            let caretBottomY = caretInView.maxY
            let threshold = visibleRect.maxY - parent.minimumBottomPadding
            
            if caretBottomY > threshold {
                let targetY = caretBottomY - visibleRect.height + parent.minimumBottomPadding
                let maxY = textView.bounds.height - visibleRect.height
                let constrainedY = min(max(targetY, 0), maxY)
                
                // Use animation only if scroll is significant
                let deltaY = abs(scrollView.contentView.bounds.origin.y - constrainedY)
                let shouldAnimate = deltaY > 2
                
                if shouldAnimate {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.2
                        context.allowsImplicitAnimation = true
                        scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: constrainedY))
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                    }
                } else {
                    scrollView.contentView.scroll(to: NSPoint(x: 0, y: constrainedY))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
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
