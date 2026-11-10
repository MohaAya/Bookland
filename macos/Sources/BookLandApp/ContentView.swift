// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum LibraryDestination {
    case books
    case annotations
}

enum LibrarySortOption: String, CaseIterable {
    case newest = "Recently added"
    case oldest = "Oldest added"
    case alphabetical = "A–Z"
    case mostRead = "Most read"
    case leastRead = "Least read"
    case lastOpened = "Last opened"
}

enum LibraryGrouping: String, CaseIterable {
    case status = "By reading status"
    case topic = "By topic"
    case none = "One list"
}

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var selectedBookID: UUID?
    @State private var destination: LibraryDestination = .books
    @State private var annotationBookID: UUID?
    @State private var showingImporter = false
    @State private var pendingURL: URL?
    @State private var showingTitlePrompt = false
    @State private var showingLinkSheet = false
    @State private var showingTools = false
    @State private var showingAbout = false
    @State private var newTitle = ""
    @State private var importError: String?
    @State private var toast: String?
    @State private var dropTargeted = false

    private var supportedImportTypes: [UTType] {
        [.pdf, UTType(filenameExtension: "md") ?? .plainText]
    }

    var selectedBook: LibraryBook? { store.books.first { $0.id == selectedBookID } }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(selectedBookID: $selectedBookID, destination: $destination, annotationBookID: $annotationBookID, showingImporter: $showingImporter, showingLinkSheet: $showingLinkSheet, showingTools: $showingTools)
                .environmentObject(store)
                .navigationSplitViewColumnWidth(min: 290, ideal: 330, max: 440)
        } detail: {
            if destination == .annotations {
                AnnotationLibraryView(bookID: $annotationBookID, onOpen: open)
                    .environmentObject(store)
            } else if let selectedBook {
                ReaderWorkspace(book: selectedBook, onShowAllNotes: { showNotes(for: selectedBook.id) })
                    .id(selectedBook.id)
                    .environmentObject(store)
            } else {
                EmptyLibraryView(showingImporter: $showingImporter, showingLinkSheet: $showingLinkSheet)
            }
        }
        .onChange(of: selectedBookID) { id in
            if id != nil { destination = .books }
        }
        .onReceive(NotificationCenter.default.publisher(for: .booklandImportRequested)) { _ in showingImporter = true }
        .onReceive(NotificationCenter.default.publisher(for: .booklandLinkRequested)) { _ in showingLinkSheet = true }
        .onReceive(NotificationCenter.default.publisher(for: .booklandNotesRequested)) { _ in showNotes(for: nil) }
        .onReceive(NotificationCenter.default.publisher(for: .booklandToolsRequested)) { _ in showingTools = true }
        .onReceive(NotificationCenter.default.publisher(for: .booklandAboutRequested)) { _ in showingAbout = true }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: supportedImportTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingTitlePrompt) {
            ImportTitleSheet(title: $newTitle, onCancel: { showingTitlePrompt = false }, onImport: importPendingPDF)
        }
        .sheet(isPresented: $showingLinkSheet) {
            AddFromLinkSheet { book in
                selectedBookID = book.id
                destination = .books
                toast = "Added “\(book.title)”"
            }
            .environmentObject(store)
        }
        .sheet(isPresented: $showingTools) {
            DocumentToolsView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutBookLandView()
        }
        .alert("Could not import file", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Color.accentColor.opacity(0.08))
                    .overlay(Label("Drop PDF or Markdown files to add them", systemImage: "square.and.arrow.down").font(.title3.weight(.semibold)))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .toast($toast)
    }

    private func showNotes(for bookID: UUID?) {
        annotationBookID = bookID
        selectedBookID = nil
        destination = .annotations
    }

    /// Opens a book at the page of a passage.
    private func open(_ book: LibraryBook, _ note: LibraryNote) {
        store.updateLastPage(for: book.id, page: note.page)
        destination = .books
        selectedBookID = book.id
    }

    private func importFiles(_ urls: [URL]) {
        if urls.count == 1, let url = urls.first {
            pendingURL = url
            newTitle = url.deletingPathExtension().lastPathComponent
            showingTitlePrompt = true
            return
        }
        let result = store.importBooks(from: urls)
        if let first = result.added.first {
            selectedBookID = first.id
            destination = .books
            toast = result.added.count == 1 ? "Added “\(first.title)”" : "Added \(result.added.count) books"
        }
        if !result.failures.isEmpty { importError = result.failures.joined(separator: "\n") }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
                else if let url = item as? URL { urls.append(url) }
            }
            let supported = urls.filter { ["pdf", "md", "markdown"].contains($0.pathExtension.lowercased()) }
            await MainActor.run {
                if supported.isEmpty {
                    importError = "BookLand supports PDF and Markdown (.md) files."
                } else {
                    importFiles(supported)
                }
            }
        }
        return true
    }

    private func importPendingPDF() {
        guard let pendingURL else { return }
        do {
            let book = try store.importBook(from: pendingURL, title: newTitle)
            selectedBookID = book.id
            destination = .books
            showingTitlePrompt = false
            self.pendingURL = nil
            toast = "Added “\(book.title)”"
        } catch {
            importError = error.localizedDescription
            showingTitlePrompt = false
        }
    }
}

