// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../LICENSE.

import PDFKit
import SwiftUI
import UIKit

enum IOSHighlightColor: String, CaseIterable, Identifiable {
    case yellow = "Yellow", green = "Green", pink = "Pink", blue = "Blue"
    var id: String { rawValue }
    var uiColor: UIColor {
        switch self {
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .pink: return .systemPink
        case .blue: return .systemBlue
        }
    }
}

@MainActor
final class IOSReaderController: ObservableObject {
    weak var pdfView: PDFView?
    @Published var page = 1
    @Published var pageCount = 1
    @Published var selectedText = ""
    @Published var documentError: String?
    @Published var documentReady = false
    @Published var history: [Int] = [1]
    @Published var historyIndex = 0
    @Published var canUndoHighlight = false
    @Published var toast: String?

    /// Called when the reader surface is tapped (used to show or hide the reading controls).
    var onTap: (() -> Void)?
    /// Opens the note editor for the current selection (reader screen only).
    var onAddNote: (() -> Void)?
    /// Highlights are also written to the book's note list so they appear in the Notes tab.
    var noteSink: ((IOSLibraryNote) -> Void)?
    var noteRemoveSink: ((UUID) -> Void)?
    var highlightNotesRemoveSink: ((Int, String) -> Void)?

    private var lastHighlight: (annotations: [(PDFPage, PDFAnnotation)], noteID: UUID)?

    var canGoToPreviousPage: Bool { page > 1 }
    var canGoToNextPage: Bool { page < pageCount }
    var canRemoveHighlight: Bool {
        guard let selection = pdfView?.currentSelection else { return false }
        return selection.pages.contains { page in
            let bounds = selection.bounds(for: page)
            return page.annotations.contains { $0.type == "Highlight" && !$0.bounds.intersection(bounds).isEmpty }
        }
    }

    func goToPage(_ page: Int) {
        let target = min(max(page, 1), pageCount)
        guard let document = pdfView?.document, let pdfPage = document.page(at: target - 1) else { return }
        if target != self.page { recordVisit(target) }
        self.page = target
        if pdfView?.currentPage !== pdfPage { pdfView?.go(to: pdfPage) }
    }

    /// Moves without touching history (used while scrubbing the page slider).
    func displayPage(_ page: Int) {
        let target = min(max(page, 1), pageCount)
        guard let document = pdfView?.document, let pdfPage = document.page(at: target - 1) else { return }
        self.page = target
        if pdfView?.currentPage !== pdfPage { pdfView?.go(to: pdfPage) }
    }

    /// Adds the page the slider ended on to the reading history.
    func commitScrub() {
        if history.last != page { recordVisit(page) }
    }

    private func recordVisit(_ target: Int) {
        if historyIndex + 1 < history.count { history.removeSubrange((historyIndex + 1)..<history.count) }
        if history.last != target { history.append(target) }
        historyIndex = history.count - 1
    }

    func goToHistory(_ index: Int) {
        guard history.indices.contains(index), let document = pdfView?.document, let pdfPage = document.page(at: history[index] - 1) else { return }
        historyIndex = index
        page = history[index]
        pdfView?.go(to: pdfPage)
    }

    func goToPreviousPage() { guard canGoToPreviousPage else { return }; goToPage(page - 1) }
    func goToNextPage() { guard canGoToNextPage else { return }; goToPage(page + 1) }

    func presentSearch() {
        pdfView?.findInteraction.presentFindNavigator(showingReplace: false)
    }

    // MARK: Zoom

    func zoomIn() {
        guard let pdfView else { return }
        let fitScale = max(pdfView.scaleFactorForSizeToFit, 0.1)
        let currentScale = max(pdfView.scaleFactor, fitScale)
        pdfView.autoScales = false
        configureZoomBounds(for: pdfView, fitScale: fitScale)
        pdfView.scaleFactor = min(currentScale * 1.25, pdfView.maxScaleFactor)
    }

