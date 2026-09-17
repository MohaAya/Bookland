// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../LICENSE.

import Foundation
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct IOSLibraryNote: Identifiable, Hashable, Codable {
    let id: UUID
    let page: Int
    let text: String
    let kind: String

    init(id: UUID = UUID(), page: Int, text: String, kind: String) {
        self.id = id
        self.page = page
        self.text = text
        self.kind = kind
    }
}

struct IOSLibraryBook: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var fileURL: URL
    var tags: [String]
    var lastPage: Int
    var notes: [IOSLibraryNote]
    var dateAdded: Date
    var lastOpenedAt: Date?

    init(id: UUID = UUID(), title: String, fileURL: URL, tags: [String] = [], lastPage: Int = 1, notes: [IOSLibraryNote] = [], dateAdded: Date = .now, lastOpenedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.tags = tags
        self.lastPage = lastPage
        self.notes = notes
        self.dateAdded = dateAdded
        self.lastOpenedAt = lastOpenedAt
    }
}

@MainActor
final class IOSLibraryStore: ObservableObject {
    @Published private(set) var books: [IOSLibraryBook] = []
    @Published var importError: String?
    @Published var pendingImportURL: URL?
    @Published var pendingImportTitle = ""

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var metadataURL: URL { documentsURL.appendingPathComponent("library.json") }

    init() { load() }

    /// Receives a PDF from Telegram, Mail, Safari, Files, or another app's
    /// Share/Open in action. The file is staged immediately because the
    /// security-scoped URL may not remain available while the title sheet is open.
    func prepareIncomingPDF(from incomingURL: URL) {
        guard incomingURL.isFileURL,
              incomingURL.pathExtension.lowercased() == "pdf" else {
            importError = "BookLand can receive PDF files only."
            return
        }

        let accessed = incomingURL.startAccessingSecurityScopedResource()
        defer { if accessed { incomingURL.stopAccessingSecurityScopedResource() } }

        let stagedURL = documentsURL.appendingPathComponent("incoming-\(UUID().uuidString).pdf")
        do {
            try FileManager.default.copyItem(at: incomingURL, to: stagedURL)
            pendingImportURL = stagedURL
            pendingImportTitle = incomingURL.deletingPathExtension().lastPathComponent
        } catch {
            importError = "Could not receive this PDF from the other app. Please try Share → Open in BookLand again."
        }
    }

    func completePendingImport() {
        guard let pendingImportURL else { return }
        let title = pendingImportTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        addCopiedPDF(at: pendingImportURL, title: title.isEmpty ? "Untitled PDF" : title)
        self.pendingImportURL = nil
        pendingImportTitle = ""
    }

    func cancelPendingImport() {
        if let pendingImportURL { try? FileManager.default.removeItem(at: pendingImportURL) }
        pendingImportURL = nil
        pendingImportTitle = ""
    }

    func importPDF(from incomingURL: URL, preferredTitle: String? = nil) {
        guard incomingURL.isFileURL else {
            importError = "BookLand received an invalid file location."
            return
        }
        let accessed = incomingURL.startAccessingSecurityScopedResource()
        defer { if accessed { incomingURL.stopAccessingSecurityScopedResource() } }

        let title = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? preferredTitle!.trimmingCharacters(in: .whitespacesAndNewlines)
            : incomingURL.deletingPathExtension().lastPathComponent
        do {
            let destination = documentsURL.appendingPathComponent("\(UUID().uuidString).pdf")
            try FileManager.default.copyItem(at: incomingURL, to: destination)
            addBook(title: title, fileURL: destination)
        } catch {
            importError = "Could not copy this PDF into BookLand. Please try Share → Save to Files first, then import it again."
        }
    }

    private func addCopiedPDF(at sourceURL: URL, title: String) {
        let destination = documentsURL.appendingPathComponent("\(UUID().uuidString).pdf")
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destination)
            addBook(title: title, fileURL: destination)
        } catch {
            importError = "Could not copy this PDF into BookLand. Please try Share → Open in BookLand again."
            try? FileManager.default.removeItem(at: sourceURL)
        }
    }

    private func addBook(title: String, fileURL: URL) {
        books.insert(IOSLibraryBook(title: title, fileURL: fileURL), at: 0)
        save()
    }

    func removeBook(_ book: IOSLibraryBook) {
        books.removeAll { $0.id == book.id }
        try? FileManager.default.removeItem(at: book.fileURL)
        save()
    }

    func markOpened(_ book: IOSLibraryBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].lastOpenedAt = .now
        save()
    }

    func updatePage(_ page: Int, for book: IOSLibraryBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].lastPage = max(1, page)
        save()
    }

    func addNote(_ note: IOSLibraryNote, to book: IOSLibraryBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].notes.insert(note, at: 0)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL), let saved = try? JSONDecoder().decode([IOSLibraryBook].self, from: data) else { return }
        books = saved.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }
}