// MARK: - Covers

@MainActor
final class CoverCache {
    static let shared = CoverCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL) async -> NSImage? {
        let key = url.lastPathComponent as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image: NSImage? = await Task.detached(priority: .utility) {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 120, height: 160), for: .cropBox)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

struct CoverView: View {
    @EnvironmentObject private var store: LibraryStore
    let book: LibraryBook
    var width: CGFloat = 38
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: book.isMarkdown ? "text.document" : "doc.richtext")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: width, height: width * 1.33)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .task(id: book.fileName) {
            guard !book.isMarkdown else { return }
            image = await CoverCache.shared.image(for: store.pdfURL(for: book))
        }
    }
}

// MARK: - Sidebar

struct LibrarySidebar: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var selectedBookID: UUID?
    @Binding var destination: LibraryDestination
    @Binding var annotationBookID: UUID?
    @Binding var showingImporter: Bool
    @Binding var showingLinkSheet: Bool
    @Binding var showingTools: Bool
    @State private var searchText = ""
    @AppStorage("bookland.sortOption") private var sortOption: LibrarySortOption = .newest
    @AppStorage("bookland.grouping") private var grouping: LibraryGrouping = .status
    @State private var showArchived = false
    @State private var selectedTag: String?
    @State private var editingBook: LibraryBook?
    @State private var removingBook: LibraryBook?

    private var allTags: [String] {
        Array(Set(store.books.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var visibleBooks: [LibraryBook] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.books.filter { book in
            guard book.isArchived == showArchived else { return false }
            let matchesSearch = query.isEmpty || book.title.localizedCaseInsensitiveContains(query) || book.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            let matchesTag = selectedTag == nil || book.tags.contains(selectedTag!)
            return matchesSearch && matchesTag
        }
        switch sortOption {
        case .newest: return filtered.sorted { $0.dateAdded > $1.dateAdded }
        case .oldest: return filtered.sorted { $0.dateAdded < $1.dateAdded }
        case .alphabetical: return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .mostRead: return filtered.sorted { $0.readCount > $1.readCount }
        case .leastRead: return filtered.sorted { $0.readCount < $1.readCount }
        case .lastOpened: return filtered.sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        }
    }

    private var continueBook: LibraryBook? {
        guard searchText.isEmpty, selectedTag == nil, !showArchived, grouping != .none else { return nil }
        return store.books.filter { $0.lastOpenedAt != nil && !$0.isMarkdown && !$0.isArchived }.max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    private var archivedCount: Int { store.books.filter(\.isArchived).count }

    /// The visible books split into titled groups, so the library is not one long list.
    private var sections: [(title: String, books: [LibraryBook])] {
        let books = visibleBooks
        switch grouping {
        case .none:
            return [(continueBook == nil ? "" : "All books", books)]
        case .status:
            let order: [LibraryBook.ReadingStatus] = [.reading, .notStarted, .finished]
            return order.compactMap { status in
                let group = books.filter { $0.status == status }
                return group.isEmpty ? nil : (status.rawValue, group)
            }
        case .topic:
            var result: [(String, [LibraryBook])] = []
            for tag in allTags {
                let group = books.filter { $0.tags.contains(tag) }
                if !group.isEmpty { result.append((tag, group)) }
            }
            let untagged = books.filter { $0.tags.isEmpty }
            if !untagged.isEmpty { result.append(("No topic", untagged)) }
            return result
        }
    }

    private func requestRemoval(of id: UUID?) {
        guard let id, let book = store.books.first(where: { $0.id == id }) else { return }
        removingBook = book
    }

    @ViewBuilder
    private func row(for book: LibraryBook) -> some View {
        BookRow(book: book)
            .tag(book.id as UUID?)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { removingBook = book } label: { Label("Remove", systemImage: "trash") }
                Button { archive(book) } label: { Label(book.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") }
                    .tint(.orange)
            }
            .contextMenu {
                if !book.notes.isEmpty {
                    Button("Show Highlights & Notes") {
                        selectedBookID = nil
                        annotationBookID = book.id
                        destination = .annotations
                    }
                    Button("Copy Highlights & Notes") { Clipboard.copy(book.notesMarkdown()) }
                }
                Button("Edit Title & Topics") { editingBook = book }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.pdfURL(for: book)])
                }
                Divider()
                Button(book.isArchived ? "Move Back to Library" : "Archive") { archive(book) }
                Button("Remove from Library…", role: .destructive) { removingBook = book }
            }
    }

    private func archive(_ book: LibraryBook) {
        if selectedBookID == book.id, !book.isArchived { selectedBookID = nil }
        store.setArchived(book.id, !book.isArchived)
    }

    private var noteTotal: Int { store.books.reduce(0) { $0 + $1.notes.count } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Library")
                    .font(.title2.weight(.semibold))
                Spacer()
                Menu {
                    Button { showingImporter = true } label: { Label("Import Files…", systemImage: "folder") }
                    Button { showingLinkSheet = true } label: { Label("Add from a Link…", systemImage: "link") }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(6)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
                .help("Add a PDF or Markdown file, or download one from a link")
                Button { showingTools = true } label: { Image(systemName: "wrench.and.screwdriver") }
                    .buttonStyle(.borderless)
                    .help("Open BookLand Tools")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search titles and topics", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                Menu {
                    ForEach(LibrarySortOption.allCases, id: \.self) { option in
                        Button { sortOption = option } label: {
                            HStack {
                                Text(option.rawValue)
                                if option == sortOption { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: { Label(sortOption.rawValue, systemImage: "arrow.up.arrow.down") }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    Button("All topics") { selectedTag = nil }
                    if !allTags.isEmpty { Divider() }
                    ForEach(allTags, id: \.self) { tag in
                        Button { selectedTag = tag } label: {
                            HStack {
                                Text(tag)
                                if selectedTag == tag { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: { Label(selectedTag ?? "Topics", systemImage: "tag") }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    ForEach(LibraryGrouping.allCases, id: \.self) { option in
                        Button { grouping = option } label: {
                            HStack {
                                Text(option.rawValue)
                                if option == grouping { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Divider()
                    Button { showArchived.toggle() } label: {
                        HStack {
                            Text(showArchived ? "Back to my library" : "Show archived (\(archivedCount))")
                            Image(systemName: showArchived ? "books.vertical" : "archivebox")
                        }
                    }
                } label: { Label(showArchived ? "Archived" : "Group", systemImage: showArchived ? "archivebox" : "rectangle.3.group") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Button {
                selectedBookID = nil
                annotationBookID = nil
                destination = .annotations
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "highlighter")
                        .frame(width: 20)
                        .foregroundStyle(Color.accentColor)
                    Text("Notes & Highlights")
                    Spacer()
                    if noteTotal > 0 { Text("\(noteTotal)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(destination == .annotations ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            Divider()

            if visibleBooks.isEmpty {
                QuietEmptyState(
                    title: showArchived ? "Nothing archived" : (store.books.isEmpty ? "No books yet" : "No matching books"),
                    systemImage: showArchived ? "archivebox" : "books.vertical",
                    description: showArchived ? "Archive books you are done with to keep your library short. Their notes stay safe."
                        : (store.books.isEmpty ? "Import a PDF or Markdown file, or drop files here." : "Try another title, topic, or sort option.")
                )
            } else {
                List(selection: $selectedBookID) {
                    if let continueBook {
                        Section("Continue reading") {
                            row(for: continueBook)
                        }
                    }
                    ForEach(sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.books) { book in row(for: book) }
                        }
                    }
                }
                .listStyle(.sidebar)
                .onDeleteCommand { requestRemoval(of: selectedBookID) }
            }

            Divider()
            HStack {
                Image(systemName: "internaldrive")
                Text("\(store.books.count) book\(store.books.count == 1 ? "" : "s") stored on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
        }
        .sheet(item: $editingBook) { book in
            BookDetailsSheet(book: book)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Remove “\(removingBook?.title ?? "")” from your library?",
            isPresented: Binding(get: { removingBook != nil }, set: { if !$0 { removingBook = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove and delete its notes", role: .destructive) {
                if let book = removingBook {
                    if selectedBookID == book.id { selectedBookID = nil }
                    store.removeBook(book)
                }
                removingBook = nil
            }
            Button("Cancel", role: .cancel) { removingBook = nil }
        } message: {
            Text("The copy inside BookLand and its highlights and notes are deleted. Your original file is not touched.")
        }
    }
}

struct BookRow: View {
    let book: LibraryBook
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            CoverView(book: book, width: compact ? 34 : 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                if let progress = book.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .frame(maxWidth: 150)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !compact, !book.tags.isEmpty {
                    Text(book.tags.prefix(3).joined(separator: "  ·  "))
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        var parts: [String] = []
        if book.isMarkdown { parts.append("Markdown") }
        else if book.readCount == 0 && book.lastPage <= 1 { parts.append("Not started") }
        else if let text = book.progressText { parts.append(text) }
        if let summary = book.notesSummary { parts.append(summary) }
        return parts.joined(separator: " · ")
    }
}

struct BookDetailsSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let book: LibraryBook
    @State private var title: String
    @State private var tagsText: String

    init(book: LibraryBook) {
        self.book = book
        _title = State(initialValue: book.title)
        _tagsText = State(initialValue: book.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit book details").font(.title2.weight(.semibold))
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            Text("Topics / tags").font(.headline)
            TextField("For example: management, theory, Finland", text: $tagsText).textFieldStyle(.roundedBorder)
            Text("Separate topics with commas. These topics can be searched and filtered.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    store.updateBook(book.id, title: title, tags: tagsText.split(separator: ",").map(String.init))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

struct AddFromLinkSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let onAdded: (LibraryBook) -> Void
    @State private var link = ""
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a book from a link").font(.title2.weight(.semibold))
            Text("Paste the web address of a PDF. BookLand downloads it and puts it in your library. Dropbox and Google Drive share links work too.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("https://…", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .disabled(working)
                    .onSubmit(download)
                Button("Paste") {
                    if let text = NSPasteboard.general.string(forType: .string) { link = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                .disabled(working)
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if working {
                    ProgressView().controlSize(.small)
                    Text("Downloading…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Download", action: download)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            // Offer a link that is already on the clipboard.
            if link.isEmpty, let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               text.lowercased().hasPrefix("http"), !text.contains(" "), !text.contains("\n") {
                link = text
            }
        }
    }

    private func download() {
        guard !working else { return }
        working = true
        errorText = nil
        Task {
            let result = await store.addBook(fromLink: link)
            working = false
            if let book = result.book {
                dismiss()
                onAdded(book)
            } else if let message = result.error, !message.isEmpty {
                errorText = message
            }
        }
    }
}

struct EmptyLibraryView: View {
    @Binding var showingImporter: Bool
    @Binding var showingLinkSheet: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("A calmer way to read")
                .font(.largeTitle.weight(.semibold))
            Text("Keep your PDFs and Markdown files together, highlight and annotate them, copy or share what you marked, and compare two PDFs side by side.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack {
                Button { showingImporter = true } label: { Label("Import files…", systemImage: "folder") }
                    .buttonStyle(.borderedProminent)
                Button { showingLinkSheet = true } label: { Label("Add from a link…", systemImage: "link") }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
            Text("You can also drag PDFs onto this window.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ImportTitleSheet: View {
    @Binding var title: String
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Name this file")
                .font(.title2.weight(.semibold))
            Text("This is the title that will appear in your library.")
                .foregroundStyle(.secondary)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onImport)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Add to Library", action: onImport)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct QuietEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