    func zoomOut() {
        guard let pdfView else { return }
        let fitScale = max(pdfView.scaleFactorForSizeToFit, 0.1)
        let currentScale = max(pdfView.scaleFactor, fitScale)
        pdfView.autoScales = false
        configureZoomBounds(for: pdfView, fitScale: fitScale)
        pdfView.scaleFactor = max(currentScale / 1.25, pdfView.minScaleFactor)
    }

    func fitToScreen() {
        guard let pdfView else { return }
        pdfView.autoScales = true
        pdfView.layoutIfNeeded()
        let fitScale = pdfView.scaleFactorForSizeToFit
        if fitScale > 0 {
            configureZoomBounds(for: pdfView, fitScale: fitScale)
            pdfView.scaleFactor = fitScale
        }
    }

    private func configureZoomBounds(for pdfView: PDFView, fitScale: CGFloat) {
        pdfView.minScaleFactor = max(fitScale * 0.65, 0.1)
        pdfView.maxScaleFactor = max(fitScale * 5.0, 4.0)
    }

    // MARK: Highlights

    func highlight(_ color: IOSHighlightColor) {
        guard let pdfView, let selection = pdfView.currentSelection,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            toast = "Select some text first, then choose a colour."
            return
        }
        var created: [(PDFPage, PDFAnnotation)] = []
        var firstPage: PDFPage?
        // One rectangle per line so a multi-line passage doesn't become one big block.
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color.uiColor.withAlphaComponent(0.45)
                annotation.quadrilateralPoints = [
                    NSValue(cgPoint: CGPoint(x: 0, y: bounds.height)),
                    NSValue(cgPoint: CGPoint(x: bounds.width, y: bounds.height)),
                    NSValue(cgPoint: CGPoint(x: 0, y: 0)),
                    NSValue(cgPoint: CGPoint(x: bounds.width, y: 0)),
                ]
                page.addAnnotation(annotation)
                created.append((page, annotation))
                if firstPage == nil { firstPage = page }
            }
        }
        guard !created.isEmpty else {
            toast = "Couldn't highlight that selection."
            return
        }
        let pageNumber = firstPage.flatMap { pdfView.document?.index(for: $0) }.map { $0 + 1 } ?? page
        let note = IOSLibraryNote(page: pageNumber, text: text, kind: "Highlight")
        lastHighlight = (created, note.id)
        canUndoHighlight = true
        noteSink?(note)
        pdfView.clearSelection()
        selectedText = ""
        toast = saveDocument() ? "Highlight saved" : "Highlighted, but couldn't save to the file."
    }

    func undoHighlight() {
        guard let last = lastHighlight else { return }
        last.annotations.forEach { $0.0.removeAnnotation($0.1) }
        noteRemoveSink?(last.noteID)
        lastHighlight = nil
        canUndoHighlight = false
        toast = saveDocument() ? "Highlight removed" : "Removed, but couldn't save to the file."
    }

    func removeHighlight() {
        guard let selection = pdfView?.currentSelection else { return }
        let selectedString = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var firstPage = page
        for page in selection.pages {
            let bounds = selection.bounds(for: page)
            page.annotations.filter { $0.type == "Highlight" && !$0.bounds.intersection(bounds).isEmpty }
                .forEach { page.removeAnnotation($0) }
            if let index = pdfView?.document?.index(for: page) { firstPage = index + 1 }
        }
        highlightNotesRemoveSink?(firstPage, selectedString)
        lastHighlight = nil
        canUndoHighlight = false
        pdfView?.clearSelection()
        selectedText = ""
        toast = saveDocument() ? "Highlight removed" : "Removed, but couldn't save to the file."
    }

    private func saveDocument() -> Bool {
        guard let document = pdfView?.document, let url = document.documentURL else { return false }
        return document.write(to: url)
    }
}

