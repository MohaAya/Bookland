// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import AppKit
import Combine
import PDFKit
import SwiftUI

@MainActor
final class PDFReaderController: ObservableObject {
    weak var pdfView: PDFView?
    @Published var currentPage: Int = 1
    @Published var pageCount: Int = 1
    @Published var selection: PDFSelection?
    @Published private(set) var zoomPercent: Int = 100
    @Published var isPanMode = false
    @Published var previousLocationPage: Int?
    @Published private(set) var nextLocationPage: Int?
    @Published private(set) var pageHistory: [Int] = [1]
    @Published private(set) var historyIndex: Int = 0
    @Published private(set) var canUndoHighlight = false
    private var lastHighlightAnnotations: [(PDFPage, PDFAnnotation)] = []

    var activeSelection: PDFSelection? {
        selection ?? pdfView?.currentSelection
    }

    var selectedText: String {
        activeSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func goToPage(_ page: Int) {
        guard let document = pdfView?.document, document.pageCount > 0 else { return }
        let boundedPage = min(max(page, 1), document.pageCount)
        guard let pdfPage = document.page(at: boundedPage - 1) else { return }
        if boundedPage != currentPage { recordPageVisit(boundedPage) }
        pdfView?.go(to: pdfPage)
        currentPage = boundedPage
    }

    func previousPage() { goToPage(currentPage - 1) }
    func nextPage() { goToPage(currentPage + 1) }

    func returnToPreviousLocation() {
        goBackInHistory()
    }

    func goBackInHistory() {
        guard historyIndex > 0 else { return }
        goToHistoryEntry(at: historyIndex - 1)
    }

    func goForwardInHistory() {
        guard historyIndex + 1 < pageHistory.count else { return }
        goToHistoryEntry(at: historyIndex + 1)
    }

    func goToHistoryEntry(at index: Int) {
        guard pageHistory.indices.contains(index), let document = pdfView?.document else { return }
        guard let page = document.page(at: pageHistory[index] - 1) else { return }
        historyIndex = index
        updateHistoryPointers()
        pdfView?.go(to: page)
        currentPage = pageHistory[index]
    }

    func pageDidChange(to page: Int) {
        guard page != currentPage else { return }
        recordPageVisit(page)
    }

    func resetPageHistory(at page: Int = 1) {
        currentPage = max(1, page)
        pageHistory = [currentPage]
        historyIndex = 0
        updateHistoryPointers()
    }

    private func recordPageVisit(_ page: Int) {
        if historyIndex + 1 < pageHistory.count {
            pageHistory.removeSubrange((historyIndex + 1)..<pageHistory.count)
        }
        if pageHistory.last != page {
            pageHistory.append(page)
        }
        historyIndex = pageHistory.count - 1
        currentPage = page
        updateHistoryPointers()
    }

    private func updateHistoryPointers() {
        previousLocationPage = historyIndex > 0 ? pageHistory[historyIndex - 1] : nil
        nextLocationPage = historyIndex + 1 < pageHistory.count ? pageHistory[historyIndex + 1] : nil
    }

    func zoomOut() {
        guard let pdfView else { return }
        pdfView.autoScales = false
        pdfView.zoomOut(nil)
        updateZoomPercent()
    }

    func zoomIn() {
        guard let pdfView else { return }
        pdfView.autoScales = false
        pdfView.zoomIn(nil)
        updateZoomPercent()
    }

    func resetZoom() {
        guard let pdfView else { return }
        pdfView.autoScales = true
        pdfView.layoutSubtreeIfNeeded()
        let fitScale = pdfView.scaleFactorForSizeToFit
        if fitScale > 0 {
            pdfView.scaleFactor = fitScale
        }
        zoomPercent = 100
        isPanMode = false
    }

    private func updateZoomPercent() {
        guard let pdfView, pdfView.scaleFactorForSizeToFit > 0 else { return }
        zoomPercent = max(10, Int((pdfView.scaleFactor / pdfView.scaleFactorForSizeToFit) * 100))
        if zoomPercent <= 100 { isPanMode = false }
    }

    func highlightSelection(color: NSColor) -> Bool {
        guard let selection = activeSelection, let document = pdfView?.document else { return false }
        var createdAnnotations: [(PDFPage, PDFAnnotation)] = []

        // PDFSelection.bounds(for:) returns one bounding rectangle for the entire
        // selection. For a selection that wraps, that rectangle can cover the
        // unselected part of both lines. Split the selection into its actual line
        // fragments first; each fragment keeps the selected start/end of its line.
        let lineSelections = selection.selectionsByLine()
        let fragments = lineSelections.isEmpty ? [selection] : lineSelections
        for fragment in fragments {
            for page in fragment.pages {
                let bounds = fragment.bounds(for: page)
                guard !bounds.isNull, !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color.withAlphaComponent(0.45)
                page.addAnnotation(annotation)
                createdAnnotations.append((page, annotation))
            }
        }
        guard !createdAnnotations.isEmpty else { return false }
        lastHighlightAnnotations = createdAnnotations
        canUndoHighlight = true
        persist(document)
        pdfView?.needsDisplay = true
        return true
    }

    func undoLastHighlight() -> Bool {
        guard !lastHighlightAnnotations.isEmpty, let document = pdfView?.document else { return false }
        for (page, annotation) in lastHighlightAnnotations {
            page.removeAnnotation(annotation)
        }
        lastHighlightAnnotations = []
        canUndoHighlight = false
        persist(document)
        pdfView?.needsDisplay = true
        return true
    }

    func removeHighlightAtSelection() -> Bool {
        guard let selection = activeSelection, let document = pdfView?.document else { return false }
        var removed = false
        for page in selection.pages {
            let selectionBounds = selection.bounds(for: page)
            let highlights = page.annotations.filter { annotation in
                annotation.type == "Highlight" && !annotation.bounds.intersection(selectionBounds).isEmpty
            }
            for annotation in highlights {
                page.removeAnnotation(annotation)
                removed = true
            }
        }
        guard removed else { return false }
        lastHighlightAnnotations = []
        canUndoHighlight = false
        persist(document)
        pdfView?.needsDisplay = true
        return true
    }

    var canRemoveHighlightAtSelection: Bool {
        guard let selection = activeSelection else { return false }
        for page in selection.pages {
            let selectionBounds = selection.bounds(for: page)
            if page.annotations.contains(where: { annotation in
                annotation.type == "Highlight" && !annotation.bounds.intersection(selectionBounds).isEmpty
            }) {
                return true
            }
        }
        return false
    }

    @discardableResult
    func addComment(_ text: String) -> Bool {
        guard let selection = activeSelection, let page = selection.pages.first, let document = pdfView?.document else { return false }
        let bounds = selection.bounds(for: page)
        let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        annotation.contents = text
        page.addAnnotation(annotation)
        persist(document)
        pdfView?.needsDisplay = true
        return true
    }

    private func persist(_ document: PDFDocument) {
        guard let url = document.documentURL else { return }
        _ = document.write(to: url)
    }
}

@MainActor
final class PDFSearchController: ObservableObject {
    weak var pdfView: PDFView?
    @Published var query = ""
    @Published private(set) var matches: [PDFSelection] = []
    @Published private(set) var currentIndex = 0

