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
    case newest = "New added"
    case oldest = "Old added"
    case alphabetical = "A–Z"
    case mostRead = "Most read"
    case leastRead = "Less read"
    case lastOpened = "Last opened"
}

enum AnnotationFilter: String, CaseIterable {
    case all = "All"
    case highlights = "Highlights"
    case notes = "Notes"
    case comments = "Comments"
}

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var selectedBookID: UUID?
    @State private var destination: LibraryDestination = .books
    @State private var showingImporter = false
    @State private var pendingURL: URL?
    @State private var showingTitlePrompt = false
    @State private var showingTools = false
    @State private var showingAbout = false
    @State private var newTitle = ""
    @State private var importError: String?

    private var supportedImportTypes: [UTType] {
        [.pdf, UTType(filenameExtension: "md") ?? .plainText]
    }

    var selectedBook: LibraryBook? { store.books.first { $0.id == selectedBookID } }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(selectedBookID: $selectedBookID, destination: $destination, showingImporter: $showingImporter, showingTools: $showingTools)
                .environmentObject(store)
        } detail: {
            if destination == .annotations {
                AnnotationLibraryView()
                    .environmentObject(store)
            } else if let selectedBook {
                ReaderWorkspace(book: selectedBook)
                    .environmentObject(store)
            } else {
                EmptyLibraryView(showingImporter: $showingImporter)
            }
        }
        .onChange(of: selectedBookID) { id in
            if id != nil { destination = .books }
        }
        .onReceive(NotificationCenter.default.publisher(for: .booklandImportRequested)) { _ in showingImporter = true }
        .onReceive(NotificationCenter.default.publisher(for: .booklandToolsRequested)) { _ in showingTools = true }
        .onReceive(NotificationCenter.default.publisher(for: .booklandAboutRequested)) { _ in showingAbout = true }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: supportedImportTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pendingURL = url
                newTitle = url.deletingPathExtension().lastPathComponent
                showingTitlePrompt = true
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingTitlePrompt) {
            ImportTitleSheet(title: $newTitle, onCancel: { showingTitlePrompt = false }, onImport: importPendingPDF)
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
    }

    private func importPendingPDF() {
        guard let pendingURL else { return }
        do {
            let book = try store.importBook(from: pendingURL, title: newTitle)
            selectedBookID = book.id
            destination = .books
            showingTitlePrompt = false
            self.pendingURL = nil
        } catch {
            importError = error.localizedDescription
            showingTitlePrompt = false
        }
    }
}

struct LibrarySidebar: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var selectedBookID: UUID?
    @Binding var destination: LibraryDestination
    @Binding var showingImporter: Bool
    @Binding var showingTools: Bool
    @State private var searchText = ""
    @State private var sortOption: LibrarySortOption = .newest
    @State private var selectedTag: String?
    @State private var editingBook: LibraryBook?

    private var allTags: [String] {
        Array(Set(store.books.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var visibleBooks: [LibraryBook] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.books.filter { book in
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your library")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { showingImporter = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderedProminent)
                    .help("Import a PDF or Markdown file")
                Button { showingTools = true } label: { Image(systemName: "wrench.and.screwdriver") }
                    .buttonStyle(.bordered)
                    .help("Open BookLand Tools")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            TextField("Search titles and topics", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

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
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Button {
                selectedBookID = nil
                destination = .annotations
            } label: {
                HStack {
                    Image(systemName: "highlighter")
                    Text("Notes & Highlights")
                    Spacer()
                    let count = store.books.reduce(0) { $0 + $1.notes.count }
                    if count > 0 { Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(destination == .annotations ? Color.accentColor.opacity(0.14) : Color.clear)

            Divider()

            if visibleBooks.isEmpty {
                QuietEmptyState(title: store.books.isEmpty ? "No books yet" : "No matching books", systemImage: "books.vertical", description: store.books.isEmpty ? "Import a PDF or Markdown file to start your library." : "Try another title, topic, or sort option.")
            } else {
                List(selection: $selectedBookID) {
                    ForEach(visibleBooks) { book in
                        BookRow(book: book)
                            .tag(book.id as UUID?)
                            .contextMenu {
                                Button("Edit title & topics") { editingBook = book }
                                Button("Reveal Library Folder") {
                                    NSWorkspace.shared.open(store.libraryFolderURL)
                                }
                                Divider()
                                Button("Remove from Library", role: .destructive) {
                                    if selectedBookID == book.id { selectedBookID = nil }
                                    store.removeBook(book)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()
            HStack {
                Image(systemName: "internaldrive")
                Text("\(store.books.count) book\(store.books.count == 1 ? "" : "s") stored locally")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
        }
        .frame(minWidth: 300)
        .sheet(item: $editingBook) { book in
            BookDetailsSheet(book: book)
                .environmentObject(store)
        }
    }
}

struct BookRow: View {
    let book: LibraryBook

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(book.readCount == 0 ? "Not read yet" : "Read activity: \(book.readCount)")
                    if let lastOpenedAt = book.lastOpenedAt {
                        Text("•")
                        Text("Opened \(lastOpenedAt, format: .dateTime.month(.abbreviated).day().hour().minute())")
                    }
                    if let lastReadAt = book.lastReadAt {
                        Text("•")
                        Text("Read \(lastReadAt, format: .dateTime.month(.abbreviated).day().hour().minute())")
                    }
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !book.tags.isEmpty {
                    Text(book.tags.prefix(3).joined(separator: "  ·  "))
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
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

struct AnnotationEntry: Identifiable {
    let book: LibraryBook
    let note: LibraryNote
    var id: UUID { note.id }
}

struct AnnotationLibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var filter: AnnotationFilter = .all
    @State private var searchText = ""

    private var entries: [AnnotationEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.books.flatMap { book in book.notes.map { AnnotationEntry(book: book, note: $0) } }
            .filter { entry in
                let kindMatches: Bool
                switch filter {
                case .all: kindMatches = true
                case .highlights: kindMatches = entry.note.kind == .highlight
                case .notes: kindMatches = entry.note.kind == .note
                case .comments: kindMatches = entry.note.kind == .comment
                }
                return kindMatches && (query.isEmpty || entry.book.title.localizedCaseInsensitiveContains(query) || entry.note.text.localizedCaseInsensitiveContains(query))
            }
            .sorted { $0.note.createdAt > $1.note.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notes & Highlights").font(.title2.weight(.semibold))
            Text("Read your annotations without reopening the original files.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Type", selection: $filter) {
                    ForEach(AnnotationFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(20)
            TextField("Search notes, highlights, and comments", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            Divider()
            if entries.isEmpty {
                QuietEmptyState(title: "No annotations yet", systemImage: "note.text", description: "Highlights, notes, and comments will appear here.")
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(entry.note.kind.label.uppercased()).font(.caption.weight(.bold)).foregroundStyle(entry.note.kind == .highlight ? Color.orange : Color.accentColor)
                            Text(entry.book.title).font(.headline)
                            Spacer()
                            Text("Page \(entry.note.page)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(entry.note.text).font(.body).textSelection(.enabled)
                        Text(entry.note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .listStyle(.inset)
            }
        }
    }
}

struct EmptyLibraryView: View {
    @Binding var showingImporter: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("A calmer way to read")
                .font(.largeTitle.weight(.semibold))
            Text("Keep your PDFs and Markdown files together, annotate them, and compare two PDF pages side by side.")
                .foregroundStyle(.secondary)
            Button("Import your first file") { showingImporter = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
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