/// PDFView that adds Highlight and Add note to the text-selection menu.
final class IOSPDFKitView: PDFView {
    var onHighlight: ((IOSHighlightColor) -> Void)?
    var onAddNote: (() -> Void)?

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard currentSelection != nil else { return }
        var items: [UIMenuElement] = IOSHighlightColor.allCases.map { color in
            UIAction(title: color.rawValue, image: UIImage(systemName: "circle.fill")?.withTintColor(color.uiColor, renderingMode: .alwaysOriginal)) { [weak self] _ in
                self?.onHighlight?(color)
            }
        }
        items.append(UIAction(title: "Add note…", image: UIImage(systemName: "note.text.badge.plus")) { [weak self] _ in self?.onAddNote?() })
        builder.insertChild(UIMenu(title: "Highlight", image: UIImage(systemName: "highlighter"), children: items), atStartOfMenu: .standardEdit)
    }
}

struct IOSPDFView: UIViewRepresentable {
    let url: URL
    @ObservedObject var controller: IOSReaderController
    let paperColor: Color
    let readingMode: IOSReadingMode
    var initialPage: Int = 1

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> PDFView {
        let view = IOSPDFKitView()
        let controller = self.controller
        view.onHighlight = { [weak controller] color in controller?.highlight(color) }
        view.onAddNote = { [weak controller] in controller?.onAddNote?() }
        configure(view, resetToFit: true)
        view.isUserInteractionEnabled = true
        view.isInMarkupMode = false
        view.isFindInteractionEnabled = true
        view.delegate = context.coordinator
        controller.pdfView = view
        context.coordinator.attach(to: view)
        loadDocument(in: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.accessibilityIdentifier != url.path {
            loadDocument(in: view)
        }
        configure(view, resetToFit: false)
        if let currentPage = view.currentPage, let document = view.document,
           document.index(for: currentPage) + 1 != controller.page {
            controller.displayPage(controller.page)
        }
    }

    private func configure(_ view: PDFView, resetToFit: Bool) {
        let modeChanged = view.accessibilityValue != readingMode.rawValue
        if resetToFit || modeChanged { view.autoScales = true }
        let paged = readingMode == .pageTurn
        if view.displayDirection != (paged ? .horizontal : .vertical) { view.displayDirection = paged ? .horizontal : .vertical }
        if view.displayMode != (paged ? .singlePage : .singlePageContinuous) { view.displayMode = paged ? .singlePage : .singlePageContinuous }
        if view.displaysPageBreaks != !paged { view.displaysPageBreaks = !paged }
        view.pageBreakMargins = UIEdgeInsets(top: 14, left: 0, bottom: 14, right: 0)
        if view.isUsingPageViewController != paged {
            view.usePageViewController(paged, withViewOptions: [
                UIPageViewController.OptionsKey.interPageSpacing: 18
            ])
        }
        view.backgroundColor = UIColor(paperColor)
        view.pageShadowsEnabled = false
        view.accessibilityValue = readingMode.rawValue
        if resetToFit || modeChanged {
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                view.layoutIfNeeded()
                let fitScale = view.scaleFactorForSizeToFit
                guard fitScale > 0 else { return }
                view.minScaleFactor = max(fitScale * 0.65, 0.1)
                view.maxScaleFactor = max(fitScale * 5.0, 4.0)
                view.autoScales = true
            }
        }
    }