@main
struct BookLandiOSApp: App {
    @StateObject private var store = IOSLibraryStore()

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(store)
                .onOpenURL { url in
                    // Handles Files, Mail, Telegram, Safari downloads, and any app's “Open in…” action.
                    store.prepareIncomingPDF(from: url)
                }
                .sheet(isPresented: Binding(
                    get: { store.pendingImportURL != nil },
                    set: { if !$0 { store.cancelPendingImport() } }
                )) {
                    IOSImportTitleSheet(title: $store.pendingImportTitle) {
                        store.completePendingImport()
                    }
                }
        }
    }
}

struct IOSRootView: View {
    var body: some View {
        TabView {
            IOSLibraryHome()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            IOSNotesView()
                .tabItem { Label("Notes", systemImage: "highlighter") }
            IOSCompareHome()
                .tabItem { Label("Compare", systemImage: "rectangle.split.2x1") }
            IOSSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(IOSDesign.accent)
    }
}

enum IOSDesign {
    static let accent = Color(red: 0.12, green: 0.42, blue: 0.48)
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.18)
    static let paper = Color(red: 0.98, green: 0.96, blue: 0.89)
    static let milky = Color(red: 0.96, green: 0.94, blue: 0.86)
}

enum IOSReadingMode: String, CaseIterable, Identifiable {
    case pageTurn = "Page turn"
    case verticalScroll = "Vertical scroll"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .pageTurn: return "book.pages"
        case .verticalScroll: return "scroll"
        }
    }
}

enum IOSReaderTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case milky = "Milky paper"
    case sepia = "Sepia paper"
    case blue = "Blue grey"
    case sage = "Sage study"
    case sketchbook = "Sketchbook"
    case midnight = "Midnight navy"
    case graphite = "Graphite night"
    case nightAmber = "Amber night"

    var id: String { rawValue }

    var paperColor: Color {
        switch self {
        case .system: return Color(uiColor: .systemBackground)
        case .milky: return IOSDesign.milky
        case .sepia: return Color(red: 0.92, green: 0.84, blue: 0.68)
        case .blue: return Color(red: 0.82, green: 0.90, blue: 0.98)
        case .sage: return Color(red: 0.87, green: 0.93, blue: 0.87)
        case .sketchbook: return Color(red: 0.95, green: 0.92, blue: 0.82)
        case .midnight: return Color(red: 0.055, green: 0.09, blue: 0.18)
        case .graphite: return Color(red: 0.12, green: 0.14, blue: 0.17)
        case .nightAmber: return Color(red: 0.20, green: 0.15, blue: 0.09)
        }
    }

    var isDark: Bool {
        switch self {
        case .midnight, .graphite, .nightAmber: return true
        default: return false
        }
    }

    var isSketchy: Bool { self == .sketchbook }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .milky: return "sun.max"
        case .sepia: return "book.closed"
        case .blue: return "cloud"
        case .sage: return "leaf"
        case .sketchbook: return "pencil.and.scribble"
        case .midnight: return "moon.stars"
        case .graphite: return "circle.dotted"
        case .nightAmber: return "moon.haze"
        }
    }
}

