// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../LICENSE.

import SwiftUI

// MARK: - Notes

struct IOSBookNotesRoute: Hashable {
    let bookID: UUID
}

/// One row per book that has highlights or notes; opens that book's own list.
struct IOSNotesView: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @State private var searchText = ""

    private var booksWithNotes: [IOSLibraryBook] {
        store.books.filter { book in
            guard !book.notes.isEmpty else { return false }
            guard !searchText.isEmpty else { return true }
            return book.title.localizedCaseInsensitiveContains(searchText)
                || book.notes.contains { $0.text.localizedCaseInsensitiveContains(searchText) || ($0.quote ?? "").localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(booksWithNotes) { book in
                    NavigationLink(value: IOSBookNotesRoute(bookID: book.id)) {
                        HStack(spacing: 14) {
                            IOSCoverView(book: book, width: 40, height: 54)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title).font(.headline).lineLimit(2)
                                if let summary = book.notesSummary {
                                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .overlay {
                if store.books.allSatisfy({ $0.notes.isEmpty }) {
                    ContentUnavailableView("No highlights yet", systemImage: "highlighter", description: Text("While reading, select text and choose Highlight, Save selection or Add note. Each book keeps its own list here, ready to copy or share."))
                } else if booksWithNotes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Notes")
            .navigationDestination(for: IOSBookNotesRoute.self) { IOSBookNotesView(bookID: $0.bookID) }
            .searchable(text: $searchText, prompt: "Search notes and books")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: store.notesMarkdown(), subject: Text("BookLand notes")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(store.books.allSatisfy { $0.notes.isEmpty })
                    .accessibilityLabel("Share the notes of every book")
                }
            }
        }
    }
}

/// Every highlight, saved passage and note of one book, with copy and share on each.
struct IOSBookNotesView: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @Environment(\.dismiss) private var dismiss
    let bookID: UUID
    /// Set when shown inside the reader: jump within the open book instead of pushing a new reader.
    var onOpen: ((Int) -> Void)? = nil

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", highlights = "Highlights", notes = "Notes"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var sortByPage = true
    @State private var searchText = ""
    @State private var toast: String?
    @State private var openRoute: IOSReaderRoute?

    private var book: IOSLibraryBook? { store.book(bookID) }

    private func visibleNotes(_ book: IOSLibraryBook) -> [IOSLibraryNote] {
        var list = book.notes
        switch filter {
        case .all: break
        case .highlights: list = list.filter { $0.isHighlight || $0.isQuote }
        case .notes: list = list.filter { !$0.isHighlight && !$0.isQuote }
        }
        if !searchText.isEmpty {
            list = list.filter { $0.text.localizedCaseInsensitiveContains(searchText) || ($0.quote ?? "").localizedCaseInsensitiveContains(searchText) }
        }
        return sortByPage
            ? list.sorted { ($0.page, $0.date ?? .distantPast) < ($1.page, $1.date ?? .distantPast) }
            : list.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        Group {
            if let book {
                content(book)
            } else {
                ContentUnavailableView("Book not found", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(book?.title ?? "Notes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openRoute) { IOSReaderLoader(route: $0) }
        .iosToast($toast)
    }

    @ViewBuilder
    private func content(_ book: IOSLibraryBook) -> some View {
        let notes = visibleNotes(book)
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            Section(book.notesSummary ?? "Nothing saved yet") {
                ForEach(notes) { note in
                    row(note, in: book)
                }
                .onDelete { offsets in
                    offsets.map { notes[$0] }.forEach { store.deleteNote($0, from: book) }
                }
            }
        }
        .overlay {
            if book.notes.isEmpty {
                ContentUnavailableView("No highlights yet", systemImage: "highlighter", description: Text("Select text while reading, then choose Highlight, Save selection or Add note."))
            } else if notes.isEmpty {
                ContentUnavailableView.search(text: searchText.isEmpty ? filter.rawValue : searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search this book’s notes")
        .toolbar {
            if onOpen != nil {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = book.notesMarkdown(notes)
                        toast = notes.count == 1 ? "Copied 1 item" : "Copied \(notes.count) items"
                    } label: { Label("Copy \(filter == .all && searchText.isEmpty ? "all" : "shown")", systemImage: "doc.on.doc") }
                    ShareLink(item: book.notesMarkdown(notes), subject: Text(book.title)) {
                        Label("Share \(filter == .all && searchText.isEmpty ? "all" : "shown")…", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Picker("Order", selection: $sortByPage) {
                        Label("By page", systemImage: "number").tag(true)
                        Label("Newest first", systemImage: "clock").tag(false)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(book.notes.isEmpty)
                .accessibilityLabel("Copy, share and sort")
            }
        }
    }

    private func row(_ note: IOSLibraryNote, in book: IOSLibraryBook) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { open(note, in: book) } label: {
                HStack(alignment: .top, spacing: 10) {
                    marker(for: note)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.text)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .lineLimit(8)
                        if let quote = note.quote, !quote.isEmpty {
                            Text(quote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .padding(.leading, 8)
                                .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 2) }
                        }
                        Text("Page \(note.page) · \(note.kind)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .accessibilityHint("Opens the book at page \(note.page)")

            VStack(spacing: 2) {
                Button {
                    UIPasteboard.general.string = book.citation(for: note)
                    toast = "Copied with page number"
                } label: {
                    Image(systemName: "doc.on.doc").frame(width: 40, height: 36)
                }
                .accessibilityLabel("Copy")
                ShareLink(item: book.citation(for: note)) {
                    Image(systemName: "square.and.arrow.up").frame(width: 40, height: 36)
                }
                .accessibilityLabel("Share")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(IOSDesign.accent)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button { open(note, in: book) } label: { Label("Open page \(note.page)", systemImage: "book") }
            Button { UIPasteboard.general.string = note.text; toast = "Copied text only" } label: { Label("Copy text only", systemImage: "text.quote") }
            Button(role: .destructive) { store.deleteNote(note, from: book) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func marker(for note: IOSLibraryNote) -> some View {
        if note.isHighlight {
            let color = IOSHighlightColor(rawValue: note.colorName ?? "") ?? .yellow
            RoundedRectangle(cornerRadius: 2).fill(Color(uiColor: color.uiColor)).frame(width: 4).padding(.vertical, 2)
        } else if note.isQuote {
            Image(systemName: "quote.opening").foregroundStyle(IOSDesign.accent).frame(width: 18).padding(.top, 3)
        } else {
            Image(systemName: "note.text").foregroundStyle(IOSDesign.accent).frame(width: 18).padding(.top, 3)
        }
    }

    private func open(_ note: IOSLibraryNote, in book: IOSLibraryBook) {
        if let onOpen { onOpen(note.page) } else { openRoute = IOSReaderRoute(bookID: book.id, page: note.page) }
    }
}

// MARK: - Compare

struct IOSCompareHome: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @State private var leftID: UUID?
    @State private var rightID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if store.books.isEmpty {
                    ContentUnavailableView("Import a PDF first", systemImage: "rectangle.split.2x1", description: Text("Pick two books from your library and read them side by side."))
                } else {
                    IOSCompareView(leftID: $leftID, rightID: $rightID)
                }
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        swap(&leftID, &rightID)
                    } label: { Image(systemName: "arrow.left.arrow.right") }
                    .accessibilityLabel("Swap the two books")
                    .disabled(store.books.count < 2)
                }
            }
            .onAppear { pickDefaults() }
            .onChange(of: store.books) { _, _ in pickDefaults() }
        }
    }

    /// Chooses two books on first use, and re-chooses if one was deleted.
    private func pickDefaults() {
        let ids = store.books.map(\.id)
        if leftID == nil || !ids.contains(leftID!) { leftID = ids.first }
        if rightID == nil || !ids.contains(rightID!) { rightID = ids.dropFirst().first ?? ids.first }
    }
}

struct IOSCompareView: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @Binding var leftID: UUID?
    @Binding var rightID: UUID?

    var body: some View {
        GeometryReader { proxy in
            let sideBySide = proxy.size.width > proxy.size.height
            let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
            layout {
                IOSComparePane(label: sideBySide ? "Left" : "Top", book: store.book(leftID ?? UUID()), books: store.books) { leftID = $0 }
                IOSComparePane(label: sideBySide ? "Right" : "Bottom", book: store.book(rightID ?? UUID()), books: store.books) { rightID = $0 }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

struct IOSComparePane: View {
    let label: String
    let book: IOSLibraryBook?
    let books: [IOSLibraryBook]
    let onSelectBook: (UUID) -> Void
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage("readerTheme") private var appearance: IOSReaderTheme = .milky
    @AppStorage("readerMode") private var readingMode: IOSReadingMode = .pageTurn
    @StateObject private var controller = IOSReaderController()
    @State private var showingPageBrowser = false

    private var paper: Color { appearance.paperColor(systemScheme) }
    private var dark: Bool { appearance.isDark(systemScheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(books) { item in
                        Button { onSelectBook(item.id) } label: {
                            if item.id == book?.id { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(book?.title ?? "Choose a PDF").lineLimit(1).font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
                .accessibilityLabel("\(label) book: \(book?.title ?? "none")")
                Spacer(minLength: 4)
                Menu {
                    Picker("Reading mode", selection: $readingMode) {
                        ForEach(IOSReadingMode.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    }
                } label: { Image(systemName: readingMode.icon).frame(width: 32, height: 32) }
                Menu {
                    Picker("Paper", selection: $appearance) {
                        ForEach(IOSReaderTheme.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    }
                } label: { Image(systemName: appearance.icon).frame(width: 32, height: 32) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .foregroundStyle(.primary)
            .background(paper)
            .environment(\.colorScheme, dark ? .dark : .light)

            if let book {
                ZStack {
                    IOSStyledPDF(url: book.fileURL, controller: controller, paper: paper, isDark: dark, isSketchy: appearance.isSketchy, mode: readingMode, initialPage: book.lastPage)
                    if let error = controller.documentError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                IOSReaderToolbar(controller: controller, showingPageBrowser: $showingPageBrowser, compact: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(paper)
                    .environment(\.colorScheme, dark ? .dark : .light)
            } else {
                ContentUnavailableView("Choose a PDF", systemImage: "doc.text")
                    .background(paper)
            }
        }
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .sheet(isPresented: $showingPageBrowser) { IOSPageBrowserSheet(controller: controller) }
    }
}

// MARK: - Settings

struct IOSSettingsView: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @EnvironmentObject private var signing: IOSSigningMonitor
    @AppStorage("readerTheme") private var theme: IOSReaderTheme = .milky
    @AppStorage("readerMode") private var mode: IOSReadingMode = .pageTurn
    @AppStorage("keepScreenAwake") private var keepAwake = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading") {
                    Picker("Paper", selection: $theme) {
                        ForEach(IOSReaderTheme.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    }
                    Picker("Turning pages", selection: $mode) {
                        ForEach(IOSReadingMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Keep screen on while reading", isOn: $keepAwake)
                }

                signingSection

                Section("Library") {
                    LabeledContent("Books", value: "\(store.books.count)")
                    LabeledContent("Space used", value: ByteCountFormatter.string(fromByteCount: store.storageBytes, countStyle: .file))
                    Text("Your PDFs are also visible in the Files app under On My iPhone › BookLand.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Importing PDFs") {
                    Label("Telegram: open the PDF → Share → More → BookLand", systemImage: "paperplane")
                    Label("Mail: press and hold the attachment → Share → BookLand", systemImage: "envelope")
                    Label("Files or Safari: Share → BookLand", systemImage: "folder")
                }
                .font(.subheadline)

                Section {
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

    @ViewBuilder
    private var signingSection: some View {
        Section {
            if let expiry = signing.expiry {
                LabeledContent("Stops opening") {
                    Text(expiry, format: .dateTime.weekday().day().month().hour().minute())
                }
                LabeledContent("Time left") {
                    Text(signing.timeLeftText).foregroundStyle(signing.shouldWarn ? Color.orange : .secondary)
                }
                Toggle("Remind me before it expires", isOn: Binding(
                    get: { signing.remindersEnabled },
                    set: { value in Task { await signing.setReminders(value) } }
                ))
                if signing.notificationsDenied {
                    Text("Notifications are off for BookLand. Turn them on in the iPhone's Settings app to get reminders.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Text("A free Apple ID lets Xcode install apps for 7 days. To renew: connect your iPhone, open the project in Xcode, and press Run. Don't delete BookLand first; installing over it keeps your library and notes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("This copy has no expiry date. That is the case in the Simulator, or when BookLand was installed in a way that isn't limited to 7 days.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Keeping BookLand installed")
        }
    }
}

struct IOSAboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

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
                        Text("BookLand").font(.title3.weight(.semibold))
                        Text("A calm research reading space").font(.subheadline).foregroundStyle(.secondary)
                        Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Why BookLand") {
                Text("BookLand makes it convenient to read two books at the same time. Open two different PDFs, move through their pages independently, and compare them side by side without leaving the reading workspace.")
                    .font(.subheadline)
                Text("Compared with a standard PDF viewer, BookLand combines a local book library, titles and tags, page history, thumbnails and index navigation, search, notes, highlights, study themes, zoom, and independent comparison panes in one place.")
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