    private func loadDocument(in view: PDFView) {
        let controller = self.controller
        let start = initialPage
        view.accessibilityIdentifier = url.path
        guard FileManager.default.fileExists(atPath: url.path), let document = PDFDocument(url: url) else {
            DispatchQueue.main.async {
                controller.documentReady = false
                controller.documentError = "BookLand could not open this PDF. The file may be damaged or unavailable."
            }
            return
        }
        // Published properties change on the next turn of the run loop, not during a view update.
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            let count = max(1, document.pageCount)
            let target = min(max(start, 1), count)
            controller.documentError = nil
            controller.documentReady = true
            controller.pageCount = count
            controller.history = [target]
            controller.historyIndex = 0
            controller.page = target
            view.document = document
            view.autoScales = true
            controller.displayPage(target)
        }
    }

    final class Coordinator: NSObject, PDFViewDelegate, UIGestureRecognizerDelegate {
        let controller: IOSReaderController
        private var observers: [NSObjectProtocol] = []

        init(controller: IOSReaderController) { self.controller = controller }

        func pdfViewParentViewController(_ pdfView: PDFView) -> UIViewController? {
            var responder: UIResponder? = pdfView
            while let current = responder {
                if let viewController = current as? UIViewController { return viewController }
                responder = current.next
            }
            return nil
        }

        func attach(to view: PDFView) {
            observers.append(NotificationCenter.default.addObserver(forName: Notification.Name.PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                Task { @MainActor in
                    guard let self, let view, let page = view.currentPage, let document = view.document else { return }
                    let number = document.index(for: page) + 1
                    if number != self.controller.page { self.controller.goToPage(number) }
                }
            })
            observers.append(NotificationCenter.default.addObserver(forName: Notification.Name.PDFViewSelectionChanged, object: view, queue: .main) { [weak self, weak view] _ in
                Task { @MainActor in
                    self?.controller.selectedText = view?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
            })

            // A single tap shows or hides the reading controls. It waits for a possible
            // double tap so PDFView's double-tap zoom doesn't also toggle them.
            let single = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            let double = UITapGestureRecognizer()
            double.numberOfTapsRequired = 2
            single.delegate = self
            double.delegate = self
            single.require(toFail: double)
            view.addGestureRecognizer(single)
            view.addGestureRecognizer(double)
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            if let pdfView = gesture.view as? PDFView, let text = pdfView.currentSelection?.string, !text.isEmpty { return }
            let controller = self.controller
            Task { @MainActor in controller.onTap?() }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

/// The PDF with its paper theme applied. Light themes tint the white page by multiplying the
/// paper colour over it; dark themes invert the page and lift the black to the paper colour.
struct IOSStyledPDF: View {
    let url: URL
    @ObservedObject var controller: IOSReaderController
    let paper: Color
    let isDark: Bool
    let isSketchy: Bool
    let mode: IOSReadingMode
    var initialPage: Int = 1

    var body: some View {
        ZStack {
            if isDark {
                IOSPDFView(url: url, controller: controller, paperColor: .white, readingMode: mode, initialPage: initialPage)
                    .colorInvert()
                Color(paper).blendMode(.screen).allowsHitTesting(false)
            } else {
                IOSPDFView(url: url, controller: controller, paperColor: .white, readingMode: mode, initialPage: initialPage)
                Color(paper).blendMode(.multiply).allowsHitTesting(false)
                if isSketchy {
                    IOSPaperTexture().blendMode(.multiply).allowsHitTesting(false)
                }
            }
        }
        .background(paper)
    }
}

struct IOSPaperTexture: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 22
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                while x <= size.width {
                    let wobble = sin((x + y) * 0.035) * 0.8
                    line.addLine(to: CGPoint(x: x, y: y + wobble))
                    x += 22
                }
                context.stroke(line, with: .color(Color.brown.opacity(0.09)), lineWidth: 0.7)
                y += 25
            }

            var fiberX: CGFloat = 12
            while fiberX < size.width {
                var fiber = Path()
                fiber.move(to: CGPoint(x: fiberX, y: 0))
                fiber.addLine(to: CGPoint(x: fiberX + 5, y: size.height))
                context.stroke(fiber, with: .color(Color.brown.opacity(0.025)), lineWidth: 0.8)
                fiberX += 38
            }
        }
    }
}

// MARK: - Reader screen

struct IOSReaderLoader: View {
    @EnvironmentObject private var store: IOSLibraryStore
    let route: IOSReaderRoute

    var body: some View {
        if let book = store.book(route.bookID) {
            IOSReaderView(book: book, startPage: route.page)
        } else {
            ContentUnavailableView("Book not found", systemImage: "questionmark.folder", description: Text("It may have been deleted from the library."))
        }
    }
}