struct IOSLibraryHome: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @State private var showingImporter = false
    @State private var showingTitlePrompt = false
    @State private var incomingURL: URL?
    @State private var incomingTitle = ""
    @State private var searchText = ""

    private var filteredBooks: [IOSLibraryBook] {
        guard !searchText.isEmpty else { return store.books }
        return store.books.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    IOSHeroHeader(showingImporter: $showingImporter)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    IOSImportHint()
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 14, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                Section("Your library") {
                    if filteredBooks.isEmpty {
                        IOSEmptyLibrary(showingImporter: $showingImporter)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredBooks) { book in
                            NavigationLink {
                                IOSReaderView(book: book)
                            } label: {
                                IOSBookCard(book: book)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { store.removeBook(book) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) { store.removeBook(book) } label: {
                                    Label("Delete from Library", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { filteredBooks[$0] }.forEach(store.removeBook)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(IOSDesign.ink.opacity(0.035).ignoresSafeArea())
            .navigationTitle("BookLand")
            .searchable(text: $searchText, prompt: "Search books and topics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImporter = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    incomingURL = url
                    incomingTitle = url.deletingPathExtension().lastPathComponent
                    showingTitlePrompt = true
                case .failure:
                    store.importError = "The PDF picker could not open this file."
                }
            }
            .sheet(isPresented: $showingTitlePrompt) {
                IOSImportTitleSheet(title: $incomingTitle) {
                    if let incomingURL { store.importPDF(from: incomingURL, preferredTitle: incomingTitle) }
                    showingTitlePrompt = false
                }
            }
            .alert("Import failed", isPresented: Binding(get: { store.importError != nil }, set: { if !$0 { store.importError = nil } })) {
                Button("OK") { store.importError = nil }
            } message: {
                Text(store.importError ?? "")
            }
        }
    }
}

struct IOSHeroHeader: View {
    @Binding var showingImporter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Read quietly.")
                        .font(.largeTitle.weight(.bold))
                    Text("Your research, books, and ideas in one calm place.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(IOSDesign.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Button { showingImporter = true } label: {
                Label("Import a PDF", systemImage: "arrow.down.doc.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(IOSDesign.accent)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct IOSImportHint: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "paperclip.circle.fill")
                .font(.title2)
                .foregroundStyle(IOSDesign.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Import from anywhere").font(.headline)
                Text("From Telegram, open the PDF, tap Share, choose More, then BookLand. From Mail, Files, or Safari, use Share or Open in…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(15)
        .background(IOSDesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct IOSBookCard: View {
    let book: IOSLibraryBook

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [IOSDesign.accent, IOSDesign.accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 54, height: 72)
                .overlay(Image(systemName: "doc.text.fill").foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title).font(.headline).foregroundStyle(IOSDesign.ink).lineLimit(2)
                Text("Page \(book.lastPage)").font(.caption).foregroundStyle(.secondary)
                if !book.tags.isEmpty {
                    Text(book.tags.joined(separator: "  ·  ")).font(.caption2).foregroundStyle(IOSDesign.accent).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct IOSEmptyLibrary: View {
    @Binding var showingImporter: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 42))
                .foregroundStyle(IOSDesign.accent)
            Text("Your library is ready").font(.title3.weight(.semibold))
            Text("Import a PDF from Files or another app to begin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose a PDF") { showingImporter = true }
                .buttonStyle(.borderedProminent)
                .tint(IOSDesign.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct IOSImportTitleSheet: View {
    @Binding var title: String
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Library title") {
                    TextField("Title", text: $title)
                }
                Section {
                Text("The original PDF is copied into BookLand, so it remains available even if the attachment disappears from the other app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add PDF")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import", action: onImport).fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium])
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
    private var lastHighlightAnnotations: [(PDFPage, PDFAnnotation)] = []

    var previousPage: Int? { historyIndex > 0 ? history[historyIndex - 1] : nil }
    var nextPage: Int? { historyIndex + 1 < history.count ? history[historyIndex + 1] : nil }
    var canGoToPreviousPage: Bool { page > 1 }
    var canGoToNextPage: Bool { page < pageCount }
    var canRemoveHighlight: Bool {
        guard let selection = pdfView?.currentSelection else { return false }
        return selection.pages.contains { page in
            let bounds = selection.bounds(for: page)
            return page.annotations.contains { annotation in
                annotation.type == "Highlight" && !annotation.bounds.intersection(bounds).isEmpty
            }
        }
    }

    func goToPage(_ page: Int) {
        let target = min(max(page, 1), pageCount)
        guard let document = pdfView?.document, let pdfPage = document.page(at: target - 1) else { return }
        if target != self.page {
            if historyIndex + 1 < history.count { history.removeSubrange((historyIndex + 1)..<history.count) }
            if history.last != target { history.append(target) }
            historyIndex = history.count - 1
        }
        self.page = target
        if pdfView?.currentPage !== pdfPage { pdfView?.go(to: pdfPage) }
    }

    func displayPage(_ page: Int) {
        let target = min(max(page, 1), pageCount)
        guard let document = pdfView?.document, let pdfPage = document.page(at: target - 1) else { return }
        self.page = target
        if pdfView?.currentPage !== pdfPage { pdfView?.go(to: pdfPage) }
    }

    func goBack() { guard historyIndex > 0 else { return }; goToHistory(historyIndex - 1) }
    func goForward() { guard historyIndex + 1 < history.count else { return }; goToHistory(historyIndex + 1) }
    func goToPreviousPage() { guard canGoToPreviousPage else { return }; goToPage(page - 1) }
    func goToNextPage() { guard canGoToNextPage else { return }; goToPage(page + 1) }

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
    func goToHistory(_ index: Int) {
        guard history.indices.contains(index), let document = pdfView?.document, let pdfPage = document.page(at: history[index] - 1) else { return }
        historyIndex = index
        page = history[index]
        pdfView?.go(to: pdfPage)
    }

    func highlight(_ color: UIColor) -> Bool {
        guard let selection = pdfView?.currentSelection, let document = pdfView?.document else { return false }
        var created: [(PDFPage, PDFAnnotation)] = []
        for page in selection.pages {
            let bounds = selection.bounds(for: page)
            guard !bounds.isEmpty else { continue }
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = color.withAlphaComponent(0.45)
            page.addAnnotation(annotation)
            created.append((page, annotation))
        }
        guard !created.isEmpty else { return false }
        lastHighlightAnnotations = created
        canUndoHighlight = true
        _ = document.write(to: document.documentURL ?? URL(fileURLWithPath: "/dev/null"))
        return true
    }

    func undoHighlight() {
        guard let document = pdfView?.document else { return }
        lastHighlightAnnotations.forEach { $0.0.removeAnnotation($0.1) }
        lastHighlightAnnotations = []
        canUndoHighlight = false
        _ = document.write(to: document.documentURL ?? URL(fileURLWithPath: "/dev/null"))
    }

    func removeHighlight() {
        guard let selection = pdfView?.currentSelection, let document = pdfView?.document else { return }
        for page in selection.pages {
            let bounds = selection.bounds(for: page)
            page.annotations.filter { annotation in
                annotation.type == "Highlight" && !annotation.bounds.intersection(bounds).isEmpty
            }.forEach { page.removeAnnotation($0) }
        }
        lastHighlightAnnotations = []
        canUndoHighlight = false
        _ = document.write(to: document.documentURL ?? URL(fileURLWithPath: "/dev/null"))
    }
}

struct IOSPDFView: UIViewRepresentable {
    let url: URL
    @ObservedObject var controller: IOSReaderController
    let paperColor: Color
    let readingMode: IOSReadingMode

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view, resetToFit: true)
        view.isUserInteractionEnabled = true
        view.isInMarkupMode = false
        view.isFindInteractionEnabled = true
        view.delegate = context.coordinator
        controller.pdfView = view
        context.coordinator.attach(to: view)
        loadDocument(in: view, resetHistory: true)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.accessibilityIdentifier != url.path {
            loadDocument(in: view, resetHistory: true)
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
        view.displayDirection = readingMode == .pageTurn ? .horizontal : .vertical
        view.displayMode = readingMode == .pageTurn ? .singlePage : .singlePageContinuous
        view.displaysPageBreaks = readingMode == .verticalScroll
        view.pageBreakMargins = UIEdgeInsets(top: 14, left: 0, bottom: 14, right: 0)
        if view.isUsingPageViewController != (readingMode == .pageTurn) {
            view.usePageViewController(readingMode == .pageTurn, withViewOptions: [
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

    private func loadDocument(in view: PDFView, resetHistory: Bool) {
        guard FileManager.default.fileExists(atPath: url.path), let document = PDFDocument(url: url) else {
            controller.documentReady = false
            controller.documentError = "BookLand could not open this PDF. The file may be damaged or unavailable."
            return
        }
        view.document = document
        view.accessibilityIdentifier = url.path
        view.autoScales = true
        controller.documentError = nil
        controller.documentReady = true
        controller.pageCount = max(1, document.pageCount)
        if resetHistory {
            controller.history = [1]
            controller.historyIndex = 0
            controller.page = 1
        }
        controller.displayPage(controller.page)
    }

    final class Coordinator: NSObject, PDFViewDelegate {
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
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

struct IOSReaderView: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @Environment(\.dismiss) private var dismiss
    let book: IOSLibraryBook
    @StateObject private var controller = IOSReaderController()
    @State private var appearance: IOSReaderTheme = .milky
    @State private var readingMode: IOSReadingMode = .pageTurn
    @State private var pageText = "1"
    @State private var showingHistory = false
    @State private var showingPageBrowser = false
    @State private var isFullScreen = false
    @State private var fullScreenControlsVisible = true

    private var paperColor: Color { appearance.paperColor }

    var body: some View {
        Group {
            if isFullScreen {
                fullScreenReader
            } else {
                standardReader
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isFullScreen ? .hidden : .visible, for: .tabBar)
        .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(isFullScreen)
        .onAppear {
            store.markOpened(book)
            controller.page = book.lastPage
            pageText = "\(book.lastPage)"
        }
        .onChange(of: controller.page) { _, page in
            pageText = "\(page)"
            store.updatePage(page, for: book)
        }
        .sheet(isPresented: $showingHistory) {
            IOSPageHistorySheet(controller: controller)
        }
        .sheet(isPresented: $showingPageBrowser) {
            IOSPageBrowserSheet(controller: controller)
        }
    }

    private var standardReader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.backward")
                        .font(.headline.weight(.semibold))
                }
                .accessibilityLabel("Back to library")
                Image(systemName: "book.pages")
                    .foregroundStyle(IOSDesign.accent)
                Text(book.title).font(.headline).lineLimit(1)
                Spacer()
                Menu {
                    ForEach(IOSReadingMode.allCases) { mode in
                        Button { readingMode = mode } label: {
                            Label(mode.rawValue, systemImage: mode.icon)
                        }
                    }
                } label: {
                    Image(systemName: readingMode.icon)
                }
                Menu {
                    ForEach(IOSReaderTheme.allCases) { theme in
                        Button {
                            appearance = theme
                        } label: {
                            Label(theme.rawValue, systemImage: theme.icon)
                        }
                    }
                } label: { Image(systemName: appearance.icon) }
                Button {
                    fullScreenControlsVisible = true
                    isFullScreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Enter full screen")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

                readerPageSurface
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                    IOSReaderToolbar(controller: controller, pageText: $pageText, showingHistory: $showingHistory, showingPageBrowser: $showingPageBrowser)
                }
        }
    }

    private var fullScreenReader: some View {
        GeometryReader { proxy in
            let sideInset = max(max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing), 14)
            let topInset = proxy.safeAreaInsets.top > 0
                ? proxy.safeAreaInsets.top
                : (proxy.size.height > proxy.size.width ? 52 : 12)
            let bottomInset = proxy.safeAreaInsets.bottom > 0
                ? proxy.safeAreaInsets.bottom
                : (proxy.size.height > proxy.size.width ? 24 : 12)

            ZStack {
                readerPageSurface

                if fullScreenControlsVisible {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.backward")
                                    .font(.headline.weight(.semibold))
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.plain)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Back to library")

                            Text(book.title)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                        }

                        // Keep the actions on their own row so they cannot be clipped by
                        // the Dynamic Island or squeezed out by a long book title.
                        HStack(spacing: 14) {
                            Menu {
                                ForEach(IOSReadingMode.allCases) { mode in
                                    Button { readingMode = mode } label: {
                                        Label(mode.rawValue, systemImage: mode.icon)
                                    }
                                }
                            } label: {
                                Image(systemName: readingMode.icon)
                                    .font(.headline)
                                    .frame(width: 38, height: 38)
                            }
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Reading mode")

                            Menu {
                                ForEach(IOSReaderTheme.allCases) { theme in
                                    Button { appearance = theme } label: {
                                        Label(theme.rawValue, systemImage: theme.icon)
                                    }
                                }
                            } label: {
                                Image(systemName: appearance.icon)
                                    .font(.headline)
                                    .frame(width: 38, height: 38)
                            }
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Paper theme")

                            Button {
                                isFullScreen = false
                            } label: {
                                Image(systemName: "arrow.down.right.and.arrow.up.left")
                                    .font(.headline)
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.plain)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Exit full screen")

                            Button {
                                fullScreenControlsVisible = false
                            } label: {
                                Image(systemName: "rectangle.compress.vertical")
                                    .font(.headline)
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.plain)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Hide reading controls")
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(IOSDesign.ink)
                        .padding(.bottom, 2)

                        Spacer()

                        IOSReaderToolbar(controller: controller, pageText: $pageText, showingHistory: $showingHistory, showingPageBrowser: $showingPageBrowser)
                            .padding(.bottom, bottomInset + 4)
                    }
                    .padding(.horizontal, sideInset)
                    .padding(.top, topInset + 8)
                    .foregroundStyle(IOSDesign.ink)
                } else {
                    VStack {
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.backward")
                                    .font(.headline.weight(.semibold))
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(.plain)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Back to library")
                            Spacer()
                            Button {
                                fullScreenControlsVisible = true
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.headline.weight(.bold))
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(.plain)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Show reading controls")
                        }
                        .padding(.horizontal, sideInset)
                        .padding(.top, topInset + 8)
                        Spacer()
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(paperColor)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var readerPageSurface: some View {
        ZStack {
            styledPDFView
            if let error = controller.documentError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.orange)
                    Text("This PDF could not be opened")
                        .font(.headline)
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
    }

    @ViewBuilder
    private var styledPDFView: some View {
        if appearance.isDark {
            ZStack {
                IOSPDFView(url: book.fileURL, controller: controller, paperColor: .white, readingMode: readingMode)
                    .colorInvert()
                Color(paperColor)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .background(paperColor)
        } else {
            ZStack {
                IOSPDFView(url: book.fileURL, controller: controller, paperColor: paperColor, readingMode: readingMode)
                Color(paperColor)
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
                if appearance.isSketchy {
                    IOSPaperTexture()
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                }
            }
            .background(paperColor)
        }
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

struct IOSReaderToolbar: View {
    @ObservedObject var controller: IOSReaderController
    @Binding var pageText: String
    @Binding var showingHistory: Bool
    @Binding var showingPageBrowser: Bool
    @State private var showingPageJump = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: controller.goToPreviousPage) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(controller.canGoToPreviousPage ? IOSDesign.ink : Color.secondary.opacity(0.42))
            .background(Circle().fill(.white.opacity(0.76)))
            .disabled(!controller.canGoToPreviousPage)
            .accessibilityLabel("Previous page")

            Button {
                pageText = "\(controller.page)"
                showingPageJump = true
            } label: {
                VStack(spacing: 0) {
                    Text("\(controller.page)")
                        .font(.headline.monospacedDigit())
                    Text("of \(controller.pageCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(IOSDesign.ink)
            .accessibilityLabel("Jump to page")

            Button(action: controller.goToNextPage) {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(controller.canGoToNextPage ? IOSDesign.ink : Color.secondary.opacity(0.42))
            .background(Circle().fill(.white.opacity(0.76)))
            .disabled(!controller.canGoToNextPage)
            .accessibilityLabel("Next page")

            Spacer(minLength: 2)

            Button { showingHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.headline)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(IOSDesign.ink)
            .background(Circle().fill(.white.opacity(0.76)))
            .accessibilityLabel("Reading history")

            Button { showingPageBrowser = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.headline)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(IOSDesign.ink)
            .background(Circle().fill(.white.opacity(0.76)))
            .accessibilityLabel("Pages and index")

            Menu {
                Button("Zoom in") { controller.zoomIn() }
                Button("Zoom out") { controller.zoomOut() }
                Divider()
                Button("Fit to screen") { controller.fitToScreen() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .frame(width: 38, height: 38)
            }
            .foregroundStyle(IOSDesign.ink)
            .background(Circle().fill(.white.opacity(0.76)))
            .accessibilityLabel("Zoom controls")

            Menu {
                Button("Yellow") { _ = controller.highlight(.systemYellow) }
                Button("Green") { _ = controller.highlight(.systemGreen) }
                Button("Pink") { _ = controller.highlight(.systemPink) }
                Button("Blue") { _ = controller.highlight(.systemBlue) }
                Divider()
                Button("Undo Last Highlight") { controller.undoHighlight() }.disabled(!controller.canUndoHighlight)
                Button("Remove Highlight Here") { controller.removeHighlight() }.disabled(!controller.canRemoveHighlight)
            } label: {
                Image(systemName: "highlighter")
                    .font(.headline)
                    .frame(width: 38, height: 38)
            }
            .foregroundStyle(IOSDesign.accent)
            .background(Circle().fill(IOSDesign.accent.opacity(0.14)))
            .accessibilityLabel("Highlight tools")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .sheet(isPresented: $showingPageJump) {
            IOSPageJumpSheet(controller: controller, pageText: $pageText)
        }
    }
}

struct IOSPageJumpSheet: View {
    @ObservedObject var controller: IOSReaderController
    @Binding var pageText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Page number") {
                    TextField("1–\(controller.pageCount)", text: $pageText)
                        .keyboardType(.numberPad)
                }
                Button("Go to page") {
                    if let page = Int(pageText) { controller.goToPage(page) }
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            .navigationTitle("Jump to page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .presentationDetents([.height(230)])
        }
    }
}

struct IOSPageHistorySheet: View {
    @ObservedObject var controller: IOSReaderController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Array(controller.history.enumerated()), id: \.offset) { entry in
                Button {
                    controller.goToHistory(entry.offset)
                    dismiss()
                } label: {
                    HStack {
                        Text("Page \(entry.element)")
                        Spacer()
                        if entry.offset == controller.historyIndex { Image(systemName: "checkmark") }
                    }
                }
            }
            .navigationTitle("Page history")
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
                                Text(row.title)
                                    .lineLimit(2)
                                Spacer()
                                if let page = row.page {
                                    Text(String(page))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, CGFloat(row.depth) * 16)
                        }
                        .disabled(row.page == nil)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pages & Index")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var pageGrid: some View {
        if let document {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 14)], spacing: 16) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        if let page = document.page(at: index) {
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
                                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                                    Text("Page (index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(index + 1 == controller.page ? IOSDesign.accent : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
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

struct IOSNotesView: View {
    @EnvironmentObject private var store: IOSLibraryStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.books) { book in
                    ForEach(book.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).font(.caption.weight(.semibold)).foregroundStyle(IOSDesign.accent)
                            Text(note.text).font(.body)
                            Text("Page \(note.page)  ·  \(note.kind)").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .overlay {
                if store.books.allSatisfy({ $0.notes.isEmpty }) {
                    ContentUnavailableView("No notes yet", systemImage: "highlighter", description: Text("Highlights and notes from your books will appear here."))
                }
            }
            .navigationTitle("Notes & Highlights")
        }
    }
}

struct IOSCompareHome: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @State private var leftID: UUID?
    @State private var rightID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if store.books.count >= 1 {
                    IOSCompareView(leftID: $leftID, rightID: $rightID)
                } else {
                    ContentUnavailableView("Import a PDF first", systemImage: "rectangle.split.2x1", description: Text("Choose two books from your library to compare them."))
                }
            }
            .navigationTitle("Compare")
            .onAppear {
                leftID = leftID ?? store.books.first?.id
                rightID = rightID ?? store.books.dropFirst().first?.id ?? store.books.first?.id
            }
        }
    }
}

struct IOSCompareView: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @Binding var leftID: UUID?
    @Binding var rightID: UUID?
    @State private var leftAppearance: IOSReaderTheme = .milky
    @State private var rightAppearance: IOSReaderTheme = .midnight
    @State private var leftPage = 1
    @State private var rightPage = 1

    private var leftBook: IOSLibraryBook? { store.books.first { $0.id == leftID } }
    private var rightBook: IOSLibraryBook? { store.books.first { $0.id == rightID } }

    var body: some View {
        GeometryReader { proxy in
            let sideBySide = proxy.size.width > proxy.size.height
            Group {
                if sideBySide {
                    HStack(spacing: 8) { pane(leftBook, title: "Left", page: $leftPage, appearance: $leftAppearance); pane(rightBook, title: "Right", page: $rightPage, appearance: $rightAppearance) }
                } else {
                    ScrollView { VStack(spacing: 14) { pane(leftBook, title: "Top", page: $leftPage, appearance: $leftAppearance).frame(height: proxy.size.height * 0.43); pane(rightBook, title: "Bottom", page: $rightPage, appearance: $rightAppearance).frame(height: proxy.size.height * 0.43) } }
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func pane(_ book: IOSLibraryBook?, title: String, page: Binding<Int>, appearance: Binding<IOSReaderTheme>) -> some View {
        IOSComparePane(label: title, book: book, books: store.books, appearance: appearance) { id in
            if title == "Left" || title == "Top" { leftID = id } else { rightID = id }
        }
    }
}

struct IOSComparePane: View {
    let label: String
    let book: IOSLibraryBook?
    let books: [IOSLibraryBook]
    @Binding var appearance: IOSReaderTheme
    let onSelectBook: (UUID) -> Void
    @StateObject private var controller = IOSReaderController()
    @State private var readingMode: IOSReadingMode = .pageTurn
    @State private var pageText = "1"
    @State private var showingHistory = false
    @State private var showingPageBrowser = false

    private var paperColor: Color { appearance.paperColor }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(label).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Menu {
                    ForEach(books) { item in
                        Button(item.title) { onSelectBook(item.id) }
                    }
                } label: {
                    Text(book?.title ?? "Choose PDF").lineLimit(1)
                }
                Spacer()
                Menu {
                    ForEach(IOSReadingMode.allCases) { mode in
                        Button {
                            readingMode = mode
                        } label: {
                            Label(mode.rawValue, systemImage: mode.icon)
                        }
                    }
                } label: {
                    Image(systemName: readingMode.icon)
                }
                Menu {
                    ForEach(IOSReaderTheme.allCases) { theme in
                        Button {
                            appearance = theme
                        } label: {
                            Label(theme.rawValue, systemImage: theme.icon)
                        }
                    }
                } label: {
                    Image(systemName: appearance.icon)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if let book {
                ZStack {
                    styledPDFView(book: book)
                    if let error = controller.documentError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    IOSReaderToolbar(controller: controller, pageText: $pageText, showingHistory: $showingHistory, showingPageBrowser: $showingPageBrowser)
                }
            } else {
                ContentUnavailableView("Choose a PDF", systemImage: "doc.text")
            }
        }
        .background(paperColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onChange(of: controller.page) { _, page in pageText = "\(page)" }
        .sheet(isPresented: $showingPageBrowser) {
            IOSPageBrowserSheet(controller: controller)
        }
    }

    @ViewBuilder
    private func styledPDFView(book: IOSLibraryBook) -> some View {
        if appearance.isDark {
            ZStack {
                IOSPDFView(url: book.fileURL, controller: controller, paperColor: .white, readingMode: readingMode)
                    .colorInvert()
                Color(paperColor)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .background(paperColor)
        } else {
            ZStack {
                IOSPDFView(url: book.fileURL, controller: controller, paperColor: paperColor, readingMode: readingMode)
                Color(paperColor)
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
                if appearance.isSketchy {
                    IOSPaperTexture()
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                }
            }
            .background(paperColor)
        }
    }
}

struct IOSSettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Import") {
                    Label("Open PDFs from Telegram, Mail, Files, Safari, or any app that offers Share / Open in…", systemImage: "paperclip")
                }
                Section("Reading") {
                    Label("Fit pages automatically", systemImage: "arrow.up.left.and.arrow.down.right")
                    Label("Independent Compare appearances", systemImage: "rectangle.split.2x1")
                    Label("Page history for every reader pane", systemImage: "clock.arrow.circlepath")
                    Label("Study themes: Milky, Sage, Sketchbook, Midnight, Graphite, and Amber", systemImage: "paintpalette")
                }
                Section("About") {
                    NavigationLink {
                        IOSAboutView()
                    } label: {
                    Label("About BookLand", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct IOSAboutView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image("LaunchMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .background(IOSDesign.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("BookLand")
                            .font(.title3.weight(.semibold))
                        Text("A calm research reading space")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Why BookLand") {
                Text("BookLand makes it convenient to read two books at the same time. Open two different PDFs, move through their pages independently, and compare them side by side without leaving the reading workspace.")
                    .font(.subheadline)
                Text("Compared with a standard PDF viewer, BookLand combines a local book library, titles and tags, page history, thumbnails and index navigation, precise search, notes, highlights, study themes, zoom, and independent comparison panes in one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Authorship and design") {
                LabeledContent("Concept and design ideas", value: "Mohammad Ayati")
                LabeledContent("Created", value: "August 2026")
                Text("The original BookLand product concept, research-reading workflow, information architecture, interaction ideas, visual direction, study themes, and comparison-reader design are attributed to Mohammad Ayati.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Logo and visual identity") {
                LabeledContent("Logo designer", value: "Lida Samadi")
                Link("Instagram · @lidasamadi.design", destination: URL(string: "https://www.instagram.com/lidasamadi.design/")!)
                Text("BookLand logo artwork and logo-specific visual-identity design are credited to Lida Samadi. These logo rights are separate from the MIT-licensed source code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Intellectual property notice") {
                Text("© Mohammad Ayati, August 2026. BookLand source code is released under the MIT License. Logo artwork and logo-specific visual identity are credited to Lida Samadi (@lidasamadi.design). The original product concept and product-design record remain attributed to Mohammad Ayati.")
                    .font(.subheadline)
            }

            Section("Third-party and user content") {
                Text("BookLand uses Apple platform technologies such as SwiftUI, PDFKit, and UIKit. Those technologies remain subject to Apple’s rights and licenses. Imported PDFs, annotations, and other user-provided materials remain subject to their respective owners’ rights.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