    var resultSummary: String {
        guard !query.isEmpty else { return "" }
        return matches.isEmpty ? "No matches" : "\(currentIndex + 1) of \(matches.count)"
    }

    func attach(to view: PDFView) {
        pdfView = view
    }

    func search() {
        guard let document = pdfView?.document else { return }
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            matches = []
            currentIndex = 0
            pdfView?.highlightedSelections = nil
            return
        }

        matches = document.findString(cleanQuery, withOptions: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        currentIndex = 0
        pdfView?.highlightedSelections = matches
        revealCurrentMatch()
    }

    func nextMatch() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        revealCurrentMatch()
    }

    func previousMatch() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        revealCurrentMatch()
    }

    func resetForNewDocument() {
        matches = []
        currentIndex = 0
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { search() }
    }

    private func revealCurrentMatch() {
        guard let match = matches[safe: currentIndex] else { return }
        pdfView?.currentSelection = match
        pdfView?.go(to: match)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

final class PaperOverlayView: NSView {
    var readingAppearance: ReadingAppearance = .system {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard readingAppearance != .system else { return }

        if readingAppearance == .dark {
            NSColor.white.withAlphaComponent(0.88).setFill()
            bounds.fill(using: .difference)
            return
        }

        let paperColor: NSColor
        switch readingAppearance {
        case .system: return
        case .dark: return
        case .milky: paperColor = NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.86, alpha: 0.28)
        case .sepia: paperColor = NSColor(calibratedRed: 0.86, green: 0.73, blue: 0.52, alpha: 0.20)
        case .blue: paperColor = NSColor(calibratedRed: 0.72, green: 0.84, blue: 0.96, alpha: 0.18)
        case .sketchy: paperColor = NSColor(calibratedRed: 0.95, green: 0.92, blue: 0.82, alpha: 0.22)
        }

        paperColor.setFill()
        bounds.fill()

        guard readingAppearance == .sketchy else { return }
        NSColor(calibratedWhite: 0.35, alpha: 0.07).setStroke()
        for x in stride(from: CGFloat(-40), through: bounds.width + 40, by: 42) {
            let line = NSBezierPath()
            line.lineWidth = 0.7
            line.move(to: NSPoint(x: x, y: 0))
            line.curve(to: NSPoint(x: x + 18, y: bounds.height), controlPoint1: NSPoint(x: x - 10, y: bounds.height * 0.35), controlPoint2: NSPoint(x: x + 30, y: bounds.height * 0.72))
            line.stroke()
        }
    }
}

