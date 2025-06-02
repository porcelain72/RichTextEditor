# KishoRichTextEditor

A drop-in Swift Package for macOS apps providing a SwiftUI `RichTextEditor`
with automatic caret-following scroll behaviour, suitable for any document-based Mac app.

## Features

- SwiftUI wrapper for AppKit's `NSTextView`
- Keeps the caret (cursor) a minimum padding above the bottom as you type/scroll
- Fully supports rich text editing (`NSAttributedString`)
- Simple API: use as a SwiftUI View with a binding

## Installation

Add to your project using [Swift Package Manager](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app):

