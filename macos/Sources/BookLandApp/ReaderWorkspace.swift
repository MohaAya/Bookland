// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import AppKit
import SwiftUI

enum ReaderMode: String, CaseIterable {
    case read = "Read"
    case compare = "Compare"
}

enum ReadingAppearance: String, CaseIterable, Identifiable {
    case system
    case dark
    case milky
    case sepia
    case blue
    case sketchy

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .system: return nil
        default: return .light
        }
    }
}

enum HighlightColor: String, CaseIterable, Identifiable {
    case yellow
    case green
    case pink
    case blue

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .yellow: return .yellow
        case .green: return .green
        case .pink: return .pink
        case .blue: return .blue
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .pink: return .systemPink
        case .blue: return .systemBlue
        }
    }
}

struct ReaderWorkspace: View {
    @EnvironmentObject private var store: LibraryStore
    let book: LibraryBook
    @State private var mode: ReaderMode = .read
    @State private var showingDetails = false
    @AppStorage("quietLibraryMainAppearance") private var mainAppearanceRaw = ReadingAppearance.system.rawValue

    private var appearance: ReadingAppearance {
        let rawValue = mode == .read ? mainAppearanceRaw : ReadingAppearance.system.rawValue
        return ReadingAppearance(rawValue: rawValue) ?? .system
    }