struct IOSReaderView: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    let book: IOSLibraryBook
    let startPage: Int?
    @StateObject private var controller = IOSReaderController()
    @AppStorage("readerTheme") private var appearance: IOSReaderTheme = .milky
    @AppStorage("readerMode") private var readingMode: IOSReadingMode = .pageTurn
    @AppStorage("keepScreenAwake") private var keepAwake = true
    @State private var chromeVisible = true
    @State private var showingHistory = false
    @State private var showingPageBrowser = false
    @State private var showingNoteEditor = false
    @State private var noteQuote = ""
    @State private var sliderValue = 1.0
    @State private var scrubbing = false

    private var paper: Color { appearance.paperColor(systemScheme) }
    private var dark: Bool { appearance.isDark(systemScheme) }
    private var chromeScheme: ColorScheme { dark ? .dark : .light }
    private var initialPage: Int { startPage ?? book.lastPage }

    var body: some View {
        VStack(spacing: 0) {
            if chromeVisible {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ZStack {
                IOSStyledPDF(url: book.fileURL, controller: controller, paper: paper, isDark: dark, isSketchy: appearance.isSketchy, mode: readingMode, initialPage: initialPage)
                if let error = controller.documentError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.orange)
                        Text("This PDF could not be opened").font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(24)
                }
            }
            if chromeVisible {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(paper.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.22), value: chromeVisible)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!chromeVisible)
        .iosToast($controller.toast, edge: .top)
        .onAppear {
            store.markOpened(book)
            sliderValue = Double(initialPage)
            controller.onTap = { chromeVisible.toggle() }
            controller.onAddNote = {
                noteQuote = controller.selectedText
                showingNoteEditor = true
            }
            controller.noteSink = { store.addNote($0, to: book) }
            controller.noteRemoveSink = { id in
                if let current = store.book(book.id), let note = current.notes.first(where: { $0.id == id }) { store.deleteNote(note, from: current) }
            }
            controller.highlightNotesRemoveSink = { page, text in
                guard let current = store.book(book.id) else { return }
                for note in current.notes where note.isHighlight && note.page == page && (text.isEmpty || text.contains(note.text) || note.text.contains(text)) {
                    store.deleteNote(note, from: current)
                }
            }
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: controller.page) { _, page in
            store.updatePage(page, for: book)
            if !scrubbing { sliderValue = Double(page) }
        }
        .onChange(of: controller.pageCount) { _, count in
            if controller.documentReady { store.setPageCount(count, for: book) }
        }
        .sheet(isPresented: $showingHistory) { IOSPageHistorySheet(controller: controller) }
        .sheet(isPresented: $showingPageBrowser) { IOSPageBrowserSheet(controller: controller) }
        .sheet(isPresented: $showingNoteEditor) {
            IOSNoteEditorSheet(page: controller.page, quote: noteQuote) { text in
                store.addNote(IOSLibraryNote(page: controller.page, text: text, kind: "Note", quote: noteQuote.isEmpty ? nil : noteQuote), to: book)
                controller.toast = "Note saved"
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .font(.headline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back to library")

            Text(book.title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)

            Menu {
                Picker("Reading mode", selection: $readingMode) {
                    ForEach(IOSReadingMode.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }
            } label: {
                Image(systemName: readingMode.icon).frame(width: 40, height: 44)
            }
            .accessibilityLabel("Reading mode")

            Menu {
                Picker("Paper", selection: $appearance) {
                    ForEach(IOSReaderTheme.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }
            } label: {
                Image(systemName: appearance.icon).frame(width: 40, height: 44)
            }
            .accessibilityLabel("Paper theme")

            Menu {
                Button { controller.zoomIn() } label: { Label("Zoom in", systemImage: "plus.magnifyingglass") }
                Button { controller.zoomOut() } label: { Label("Zoom out", systemImage: "minus.magnifyingglass") }
                Button { controller.fitToScreen() } label: { Label("Fit to screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                Divider()
                Button { showingHistory = true } label: { Label("Reading history", systemImage: "clock.arrow.circlepath") }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 40, height: 44)
            }
            .accessibilityLabel("More")
        }
        .font(.title3)
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .background(paper)
        .overlay(alignment: .bottom) { Divider() }
        .environment(\.colorScheme, chromeScheme)
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            if controller.pageCount > 1 {
                Slider(value: $sliderValue, in: 1...Double(controller.pageCount), step: 1) { editing in
                    scrubbing = editing
                    if !editing { controller.commitScrub() }
                }
                .tint(IOSDesign.accent)
                .onChange(of: sliderValue) { _, value in
                    if scrubbing { controller.displayPage(Int(value)) }
                }
                .accessibilityLabel("Page slider")
                .accessibilityValue("Page \(controller.page) of \(controller.pageCount)")
            }
            IOSReaderToolbar(controller: controller, showingPageBrowser: $showingPageBrowser)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(paper)
        .overlay(alignment: .top) { Divider() }
        .environment(\.colorScheme, chromeScheme)
    }
}

struct IOSChipLabel: View {
    let systemName: String
    var tint: Color = .primary
    var enabled = true
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.headline)
            .frame(width: size, height: size)
            .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.45))
            .background(Circle().fill((enabled ? tint : Color.secondary).opacity(0.1)))
            .contentShape(Circle())
    }
}

