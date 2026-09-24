import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Paints ``HighlightRun``s onto an attributed copy of the source.
///
/// Every character gets a foreground color: the run's role color, or
/// ``TokenPalette/foreground`` outside runs. Bold and italic runs carry a
/// font with those traits; the view normalizes family and size.
struct HighlightAttributedStringBuilder: Sendable {
    private let palette: TokenPalette
    private let colorPacking = HighlightColorPacking()

    /// Creates a builder that paints with `palette`.
    init(palette: TokenPalette) {
        self.palette = palette
    }

    func build(source: String, runs: [HighlightRun]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: source)
        let full = NSRange(location: 0, length: attributed.length)
        guard full.length > 0 else { return attributed }
        var colors: [TokenRole: Any] = [:]
        func color(for role: TokenRole) -> Any {
            if let cached = colors[role] { return cached }
            let created = colorPacking.platformColor(palette.color(for: role))
            colors[role] = created
            return created
        }

        attributed.beginEditing()
        attributed.addAttribute(.foregroundColor, value: color(for: .foreground), range: full)
        for run in runs where run.end <= full.length {
            let range = NSRange(location: run.location, length: run.length)
            attributed.addAttribute(.foregroundColor, value: color(for: run.style.role), range: range)
            if let font = font(bold: run.style.isBold, italic: run.style.isItalic) {
                attributed.addAttribute(.font, value: font, range: range)
            }
        }
        attributed.endEditing()
        return attributed
    }

    /// A font carrying only the requested traits, or `nil` for regular text.
    private func font(bold: Bool, italic: Bool) -> Any? {
        guard bold || italic else { return nil }
#if canImport(AppKit)
        let base = NSFont.monospacedSystemFont(ofSize: 13, weight: bold ? .bold : .regular)
        guard italic else { return base }
        let descriptor = base.fontDescriptor.withSymbolicTraits(
            base.fontDescriptor.symbolicTraits.union(.italic)
        )
        return NSFont(descriptor: descriptor, size: 13) ?? base
#elseif canImport(UIKit)
        let base = UIFont.monospacedSystemFont(ofSize: 13, weight: bold ? .bold : .regular)
        guard italic,
              let descriptor = base.fontDescriptor.withSymbolicTraits(
                  base.fontDescriptor.symbolicTraits.union(.traitItalic)
              ) else { return base }
        return UIFont(descriptor: descriptor, size: 13)
#else
        return nil
#endif
    }
}
