// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Small helpers

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// A short confirmation that fades away on its own ("Copied", "Added 3 books").
private struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: message) {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            withAnimation { self.message = nil }
                        }
                }
            }
            .animation(.easeOut(duration: 0.2), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

extension LibraryNote {
    var highlightColor: HighlightColor? {
        guard let colorName else { return nil }
        return HighlightColor(rawValue: colorName)
    }

    /// Colour of the little bar beside a passage.
    var accent: Color {
        switch kind {
        case .highlight: return highlightColor?.color ?? .orange
        case .comment: return .purple
        case .note: return .accentColor
        }
    }
}

extension HighlightColor {
    static func named(for color: NSColor) -> HighlightColor? {
        allCases.first { $0.nsColor == color }
    }
}

// MARK: - One passage

/// A highlight, note or comment with Copy and Share next to it.
struct NoteCard: View {
    let book: LibraryBook
    let note: LibraryNote
    var showsBookTitle = false
    var onJump: (() -> Void)?
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var citation: String { book.citation(for: note) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(note.accent)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(note.kind.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(note.accent)
                    if showsBookTitle {
                        Text(book.title).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button { onJump?() } label: {
                        Text("p. \(note.page)")
                            .font(.caption.monospacedDigit())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(onJump == nil ? Color.secondary : Color.accentColor)
                    .disabled(onJump == nil)
                    .help("Go to page \(note.page)")
                }
                Text(note.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
                        .help("Copy this passage with its page and book")
                    ShareLink(item: citation) { Label("Share", systemImage: "square.and.arrow.up") }
                        .help("Share this passage")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Copy Passage", action: onCopy)
            Button("Copy Text Only") { Clipboard.copy(note.text) }
            if let onJump { Button("Go to Page \(note.page)", action: onJump) }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Side panel next to the reader

struct NotesPanel: View {
    @EnvironmentObject private var store: LibraryStore
    let book: LibraryBook
    let onAdd: () -> Void
    var onJump: ((Int) -> Void)?
    var onShowAll: (() -> Void)?
    @State private var toast: String?

    var currentBook: LibraryBook { store.books.first(where: { $0.id == book.id }) ?? book }

    private var sortedNotes: [LibraryNote] {
        currentBook.notes.sorted { ($0.page, $1.createdAt) < ($1.page, $0.createdAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Notes & marks").font(.headline)
                    if let summary = currentBook.notesSummary {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !currentBook.notes.isEmpty {
                    Button {
                        Clipboard.copy(currentBook.notesMarkdown())
                        toast = "Copied all as Markdown"
                    } label: { Image(systemName: "doc.on.doc") }
                        .help("Copy every highlight and note of this book")
                    ShareLink(item: currentBook.notesMarkdown()) { Image(systemName: "square.and.arrow.up") }
                        .help("Share every highlight and note of this book")
                    if let onShowAll {
                        Button(action: onShowAll) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                            .help("Open the full Notes & Highlights page for this book")
                    }
                }
                Button(action: onAdd) { Image(systemName: "plus") }
                    .help("Add a note")
            }
            .buttonStyle(.borderless)
            .padding(14)
            Divider()
            if currentBook.notes.isEmpty {
                QuietEmptyState(title: "Nothing here yet", systemImage: "highlighter", description: "Select text in the PDF and pick a colour to highlight it, or add a note with +.")
            } else {
                List {
                    ForEach(sortedNotes) { note in
                        NoteCard(book: currentBook, note: note,
                                 onJump: onJump.map { jump in { jump(note.page) } },
                                 onCopy: {
                                     Clipboard.copy(currentBook.citation(for: note))
                                     toast = "Copied"
                                 },
                                 onDelete: { store.deleteNote(note, from: book.id) })
                    }
                }
                .listStyle(.inset)
            }
        }
        .toast($toast)
    }
}

// MARK: - Notes & Highlights page

enum AnnotationFilter: String, CaseIterable {
    case all = "All"
    case highlights = "Highlights"
    case notes = "Notes"
    case comments = "Comments"
}

/// Everything you marked, grouped by book. Pick one book to read just its passages.
struct AnnotationLibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var bookID: UUID?
    let onOpen: (LibraryBook, LibraryNote) -> Void
    @State private var filter: AnnotationFilter = .all
    @State private var searchText = ""
    @State private var toast: String?

    private var booksWithNotes: [LibraryBook] {
        store.books.filter { !$0.notes.isEmpty }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func visibleNotes(_ book: LibraryBook) -> [LibraryNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return book.notes
            .filter { note in
                let kindMatches: Bool
                switch filter {
                case .all: kindMatches = true
                case .highlights: kindMatches = note.kind == .highlight
                case .notes: kindMatches = note.kind == .note
                case .comments: kindMatches = note.kind == .comment
                }
                return kindMatches && (query.isEmpty || note.text.localizedCaseInsensitiveContains(query) || book.title.localizedCaseInsensitiveContains(query))
            }
            .sorted { ($0.page, $1.createdAt) < ($1.page, $0.createdAt) }
    }

    private var groups: [(book: LibraryBook, notes: [LibraryNote])] {
        booksWithNotes
            .filter { bookID == nil || $0.id == bookID }
            .map { ($0, visibleNotes($0)) }
            .filter { !$0.1.isEmpty }
    }

    private var scopeTitle: String {
        if let bookID, let book = store.books.first(where: { $0.id == bookID }) { return book.title }
        return "All books"
    }

    /// Markdown for exactly what is on screen (respecting the filter and search).
    private var visibleMarkdown: String {
        groups.map { $0.book.notesMarkdown($0.notes) }.joined(separator: "\n")
    }

    private var visibleCount: Int { groups.reduce(0) { $0 + $1.notes.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if groups.isEmpty {
                QuietEmptyState(
                    title: booksWithNotes.isEmpty ? "No highlights yet" : "Nothing matches",
                    systemImage: "highlighter",
                    description: booksWithNotes.isEmpty
                        ? "Open a PDF, select a passage and pick a colour. It shows up here, ready to copy or share."
                        : "Try another filter or search."
                )
            } else {
                List {
                    ForEach(groups, id: \.book.id) { group in
                        Section {
                            ForEach(group.notes) { note in
                                NoteCard(book: group.book, note: note,
                                         showsBookTitle: false,
                                         onJump: group.book.isMarkdown ? nil : { onOpen(group.book, note) },
                                         onCopy: {
                                             Clipboard.copy(group.book.citation(for: note))
                                             toast = "Copied"
                                         },
                                         onDelete: { store.deleteNote(note, from: group.book.id) })
                            }
                        } header: {
                            bookHeader(group.book, notes: group.notes)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .toast($toast)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notes & Highlights").font(.title2.weight(.semibold))
                    Text(visibleCount == 0 ? "Your highlights, notes and comments, in one place."
                         : "\(visibleCount) passage\(visibleCount == 1 ? "" : "s") · \(scopeTitle)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button { bookID = nil } label: {
                        HStack { Text("All books"); if bookID == nil { Image(systemName: "checkmark") } }
                    }
                    if !booksWithNotes.isEmpty { Divider() }
                    ForEach(booksWithNotes) { book in
                        Button { bookID = book.id } label: {
                            HStack { Text(book.title); if bookID == book.id { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    Label(scopeTitle, systemImage: "book.closed").lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 260)
                Button {
                    Clipboard.copy(visibleMarkdown)
                    toast = "Copied \(visibleCount) passage\(visibleCount == 1 ? "" : "s") as Markdown"
                } label: { Label("Copy all", systemImage: "doc.on.doc") }
                    .disabled(visibleCount == 0)
                    .help("Copy everything shown here as Markdown")
                ShareLink(item: visibleMarkdown) { Label("Share", systemImage: "square.and.arrow.up") }
                    .disabled(visibleCount == 0)
                    .help("Share everything shown here")
                Button(action: saveMarkdown) { Label("Save…", systemImage: "square.and.arrow.down") }
                    .disabled(visibleCount == 0)
                    .help("Save everything shown here as a Markdown file")
            }
            HStack(spacing: 12) {
                Picker("Type", selection: $filter) {
                    ForEach(AnnotationFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
                TextField("Search passages", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(20)
    }

    private func bookHeader(_ book: LibraryBook, notes: [LibraryNote]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: book.isMarkdown ? "text.document" : "book.closed.fill")
                .foregroundStyle(Color.accentColor)
            Text(book.title).font(.headline).lineLimit(1)
            Text("\(notes.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Button {
                Clipboard.copy(book.notesMarkdown(notes))
                toast = "Copied “\(book.title)” passages"
            } label: { Label("Copy", systemImage: "doc.on.doc") }
                .help("Copy this book's passages as Markdown")
            ShareLink(item: book.notesMarkdown(notes)) { Label("Share", systemImage: "square.and.arrow.up") }
                .help("Share this book's passages")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.vertical, 4)
    }

    private func saveMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = (bookID == nil ? "BookLand notes" : scopeTitle) + ".md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try visibleMarkdown.write(to: url, atomically: true, encoding: .utf8)
            toast = "Saved \(url.lastPathComponent)"
        } catch {
            toast = nil
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