struct IOSReaderToolbar: View {
    @ObservedObject var controller: IOSReaderController
    @Binding var showingPageBrowser: Bool
    var compact = false
    @State private var showingPageJump = false

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            Button(action: controller.goToPreviousPage) {
                IOSChipLabel(systemName: "chevron.left", enabled: controller.canGoToPreviousPage)
            }
            .disabled(!controller.canGoToPreviousPage)
            .accessibilityLabel("Previous page")

            Button { showingPageJump = true } label: {
                VStack(spacing: 0) {
                    Text("\(controller.page)").font(.headline.monospacedDigit())
                    Text("of \(controller.pageCount)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(minWidth: 48, minHeight: 40)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Page \(controller.page) of \(controller.pageCount). Jump to page")

            Button(action: controller.goToNextPage) {
                IOSChipLabel(systemName: "chevron.right", enabled: controller.canGoToNextPage)
            }
            .disabled(!controller.canGoToNextPage)
            .accessibilityLabel("Next page")

            Spacer(minLength: 0)

            Button { showingPageBrowser = true } label: { IOSChipLabel(systemName: "square.grid.2x2") }
                .accessibilityLabel("Pages and index")

            Button { controller.presentSearch() } label: { IOSChipLabel(systemName: "magnifyingglass") }
                .accessibilityLabel("Search in book")

            if !compact {
                Menu {
                    ForEach(IOSHighlightColor.allCases) { color in
                        Button { controller.highlight(color) } label: { Label("Highlight \(color.rawValue.lowercased())", systemImage: "highlighter") }
                    }
                    if let onAddNote = controller.onAddNote {
                        Button(action: onAddNote) { Label("Add note…", systemImage: "note.text.badge.plus") }
                    }
                    Divider()
                    Button { controller.undoHighlight() } label: { Label("Undo last highlight", systemImage: "arrow.uturn.backward") }
                        .disabled(!controller.canUndoHighlight)
                    Button(role: .destructive) { controller.removeHighlight() } label: { Label("Remove highlight here", systemImage: "eraser") }
                        .disabled(!controller.canRemoveHighlight)
                } label: {
                    IOSChipLabel(systemName: "highlighter", tint: IOSDesign.accent)
                }
                .accessibilityLabel("Highlight and notes")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .sheet(isPresented: $showingPageJump) {
            IOSPageJumpSheet(controller: controller)
        }
    }
}

struct IOSPageJumpSheet: View {
    @ObservedObject var controller: IOSReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var pageText = ""
    @FocusState private var focused: Bool

    private var target: Int? {
        guard let value = Int(pageText), (1...controller.pageCount).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Page number") {
                    TextField("1–\(controller.pageCount)", text: $pageText)
                        .keyboardType(.numberPad)
                        .focused($focused)
                }
            }
            .navigationTitle("Jump to page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        if let target { controller.goToPage(target) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(target == nil)
                }
            }
            .onAppear {
                pageText = "\(controller.page)"
                focused = true
            }
        }
        .presentationDetents([.height(220)])
    }
}

