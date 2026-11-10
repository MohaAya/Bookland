// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../LICENSE.

import SwiftUI

// MARK: - Notes

struct IOSNotesView: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @State private var searchText = ""

    private var booksWithNotes: [IOSLibraryBook] {
        store.books.filter { book in
            !filteredNotes(book).isEmpty
        }
    }

    private func filteredNotes(_ book: IOSLibraryBook) -> [IOSLibraryNote] {
        let sorted = book.notes.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.text.localizedCaseInsensitiveContains(searchText) || ($0.quote ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(booksWithNotes) { book in
                    Section(book.title) {
                        ForEach(filteredNotes(book)) { note in
                            NavigationLink(value: IOSReaderRoute(bookID: book.id, page: note.page)) {
                                IOSNoteRow(note: note)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.deleteNote(note, from: book) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .contextMenu {
                                Button { UIPasteboard.general.string = note.text } label: { Label("Copy", systemImage: "doc.on.doc") }
                                Button(role: .destructive) { store.deleteNote(note, from: book) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .overlay {
                if store.books.allSatisfy({ $0.notes.isEmpty }) {
                    ContentUnavailableView("No notes yet", systemImage: "highlighter", description: Text("While reading, select text and tap the highlighter to save a highlight or write a note. They collect here."))
                } else if booksWithNotes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Notes")
            .navigationDestination(for: IOSReaderRoute.self) { IOSReaderLoader(route: $0) }
            .searchable(text: $searchText, prompt: "Search notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: store.notesMarkdown(), subject: Text("BookLand notes")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(store.books.allSatisfy { $0.notes.isEmpty })
                    .accessibilityLabel("Share all notes")
                }
            }
        }
    }
}

struct IOSNoteRow: View {
    let note: IOSLibraryNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.isHighlight ? "highlighter" : "note.text")
                .foregroundStyle(note.isHighlight ? Color.orange : IOSDesign.accent)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.text)
                    .font(.body)
                    .lineLimit(5)
                if let quote = note.quote, !quote.isEmpty {
                    Text(quote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 2) }
                }
                Text("Page \(note.page) · \(note.kind)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
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
