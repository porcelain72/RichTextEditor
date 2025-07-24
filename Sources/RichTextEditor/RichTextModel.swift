//
//  File.swift
//  
//
//  Created by Peter Macdonald on 24/07/2025.
//
/// A wrapper around NSAttributedString that exposes `@Published var attributedString`
/// and makes the type `Codable` by round-tripping through RTF data.
///
import Foundation
import AppKit

public class RichTextModel: ObservableObject, Codable {
    // MARK: –– Published attributed string
    @Published var attributedString: NSAttributedString

    // MARK: –– Designated initializers

  //  var attributes : [NSAttributedString.Key:Any] = [:]
    /// Create an empty KishoRichText (i.e. an empty string).
    public  init() {
        self.attributedString = NSAttributedString(string: "")
    }

    /// Create from existing RTF data.
    /// If the data cannot be decoded, falls back to an empty string.
    public  init(rtfData: Data) {
        if let decoded = try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            self.attributedString = decoded
        } else {
            self.attributedString = NSAttributedString(string: "")
        }
    }

    // MARK: –– Codable Conformance

    enum CodingKeys: String, CodingKey {
        case rtfData
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decode(Data.self, forKey: .rtfData)

        if let decoded = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            self.attributedString = decoded
        } else {
            self.attributedString = NSAttributedString(string: "")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let rtfData = attributedString.rtfData()
        try container.encode(rtfData, forKey: .rtfData)
    }
    
    public  func flushContent()  {
        self.attributedString = NSAttributedString(string: "")
    }
    
    public  func copy() -> RichTextModel {
         let new = RichTextModel()
         new.attributedString = NSAttributedString(attributedString: self.attributedString)
         return new
     }
}



extension RichTextModel {

    public  func applyTypography(font: NSFont, color: NSColor? = nil) {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        let mutableCopy = NSMutableAttributedString(attributedString: attributedString)

        mutableCopy.beginEditing()
        mutableCopy.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            var newAttributes = attributes
            newAttributes[.font] = font
            if let color = color {
                newAttributes[.foregroundColor] = color
            }
            mutableCopy.setAttributes(newAttributes, range: range)
        }
        mutableCopy.endEditing()

        self.attributedString = mutableCopy
    }
    
    /// Create a single KishoRichText by concatenating the `content` of each KishoSection in order.
    /// Inserts one newline between each section’s content, preserving all attributes.

    
    /// Splits `self.attributedString` into paragraphs, returning each paragraph
    /// as a brand‐new `KishoRichText` (with its own attributed string).
    ///
    /// Paragraph boundaries are determined using NSString’s `.byParagraphs` enumeration,
    /// so each returned wrapper contains exactly one paragraph (including any attached
    /// newline or paragraph‐separator attributes).
    public  func paragraphs() -> [RichTextModel] {
        let full = self.attributedString
        let fullNSString = full.string as NSString
        var result: [RichTextModel] = []

        // Enumerate by paragraph: this yields each “paragraph substring” and its range.
        fullNSString.enumerateSubstrings(
            in: NSRange(location: 0, length: fullNSString.length),
            options: .byParagraphs
        ) { (substring, substringRange, enclosingRange, stop) in
            // substringRange is the character range of this paragraph (without trailing newline),
            // but we want the full attributed substring including any paragraph separator.
            // So use 'enclosingRange' to include the final newline (if any).
            let paragraphRange = enclosingRange

            // Extract the attributed substring for this paragraph
            let subAttrString = full.attributedSubstring(from: paragraphRange)

            // Wrap it in a new KishoRichText
            let newRich = RichTextModel()
            newRich.attributedString = subAttrString
            result.append(newRich)
        }

        return result
    }
    

        /// A reasonable “default title” drawn from the first short sentence (≤ 20 words) of the content.
        /// - If the attributed string is empty (after trimming whitespace/newlines), returns "Untitled".
        /// - Otherwise, enumerates by sentences; if it finds a sentence with ≤ 20 words, returns that.
        /// - If no sentence under 20 words is found, returns the first 20 words of the text joined by spaces.
    public  var defaultTitle: String {
            // 1) Get the plain string and trim whitespace/newlines
            let fullString = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fullString.isEmpty else {
                return "Untitled"
            }

            // 2) Try to find a “short” (≤ 20‐word) sentence
            let nsString = fullString as NSString
            var shortSentence: String? = nil

            nsString.enumerateSubstrings(
                in: NSRange(location: 0, length: nsString.length),
                options: .bySentences
            ) { (substring, substringRange, enclosingRange, stop) in
                guard
                    let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !sentence.isEmpty
                else { return }

                let wordCount = sentence
                    .split { $0.isWhitespace }
                    .count
                if wordCount <= 20 {
                    shortSentence = sentence
                    stop.pointee = true
                }
            }

            if let title = shortSentence {
                return title
            }

            // 3) No sentence under 20 words found → return first 20 words
            let allWords = fullString
                .split { $0.isWhitespace }
            let firstWords = allWords.prefix(20)
            return firstWords.joined(separator: " ")
        }


        /// Returns a new KishoRichText which is the concatenation of `parts`,
        /// with a single newline inserted between each part’s attributed string.
    public  static func joined(_ parts: [RichTextModel]) -> RichTextModel {
            let result = RichTextModel()
            let combined = NSMutableAttributedString()

            for (index, part) in parts.enumerated() {
                // Append this part’s attributedString
                combined.append(part.attributedString)

                // If not the last element, append one newline (preserving default attributes)
                if index < parts.count - 1 {
                    combined.append(NSAttributedString(string: "\n"))
                }
            }

            // Assign back to the wrapper’s published property
            result.attributedString = combined
            return result
        }
    
}

/// Convenience extension to export NSAttributedString as RTF data.
extension NSAttributedString {
    /// Returns RTF data for the entire string. If encoding fails, returns empty Data.
    public  func rtfData() -> Data {
        return (try? self.data(
            from: NSRange(location: 0, length: self.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtf
            ]
        )) ?? Data()
    }
}