struct IOSNoteEditorSheet: View {
    let page: Int
    let quote: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if !quote.isEmpty {
                    Section("Selected passage") {
                        Text(quote).font(.subheadline).foregroundStyle(.secondary).lineLimit(6)
                    }
                }
                Section("Your note · page \(page)") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .focused($focused)
                }
            }
            .navigationTitle("Add note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

struct IOSPageHistorySheet: View {
    @ObservedObject var controller: IOSReaderController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Array(controller.history.enumerated()).reversed(), id: \.offset) { entry in
                Button {
                    controller.goToHistory(entry.offset)
                    dismiss()
                } label: {
                    HStack {
                        Text("Page \(entry.element)")
                        Spacer()
                        if entry.offset == controller.historyIndex {
                            Text("You are here").font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "checkmark").foregroundStyle(IOSDesign.accent)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Page history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .overlay {
                if controller.history.count <= 1 {
                    ContentUnavailableView("Nothing yet", systemImage: "clock.arrow.circlepath", description: Text("Pages you visit are listed here so you can jump back."))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct IOSOutlineRow: Identifiable {
    let id: String
    let title: String
    let page: Int?
    let depth: Int
}

struct IOSPageBrowserSheet: View {
    @ObservedObject var controller: IOSReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var browserMode = 0

    private var document: PDFDocument? { controller.pdfView?.document }

    private var outlineRows: [IOSOutlineRow] {
        guard let root = document?.outlineRoot else { return [] }
        return flattenOutline(root, depth: 0, path: "0")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Browse", selection: $browserMode) {
                    Text("Pages").tag(0)
                    Text("Index").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if browserMode == 0 {
                    pageGrid
                } else if outlineRows.isEmpty {
                    ContentUnavailableView("No index in this PDF", systemImage: "list.bullet.indent", description: Text("This PDF does not contain a navigable outline."))
                } else {
                    List(outlineRows) { row in
                        Button {
                            guard let page = row.page else { return }
                            controller.goToPage(page)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: row.page == nil ? "folder" : "bookmark")
                                    .foregroundStyle(IOSDesign.accent)
                                Text(row.title).lineLimit(2)
                                Spacer()
                                if let page = row.page {
                                    Text(String(page)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, CGFloat(row.depth) * 16)
                        }
                        .foregroundStyle(.primary)
                        .disabled(row.page == nil)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pages & Index")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var pageGrid: some View {
        if let document {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 14)], spacing: 16) {
                        ForEach(0..<document.pageCount, id: \.self) { index in
                            if let page = document.page(at: index) {
                                let isCurrent = index + 1 == controller.page
                                Button {
                                    controller.goToPage(index + 1)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(uiImage: page.thumbnail(of: CGSize(width: 92, height: 126), for: .cropBox))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 126)
                                            .background(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(isCurrent ? IOSDesign.accent : .clear, lineWidth: 2.5))
                                            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                                        Text("Page \(index + 1)")
                                            .font(.caption.monospacedDigit().weight(isCurrent ? .semibold : .regular))
                                            .foregroundStyle(isCurrent ? IOSDesign.accent : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .id(index + 1)
                            }
                        }
                    }
                    .padding(16)
                }
                .onAppear { proxy.scrollTo(controller.page, anchor: .center) }
            }
        } else {
            ContentUnavailableView("PDF is not ready", systemImage: "doc.text.magnifyingglass")
        }
    }

    private func flattenOutline(_ outline: PDFOutline, depth: Int, path: String) -> [IOSOutlineRow] {
        var rows: [IOSOutlineRow] = []
        for index in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: index) else { continue }
            let childPath = path + "." + String(index)
            let page: Int?
            if let destinationPage = child.destination?.page, let document {
                page = document.index(for: destinationPage) + 1
            } else {
                page = nil
            }
            let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append(IOSOutlineRow(id: childPath, title: title?.isEmpty == false ? title! : "Untitled section", page: page, depth: depth))
            rows.append(contentsOf: flattenOutline(child, depth: depth + 1, path: childPath))
        }
        return rows
    }
}
