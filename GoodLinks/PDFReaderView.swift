import SwiftUI
import PDFKit

// MARK: - State object shared between the view and toolbar buttons

@MainActor
class PDFReaderState: ObservableObject {
    weak var pdfView: PDFView?

    /// Highlights the current PDF selection, stores the text, and returns it.
    func highlightSelectionAndReturn() -> String? {
        guard let pdfView,
              let selection = pdfView.currentSelection,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }

        for page in selection.pages {
            let bounds = selection.bounds(for: page)
            let ann = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            ann.color = NSColor.yellow.withAlphaComponent(0.55)
            page.addAnnotation(ann)
        }
        pdfView.clearSelection()
        return text
    }
}

// MARK: - PDFReaderView

struct PDFReaderView: NSViewRepresentable {
    let url: URL
    let isDark: Bool
    let savedHighlights: [Highlight]
    var state: PDFReaderState
    var onHighlight: ((String) -> Void)?
    var onWordCount: ((Int) -> Void)?

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)

        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
            context.coordinator.document = doc
            applyHighlights(savedHighlights, to: doc)

            // Report word count once
            var allText = ""
            for i in 0..<doc.pageCount { allText += doc.page(at: i)?.string ?? "" }
            let wc = allText.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }.count
            DispatchQueue.main.async { self.onWordCount?(wc) }
        }

        context.coordinator.onHighlight = onHighlight
        state.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        context.coordinator.onHighlight = onHighlight
        state.pdfView = nsView
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // Re-apply highlights by searching for the stored text in the document
    private func applyHighlights(_ highlights: [Highlight], to doc: PDFDocument) {
        for hl in highlights {
            guard !hl.text.isEmpty else { continue }
            let selections = doc.findString(hl.text, withOptions: [.caseInsensitive])
            guard let first = selections.first else { continue }
            for page in first.pages {
                let bounds = first.bounds(for: page)
                let ann = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                ann.color = NSColor.yellow.withAlphaComponent(0.55)
                page.addAnnotation(ann)
            }
        }
    }

    class Coordinator: NSObject {
        var document: PDFDocument?
        var onHighlight: ((String) -> Void)?
    }
}