final class StudyPDFView: PDFView {
    let paperOverlay = PaperOverlayView(frame: .zero)
    var onContextHighlight: ((NSColor) -> Void)?
    var onContextUndoHighlight: (() -> Void)?
    var onContextRemoveHighlight: (() -> Void)?
    var canContextUndoHighlight: (() -> Bool)?
    var canContextRemoveHighlight: (() -> Bool)?
    var readingAppearance: ReadingAppearance = .system {
        didSet { paperOverlay.readingAppearance = readingAppearance; backgroundColor = readingAppearance == .dark ? .black : NSColor(calibratedWhite: 0.92, alpha: 1) }
    }
    var isPanMode = false {
        didSet { panGesture.isEnabled = isPanMode }
    }
    private lazy var panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(paperOverlay, positioned: .above, relativeTo: nil)
        paperOverlay.autoresizingMask = [.width, .height]
        panGesture.isEnabled = false
        addGestureRecognizer(panGesture)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(paperOverlay, positioned: .above, relativeTo: nil)
        paperOverlay.autoresizingMask = [.width, .height]
        panGesture.isEnabled = false
        addGestureRecognizer(panGesture)
    }

    override func layout() {
        super.layout()
        paperOverlay.frame = bounds
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let hasSelection = !(currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        let menu = super.menu(for: event) ?? NSMenu(title: hasSelection ? "PDF selection" : "PDF")
        guard hasSelection else { return menu }

        // Preserve PDFKit/AppKit's native selection actions such as Copy,
        // Look Up, Share, Translate, and Services, then append study actions.
        if !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }
        let highlightItem = NSMenuItem(title: "Highlight", action: nil, keyEquivalent: "")
        let highlightMenu = NSMenu(title: "Highlight")
        addHighlightMenuItem("Yellow", selector: #selector(contextHighlightYellow), to: highlightMenu)
        addHighlightMenuItem("Green", selector: #selector(contextHighlightGreen), to: highlightMenu)
        addHighlightMenuItem("Pink", selector: #selector(contextHighlightPink), to: highlightMenu)
        addHighlightMenuItem("Blue", selector: #selector(contextHighlightBlue), to: highlightMenu)
        menu.setSubmenu(highlightMenu, for: highlightItem)
        menu.addItem(highlightItem)

        let removeItem = NSMenuItem(title: "Remove Highlight Here", action: #selector(contextRemoveHighlight), keyEquivalent: "")
        removeItem.target = self
        removeItem.isEnabled = canContextRemoveHighlight?() ?? false
        menu.addItem(removeItem)

        let undoItem = NSMenuItem(title: "Undo Last Highlight", action: #selector(contextUndoHighlight), keyEquivalent: "")
        undoItem.target = self
        undoItem.isEnabled = canContextUndoHighlight?() ?? false
        menu.addItem(undoItem)
        return menu
    }

    private func addHighlightMenuItem(_ title: String, selector: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func contextHighlightYellow() { onContextHighlight?(.systemYellow) }
    @objc private func contextHighlightGreen() { onContextHighlight?(.systemGreen) }
    @objc private func contextHighlightPink() { onContextHighlight?(.systemPink) }
    @objc private func contextHighlightBlue() { onContextHighlight?(.systemBlue) }
    @objc private func contextUndoHighlight() { onContextUndoHighlight?() }
    @objc private func contextRemoveHighlight() { onContextRemoveHighlight?() }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard let scrollView = enclosingScrollView else { return }
        let delta = gesture.translation(in: self)
        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        origin.x -= delta.x
        origin.y -= delta.y
        clipView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clipView)
        gesture.setTranslation(.zero, in: self)
    }
}

final class StudyPDFContainerView: NSView {
    let pdfView: StudyPDFView
    private let thumbnailView = PDFThumbnailView(frame: .zero)
    var showPageSidebar = true {
        didSet { needsLayout = true }
    }

    init(showPageSidebar: Bool) {
        self.pdfView = StudyPDFView(frame: .zero)
        self.showPageSidebar = showPageSidebar
        super.init(frame: .zero)
        wantsLayer = true
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = NSSize(width: 120, height: 160)
        thumbnailView.backgroundColor = NSColor(calibratedWhite: 0.94, alpha: 1)
        addSubview(pdfView)
        addSubview(thumbnailView)
    }

    required init?(coder: NSCoder) {
        self.pdfView = StudyPDFView(frame: .zero)
        super.init(coder: coder)
        thumbnailView.pdfView = pdfView
        addSubview(pdfView)
        addSubview(thumbnailView)
    }

    override func layout() {
        super.layout()
        let sidebarWidth: CGFloat = showPageSidebar ? 176 : 0
        thumbnailView.isHidden = sidebarWidth == 0
        thumbnailView.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
        pdfView.frame = NSRect(x: sidebarWidth, y: 0, width: max(0, bounds.width - sidebarWidth), height: bounds.height)
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    @ObservedObject var controller: PDFReaderController
    @ObservedObject var searchController: PDFSearchController
    let appearance: ReadingAppearance
    let showPageSidebar: Bool
    let onHighlight: ((NSColor) -> Bool)?
    let onUndoHighlight: (() -> Bool)?
    let onRemoveHighlight: (() -> Bool)?

    init(url: URL, controller: PDFReaderController, searchController: PDFSearchController, appearance: ReadingAppearance, showPageSidebar: Bool, onHighlight: ((NSColor) -> Bool)? = nil, onUndoHighlight: (() -> Bool)? = nil, onRemoveHighlight: (() -> Bool)? = nil) {
        self.url = url
        self.controller = controller
        self.searchController = searchController
        self.appearance = appearance
        self.showPageSidebar = showPageSidebar
        self.onHighlight = onHighlight
        self.onUndoHighlight = onUndoHighlight
        self.onRemoveHighlight = onRemoveHighlight
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> StudyPDFContainerView {
        let container = StudyPDFContainerView(showPageSidebar: showPageSidebar)
        let view = container.pdfView
        view.backgroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        view.readingAppearance = appearance
        view.isPanMode = controller.isPanMode
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        configureContextActions(for: view)
        context.coordinator.attach(to: view)
        searchController.attach(to: view)
        loadDocument(in: view)
        return container
    }

    func updateNSView(_ container: StudyPDFContainerView, context: Context) {
        let view = container.pdfView
        let sidebarChanged = container.showPageSidebar != showPageSidebar
        container.showPageSidebar = showPageSidebar
        view.readingAppearance = appearance
        view.isPanMode = controller.isPanMode
        configureContextActions(for: view)
        if view.document?.documentURL?.path != url.path {
            loadDocument(in: view)
            searchController.resetForNewDocument()
        }
        if let current = view.currentPage, let document = view.document,
           document.index(for: current) + 1 != controller.currentPage {
            controller.goToPage(controller.currentPage)
        }
        if sidebarChanged {
            DispatchQueue.main.async {
                if view.autoScales { controller.resetZoom() }
            }
        }
    }

    private func loadDocument(in view: PDFView) {
        guard let document = PDFDocument(url: url) else { return }
        view.document = document
        controller.resetZoom()
        controller.pageCount = max(1, document.pageCount)
        let initialPage = min(max(controller.currentPage, 1), controller.pageCount)
        controller.resetPageHistory(at: initialPage)
        controller.goToPage(controller.currentPage)
        DispatchQueue.main.async {
            controller.resetZoom()
        }
    }

    private func configureContextActions(for view: StudyPDFView) {
        view.onContextHighlight = { color in _ = onHighlight?(color) }
        view.onContextUndoHighlight = { _ = onUndoHighlight?() }
        view.onContextRemoveHighlight = { _ = onRemoveHighlight?() }
        view.canContextUndoHighlight = { controller.canUndoHighlight }
        view.canContextRemoveHighlight = { controller.canRemoveHighlightAtSelection }
    }

    @MainActor
    final class Coordinator: NSObject {
        let controller: PDFReaderController
        weak var pdfView: PDFView?
        private var observers: [NSObjectProtocol] = []

        init(controller: PDFReaderController) { self.controller = controller }

        func attach(to view: PDFView) {
            pdfView = view
            controller.pdfView = view
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: Notification.Name.PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let page = view.currentPage, let document = view.document else { return }
                    let newPage = document.index(for: page) + 1
                    self.controller.pageDidChange(to: newPage)
                }
            })
            observers.append(center.addObserver(forName: Notification.Name.PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.controller.selection = view.currentSelection
                }
            })
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