    private var appearanceTitle: String {
        "\(mode == .read ? "Main" : "Compare") · \(appearance.label)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title).font(.title2.weight(.semibold))
                    Text(book.sourcePath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    showingDetails = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                if mode == .read {
                    Menu {
                        ForEach(ReadingAppearance.allCases) { style in
                            Button {
                                mainAppearanceRaw = style.rawValue
                            } label: {
                                HStack {
                                    Text(style.label)
                                    if style == appearance { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        Label(appearanceTitle, systemImage: "paintpalette")
                    }
                    .menuStyle(.borderlessButton)
                }
                Picker("View", selection: $mode) {
                    ForEach(ReaderMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(book.isMarkdown)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()
            if mode == .read {
                if book.isMarkdown {
                    MarkdownReader(book: book)
                } else {
                    SingleReader(book: book, appearance: appearance)
                }
            } else {
                CompareReader(primaryBook: book, onClose: { mode = .read })
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(appearance.colorScheme)
        .sheet(isPresented: $showingDetails) {
            BookDetailsSheet(book: book)
                .environmentObject(store)
        }
    }
}

struct MarkdownReader: View {
    @EnvironmentObject private var store: LibraryStore
    let book: LibraryBook
    @State private var showingNote = false
    @State private var noteText = ""
    @State private var noteKind: LibraryNoteKind = .note

    private var markdownText: String {
        (try? String(contentsOf: store.pdfURL(for: book), encoding: .utf8)) ?? "Unable to read this Markdown file."
    }

    private var renderedMarkdown: AttributedString {
        (try? AttributedString(markdown: markdownText, options: .init(interpretedSyntax: .full))) ?? AttributedString(markdownText)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Label("Markdown document", systemImage: "text.document")
                        .font(.headline)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(store.pdfURL(for: book))
                    } label: {
                        Label("Open in editor", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        noteKind = .note
                        noteText = ""
                        showingNote = true
                    } label: {
                        Label("Add note", systemImage: "note.text.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                Divider()
                ScrollView {
                    Text(renderedMarkdown)
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 52)
                        .padding(.vertical, 38)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
            Divider()
            NotesPanel(book: book, onAdd: {
                noteKind = .note
                noteText = ""
                showingNote = true
            })
            .frame(width: 300)
        }
        .sheet(isPresented: $showingNote) {
            NoteEditor(kind: $noteKind, text: $noteText, page: 1, onCancel: { showingNote = false }, onSave: saveNote)
        }
        .onAppear {
            store.markOpened(book.id)
            store.markRead(book.id)
        }
    }

    private func saveNote() {
        let cleanText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        store.addNote(LibraryNote(page: 1, text: cleanText, kind: noteKind), to: book.id)
        noteText = ""
        showingNote = false
    }
}

struct SingleReader: View {
    @EnvironmentObject private var store: LibraryStore
    let book: LibraryBook
    let appearance: ReadingAppearance
    @StateObject private var controller = PDFReaderController()
    @StateObject private var searchController = PDFSearchController()
    @State private var showingNote = false
    @State private var noteText = ""
    @State private var noteKind: LibraryNoteKind = .note
    @State private var showPageSidebar = true
    @State private var lastHighlightNote: LibraryNote?

    var body: some View {
        HStack(spacing: 0) {
            ReaderPanel(book: book, appearance: appearance, controller: controller, searchController: searchController, showPageSidebar: $showPageSidebar, onHighlight: highlight, onUndoHighlight: undoHighlight, onRemoveHighlight: removeHighlight, onComment: { noteKind = .comment; noteText = controller.selectedText; showingNote = true })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            NotesPanel(book: book, onAdd: { noteKind = .note; noteText = ""; showingNote = true })
                .frame(width: 300)
        }
        .sheet(isPresented: $showingNote) {
            NoteEditor(kind: $noteKind, text: $noteText, page: controller.currentPage, onCancel: { showingNote = false }, onSave: saveNote)
        }
        .onAppear {
            store.markOpened(book.id)
            controller.goToPage(book.lastPage)
        }
        .onChange(of: controller.currentPage) { page in
            store.updateLastPage(for: book.id, page: page)
            store.markRead(book.id)
        }
    }

    private func highlight(color: NSColor) -> Bool {
        guard controller.highlightSelection(color: color) else { return false }
        let text = controller.selectedText
        let note = LibraryNote(page: controller.currentPage, text: text.isEmpty ? "Highlighted passage" : text, kind: .highlight)
        store.addNote(note, to: book.id)
        lastHighlightNote = note
        controller.selection = nil
        return true
    }

    private func undoHighlight() -> Bool {
        guard controller.undoLastHighlight() else { return false }
        if let lastHighlightNote {
            store.deleteNote(lastHighlightNote, from: book.id)
            self.lastHighlightNote = nil
        }
        return true
    }

    private func removeHighlight() -> Bool {
        let text = controller.selectedText
        guard controller.removeHighlightAtSelection() else { return false }
        store.deleteHighlight(page: controller.currentPage, text: text, from: book.id)
        lastHighlightNote = nil
        return true
    }

    private func saveNote() {
        let cleanText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        if noteKind == .comment { _ = controller.addComment(cleanText) }
        store.addNote(LibraryNote(page: controller.currentPage, text: cleanText, kind: noteKind), to: book.id)
        noteText = ""
        showingNote = false
    }
}

struct ReaderPanel: View {
    @EnvironmentObject private var store: LibraryStore
    let book: LibraryBook
    let appearance: ReadingAppearance
    @ObservedObject var controller: PDFReaderController
    @ObservedObject var searchController: PDFSearchController
    @Binding var showPageSidebar: Bool
    let onHighlight: (NSColor) -> Bool
    let onUndoHighlight: () -> Bool
    let onRemoveHighlight: () -> Bool
    let onComment: () -> Void
    @State private var selectedHighlightColor: HighlightColor = .yellow
    @State private var showingSelectionHint = false

    var body: some View {
        VStack(spacing: 0) {
            PDFSearchBar(controller: searchController)
            Divider()
            HStack(spacing: 8) {
                Button(action: controller.previousPage) { Image(systemName: "chevron.left") }
                    .disabled(controller.currentPage <= 1)
                Button(action: controller.nextPage) { Image(systemName: "chevron.right") }
                    .disabled(controller.currentPage >= controller.pageCount)
                PageJumpControl(controller: controller)
                PageHistoryControl(controller: controller)
                Spacer()
                Button {
                    showPageSidebar.toggle()
                } label: {
                    Image(systemName: showPageSidebar ? "sidebar.left" : "sidebar.left")
                }
                .help(showPageSidebar ? "Hide page thumbnails" : "Show page thumbnails")
                ZoomControls(controller: controller)
                Label("Highlight", systemImage: "highlighter")
                    .font(.callout.weight(.medium))
                ForEach(HighlightColor.allCases) { color in
                    Button {
                        selectedHighlightColor = color
                        if !onHighlight(color.nsColor) { showingSelectionHint = true }
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 17, height: 17)
                            .overlay(Circle().stroke(selectedHighlightColor == color ? Color.primary : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help("Highlight selected text \(color.label.lowercased())")
                }
                Button { _ = onUndoHighlight() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!controller.canUndoHighlight)
                .help("Undo last highlight")
                Button { _ = onRemoveHighlight() } label: {
                    Image(systemName: "eraser")
                }
                .disabled(!controller.canRemoveHighlightAtSelection)
                .help("Remove highlight from selected text")
                Button("Comment", action: onComment)
                    .disabled(controller.selectedText.isEmpty)
            }
            .buttonStyle(.bordered)
            .padding(12)
            if showingSelectionHint {
                Text("Select text in the PDF first, then choose a highlight color.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()
            PDFKitView(url: store.pdfURL(for: book), controller: controller, searchController: searchController, appearance: appearance, showPageSidebar: showPageSidebar, onHighlight: onHighlight, onUndoHighlight: onUndoHighlight, onRemoveHighlight: onRemoveHighlight)
        }
    }
}

struct PageJumpControl: View {
    @ObservedObject var controller: PDFReaderController
    @State private var pageText = "1"

    var body: some View {
        HStack(spacing: 4) {
            TextField("Page", text: $pageText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .multilineTextAlignment(.center)
                .onSubmit { jump() }
            Text("/ \(controller.pageCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .onAppear { pageText = "\(controller.currentPage)" }
        .onChange(of: controller.currentPage) { pageText = "\($0)" }
    }

    private func jump() {
        guard let page = Int(pageText) else {
            pageText = "\(controller.currentPage)"
            return
        }
        controller.goToPage(page)
    }
}

struct PageHistoryControl: View {
    @ObservedObject var controller: PDFReaderController

    private var historyLabel: String {
        let visiblePages = controller.pageHistory.suffix(5).map(String.init)
        let prefix = controller.pageHistory.count > visiblePages.count ? "… → " : ""
        return prefix + visiblePages.joined(separator: " → ")
    }

    var body: some View {
        HStack(spacing: 3) {
            Button(action: controller.goBackInHistory) {
                Image(systemName: "arrow.left")
            }
            .disabled(controller.previousLocationPage == nil)
            .help(controller.previousLocationPage.map { "Return to page \($0)" } ?? "No previous page")

            Button(action: controller.goForwardInHistory) {
                Image(systemName: "arrow.right")
            }
            .disabled(controller.nextLocationPage == nil)
            .help(controller.nextLocationPage.map { "Go forward to page \($0)" } ?? "No next page")

            Menu {
                Section("Page history") {
                    ForEach(Array(controller.pageHistory.enumerated()), id: \.offset) { entry in
                        Button {
                            controller.goToHistoryEntry(at: entry.offset)
                        } label: {
                            HStack {
                                Text("Page \(entry.element)")
                                if entry.offset == controller.historyIndex {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Label(historyLabel, systemImage: "clock.arrow.circlepath")
                    .lineLimit(1)
                    .frame(maxWidth: 150)
            }
            .menuStyle(.borderlessButton)
            .help("Page history: \(controller.pageHistory.map(String.init).joined(separator: " → "))")
        }
        .buttonStyle(.bordered)
    }
}

struct PDFSearchBar: View {
    @ObservedObject var controller: PDFSearchController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in this PDF", text: $controller.query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { controller.search() }
            Button("Find", action: controller.search)
                .buttonStyle(.borderedProminent)
            if !controller.resultSummary.isEmpty {
                Text(controller.resultSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72)
                Button(action: controller.previousMatch) { Image(systemName: "chevron.up") }
                    .disabled(controller.matches.isEmpty)
                    .help("Previous match")
                Button(action: controller.nextMatch) { Image(systemName: "chevron.down") }
                    .disabled(controller.matches.isEmpty)
                    .help("Next match")
            }
            if !controller.query.isEmpty {
                Button {
                    controller.query = ""
                    controller.search()
                } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct ZoomControls: View {
    @ObservedObject var controller: PDFReaderController

    var body: some View {
        HStack(spacing: 4) {
            Button(action: controller.zoomOut) { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out")
            Text("\(controller.zoomPercent)%")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 42)
            Button(action: controller.zoomIn) { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in")
            Button("Fit") { controller.resetZoom() }
                .font(.caption)
                .help("Fit page to window")
            if controller.zoomPercent > 100 {
                Button {
                    controller.isPanMode.toggle()
                } label: {
                    Image(systemName: controller.isPanMode ? "hand.raised.fill" : "hand.raised")
                }
                .help(controller.isPanMode ? "Stop grabbing the page" : "Grab and move the zoomed page")
            }
        }
        .buttonStyle(.bordered)
    }
}

struct NotesPanel: View {
    @EnvironmentObject private var store: LibraryStore
    let book: LibraryBook
    let onAdd: () -> Void

    var currentBook: LibraryBook { store.books.first(where: { $0.id == book.id }) ?? book }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notes & marks").font(.headline)
                Spacer()
                Button(action: onAdd) { Image(systemName: "plus") }
            }
            .padding(14)
            Divider()
            if currentBook.notes.isEmpty {
                QuietEmptyState(title: "Nothing here yet", systemImage: "note.text", description: "Select text to highlight or comment, or add a note.")
            } else {
                List {
                    ForEach(currentBook.notes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(note.kind.label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(note.kind == .highlight ? Color.orange : Color.accentColor)
                                Spacer()
                                Text("p. \(note.page)").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(note.text).font(.callout).lineLimit(8)
                        }
                        .padding(.vertical, 5)
                        .contextMenu {
                            Button("Delete", role: .destructive) { store.deleteNote(note, from: book.id) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct CompareReader: View {
    @EnvironmentObject private var store: LibraryStore
    let primaryBook: LibraryBook
    @AppStorage("quietLibraryCompareLeftAppearance") private var leftAppearanceRaw = ReadingAppearance.milky.rawValue
    @AppStorage("quietLibraryCompareRightAppearance") private var rightAppearanceRaw = ReadingAppearance.dark.rawValue
    @State private var leftID: UUID?
    @State private var rightID: UUID?
    @State private var importSide: ComparisonSide = .right
    @State private var showingImporter = false
    @State private var pendingURL: URL?
    @State private var showingTitlePrompt = false
    @State private var importTitle = ""
    @State private var importError: String?
    @StateObject private var leftController = PDFReaderController()
    @StateObject private var rightController = PDFReaderController()
    @State private var leftSidebarVisible = true
    @State private var rightSidebarVisible = true
    @State private var splitFraction: CGFloat = 0.5
    @State private var splitDragStart: CGFloat?
    let onClose: () -> Void

    private var leftAppearance: ReadingAppearance { ReadingAppearance(rawValue: leftAppearanceRaw) ?? .milky }
    private var rightAppearance: ReadingAppearance { ReadingAppearance(rawValue: rightAppearanceRaw) ?? .dark }

    init(primaryBook: LibraryBook, onClose: @escaping () -> Void = {}) {
        self.primaryBook = primaryBook
        self.onClose = onClose
        _leftID = State(initialValue: primaryBook.id)
        _rightID = State(initialValue: primaryBook.id)
    }

    var leftBook: LibraryBook? { store.books.first { $0.id == leftID } }
    var rightBook: LibraryBook? { store.books.first { $0.id == rightID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Compare workspace").font(.headline)
                Spacer()
                Button("Close Compare", action: onClose)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    if leftBook != nil {
                        ComparisonPane(label: "Left page", bookID: $leftID, book: leftBook, books: store.books, controller: leftController, appearance: leftAppearance, showPageSidebar: $leftSidebarVisible, onAppearanceChange: { leftAppearanceRaw = $0.rawValue }, onOpenFile: { openFile(for: .left) })
                            .frame(width: rightBook == nil ? proxy.size.width : proxy.size.width * splitFraction)
                    }
                    if leftBook != nil && rightBook != nil {
                        Rectangle()
                            .fill(Color.primary.opacity(0.14))
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if splitDragStart == nil { splitDragStart = splitFraction }
                                        let start = splitDragStart ?? splitFraction
                                        splitFraction = min(max(start + value.translation.width / max(proxy.size.width, 1), 0.2), 0.8)
                                    }
                                    .onEnded { _ in splitDragStart = nil }
                            )
                            .help("Drag to resize comparison panes")
                    }
                    if rightBook != nil {
                        ComparisonPane(label: "Right page", bookID: $rightID, book: rightBook, books: store.books, controller: rightController, appearance: rightAppearance, showPageSidebar: $rightSidebarVisible, onAppearanceChange: { rightAppearanceRaw = $0.rawValue }, onOpenFile: { openFile(for: .right) })
                            .frame(width: leftBook == nil ? proxy.size.width : proxy.size.width * (1 - splitFraction))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pendingURL = url
                importTitle = url.deletingPathExtension().lastPathComponent
                showingTitlePrompt = true
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingTitlePrompt) {
            ImportTitleSheet(title: $importTitle, onCancel: { showingTitlePrompt = false }, onImport: importComparisonFile)
        }
        .alert("Could not import PDF", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
    }

    private func openFile(for side: ComparisonSide) {
        importSide = side
        showingImporter = true
    }

    private func importComparisonFile() {
        guard let pendingURL else { return }
        do {
            let book = try store.importBook(from: pendingURL, title: importTitle)
            if importSide == .left { leftID = book.id } else { rightID = book.id }
            self.pendingURL = nil
            showingTitlePrompt = false
        } catch {
            importError = error.localizedDescription
            showingTitlePrompt = false
        }
    }
}

enum ComparisonSide {
    case left
    case right
}

struct ComparisonPane: View {
    @EnvironmentObject private var store: LibraryStore
    let label: String
    @Binding var bookID: UUID?
    let book: LibraryBook?
    let books: [LibraryBook]
    @ObservedObject var controller: PDFReaderController
    let appearance: ReadingAppearance
    @Binding var showPageSidebar: Bool
    let onAppearanceChange: (ReadingAppearance) -> Void
    let onOpenFile: () -> Void
    @StateObject private var searchController = PDFSearchController()
    @State private var selectedHighlightColor: HighlightColor = .yellow
    @State private var showingSelectionHint = false
    @State private var lastHighlightNote: LibraryNote?

    var body: some View {
        VStack(spacing: 0) {
            PDFSearchBar(controller: searchController)
            Divider()
            HStack(spacing: 8) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Menu {
                    ForEach(ReadingAppearance.allCases) { style in
                        Button {
                            onAppearanceChange(style)
                        } label: {
                            HStack {
                                Text(style.label)
                                if style == appearance { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label(appearance.label, systemImage: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                Menu {
                    ForEach(books) { item in
                        Button {
                            bookID = item.id
                        } label: {
                            HStack {
                                Text(item.title)
                                if item.id == bookID { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Divider()
                    Button("Open another PDF…", action: onOpenFile)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                        Text(book?.title ?? "Choose a PDF")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 240, alignment: .leading)
                Spacer()
                ZoomControls(controller: controller)
                Button(action: controller.previousPage) { Image(systemName: "chevron.left") }.disabled(controller.currentPage <= 1)
                PageJumpControl(controller: controller)
                PageHistoryControl(controller: controller)
                Button(action: controller.nextPage) { Image(systemName: "chevron.right") }.disabled(controller.currentPage >= controller.pageCount)
                Button {
                    showPageSidebar.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(showPageSidebar ? "Hide page thumbnails" : "Show page thumbnails")
                Label("Highlight", systemImage: "highlighter")
                    .font(.callout.weight(.medium))
                ForEach(HighlightColor.allCases) { color in
                    Button {
                        selectedHighlightColor = color
                        if !highlight(color: color.nsColor) { showingSelectionHint = true }
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 17, height: 17)
                            .overlay(Circle().stroke(selectedHighlightColor == color ? Color.primary : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help("Highlight selected text \(color.label.lowercased())")
                }
                Button { _ = undoHighlight() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!controller.canUndoHighlight)
                .help("Undo last highlight")
                Button { _ = removeHighlight() } label: {
                    Image(systemName: "eraser")
                }
                .disabled(!controller.canRemoveHighlightAtSelection)
                .help("Remove highlight from selected text")
            }
            .padding(10)
            if showingSelectionHint {
                Text("Select text in this PDF first, then choose a highlight color.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()
            if let book {
                PDFKitView(url: store.pdfURL(for: book), controller: controller, searchController: searchController, appearance: appearance, showPageSidebar: showPageSidebar, onHighlight: highlight, onUndoHighlight: undoHighlight, onRemoveHighlight: removeHighlight)
            } else {
                QuietEmptyState(title: "Choose a PDF", systemImage: "doc.text.magnifyingglass", description: "Select a document for this comparison pane.")
            }
        }
    }

    private func highlight(color: NSColor) -> Bool {
        guard let book, controller.highlightSelection(color: color) else { return false }
        let text = controller.selectedText
        let note = LibraryNote(page: controller.currentPage, text: text.isEmpty ? "Highlighted passage" : text, kind: .highlight)
        store.addNote(note, to: book.id)
        lastHighlightNote = note
        controller.selection = nil
        return true
    }

    private func undoHighlight() -> Bool {
        guard let book, controller.undoLastHighlight() else { return false }
        if let lastHighlightNote {
            store.deleteNote(lastHighlightNote, from: book.id)
            self.lastHighlightNote = nil
        }
        return true
    }

    private func removeHighlight() -> Bool {
        guard let book else { return false }
        let text = controller.selectedText
        guard controller.removeHighlightAtSelection() else { return false }
        store.deleteHighlight(page: controller.currentPage, text: text, from: book.id)
        lastHighlightNote = nil
        return true
    }
}

struct NoteEditor: View {
    @Binding var kind: LibraryNoteKind
    @Binding var text: String
    let page: Int
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .comment ? "Comment on page \(page)" : "Add a note")
                .font(.title2.weight(.semibold))
            if kind == .note {
                Picker("Type", selection: $kind) {
                    Text("Note").tag(LibraryNoteKind.note)
                    Text("Comment").tag(LibraryNoteKind.comment)
                }
                .pickerStyle(.segmented)
            }
            TextEditor(text: $text)
                .font(.body)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .frame(minHeight: 130)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}
