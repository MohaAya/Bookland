// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../LICENSE.

import SwiftUI

/// Where a reader should open: a book and, optionally, a specific page (from the Notes tab).
struct IOSReaderRoute: Hashable {
    let bookID: UUID
    var page: Int? = nil
}

enum IOSLibrarySort: String, CaseIterable, Identifiable {
    case recent = "Recently read"
    case title = "Title"
    case added = "Date added"
    var id: String { rawValue }
}

struct IOSLibraryHome: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @EnvironmentObject private var signing: IOSSigningMonitor
    @AppStorage("librarySort") private var sort: IOSLibrarySort = .recent
    @State private var showingImporter = false
    @State private var showingLinkSheet = false
    @State private var searchText = ""
    @State private var renaming: IOSLibraryBook?
    @State private var renameText = ""
    @State private var tagging: IOSLibraryBook?
    @State private var tagText = ""
    @State private var deleting: IOSLibraryBook?
    @State private var toast: String?

    private var visibleBooks: [IOSLibraryBook] {
        let matches = searchText.isEmpty ? store.books : store.books.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
        switch sort {
        case .recent: return matches.sorted { ($0.lastOpenedAt ?? $0.dateAdded) > ($1.lastOpenedAt ?? $1.dateAdded) }
        case .title: return matches.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .added: return matches.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.books.isEmpty {
                    IOSEmptyLibrary(showingImporter: $showingImporter, showingLinkSheet: $showingLinkSheet)
                } else {
                    libraryList
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: IOSReaderRoute.self) { IOSReaderLoader(route: $0) }
            .searchable(text: $searchText, prompt: "Search titles and tags")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(IOSLibrarySort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel("Sort library")
                    .disabled(store.books.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingImporter = true } label: { Label("Import from Files", systemImage: "folder") }
                        Button { showingLinkSheet = true } label: { Label("Add from a link…", systemImage: "link") }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a PDF")
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    if urls.count == 1, let url = urls.first {
                        // One file: ask for a title, same as Share → Open in BookLand.
                        store.prepareIncomingPDF(from: url)
                    } else {
                        let added = urls.filter { store.importPDF(from: $0) }.count
                        if added > 0 { toast = "Added \(added) PDFs" }
                    }
                case .failure:
                    store.importError = "The PDF picker could not open this file."
                }
            }
            .sheet(isPresented: $showingLinkSheet) { IOSAddFromLinkSheet() }
            .onChange(of: store.lastAddedTitle) { _, title in
                guard let title else { return }
                toast = "Added “\(title)”"
                store.lastAddedTitle = nil
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Title", text: $renameText)
                Button("Save") { if let renaming { store.rename(renaming, to: renameText) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .alert("Tags", isPresented: Binding(get: { tagging != nil }, set: { if !$0 { tagging = nil } })) {
                TextField("research, thesis, to read", text: $tagText)
                Button("Save") {
                    if let tagging {
                        let tags = tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        store.setTags(tags, for: tagging)
                    }
                    tagging = nil
                }
                Button("Cancel", role: .cancel) { tagging = nil }
            } message: {
                Text("Separate tags with commas.")
            }
            .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete PDF and Notes", role: .destructive) {
                    if let deleting { store.removeBook(deleting) }
                    deleting = nil
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: {
                Text("This removes the PDF and its highlights from this iPhone. It cannot be undone.")
            }
            .iosToast($toast)
        }
    }

    private var libraryList: some View {
        List {
            if signing.shouldWarn {
                Section {
                    IOSExpiryBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if searchText.isEmpty, let recent = store.mostRecentlyOpened {
                Section("Continue reading") {
                    NavigationLink(value: IOSReaderRoute(bookID: recent.id)) {
                        IOSContinueCard(book: recent)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            Section(searchText.isEmpty ? "All books · \(visibleBooks.count)" : "Results · \(visibleBooks.count)") {
                ForEach(visibleBooks) { book in
                    NavigationLink(value: IOSReaderRoute(bookID: book.id)) {
                        IOSBookRow(book: book)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleting = book } label: { Label("Delete", systemImage: "trash") }
                        Button { startTagging(book) } label: { Label("Tags", systemImage: "tag") }.tint(.indigo)
                    }
                    .swipeActions(edge: .leading) {
                        Button { startRenaming(book) } label: { Label("Rename", systemImage: "pencil") }.tint(IOSDesign.accent)
                    }
                    .contextMenu {
                        Button { startRenaming(book) } label: { Label("Rename", systemImage: "pencil") }
                        Button { startTagging(book) } label: { Label("Edit tags", systemImage: "tag") }
                        Divider()
                        Button(role: .destructive) { deleting = book } label: { Label("Delete…", systemImage: "trash") }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if !searchText.isEmpty && visibleBooks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func startRenaming(_ book: IOSLibraryBook) {
        renameText = book.title
        renaming = book
    }

    private func startTagging(_ book: IOSLibraryBook) {
        tagText = book.tags.joined(separator: ", ")
        tagging = book
    }
}

struct IOSCoverView: View {
    let book: IOSLibraryBook
    var width: CGFloat = 46
    var height: CGFloat = 62
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [IOSDesign.accent, IOSDesign.accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "doc.text.fill").foregroundStyle(.white.opacity(0.9)))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1.5)
        .task(id: book.fileName) { image = await IOSCoverCache.image(for: book) }
        .accessibilityHidden(true)
    }
}

struct IOSBookRow: View {
    let book: IOSLibraryBook

    var body: some View {
        HStack(spacing: 14) {
            IOSCoverView(book: book)
            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if book.pageCount != nil {
                    ProgressView(value: book.progress)
                        .tint(IOSDesign.accent)
                }
                if !book.tags.isEmpty {
                    Text(book.tags.joined(separator: "  ·  "))
                        .font(.caption2)
                        .foregroundStyle(IOSDesign.accent)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let count = book.pageCount, count > 0 else { return book.progressText }
        return "\(book.progressText) · \(Int((book.progress * 100).rounded()))%"
    }
}

struct IOSContinueCard: View {
    let book: IOSLibraryBook

    var body: some View {
        HStack(spacing: 16) {
            IOSCoverView(book: book, width: 64, height: 86)
            VStack(alignment: .leading, spacing: 6) {
                Text("Resume")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(IOSDesign.accent)
                Text(book.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(book.progressText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if book.pageCount != nil {
                    ProgressView(value: book.progress).tint(IOSDesign.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(IOSDesign.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the book where you stopped")
    }
}

struct IOSExpiryBanner: View {
    @EnvironmentObject private var signing: IOSSigningMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("BookLand stops opening in \(signing.timeLeftText)", systemImage: "clock.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("iPhone limits apps installed with a free Apple ID to 7 days. Connect your iPhone to your Mac and press Run in Xcode — don't delete BookLand first, and your library stays.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !signing.remindersEnabled {
                Button("Remind me before it happens") { Task { await signing.setReminders(true) } }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct IOSAddFromLinkSheet: View {
    @EnvironmentObject private var store: IOSLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var working = false
    @State private var errorText: String?
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var canDownload: Bool { !link.trimmingCharacters(in: .whitespaces).isEmpty && !working }

    var body: some View {
        NavigationStack {
            Form {
                Section("Link to a PDF") {
                    TextField("Link", text: $link, prompt: Text("Paste or type a link").foregroundStyle(.secondary), axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(download)
                        .disabled(working)
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { link = first; errorText = nil }
                    }
                    .disabled(working)
                }
                if working {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Downloading…")
                            Spacer()
                            Button("Stop", role: .cancel) { task?.cancel() }
                        }
                    }
                }
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Text("Works with a direct link to a PDF, and with Dropbox and Google Drive share links. The file is saved on this iPhone, so you can read it offline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add from a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { task?.cancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Download", action: download).fontWeight(.semibold).disabled(!canDownload)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(working)
    }

    private func download() {
        guard canDownload else { return }
        errorText = nil
        working = true
        focused = false
        task = Task {
            let result = await store.addBook(fromLink: link)
            working = false
            if let result {
                if !result.isEmpty { errorText = result }
            } else {
                dismiss()
            }
        }
    }
}

struct IOSEmptyLibrary: View {
    @Binding var showingImporter: Bool
    @Binding var showingLinkSheet: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 52))
                    .foregroundStyle(IOSDesign.accent)
                    .padding(.top, 48)
                Text("Your library is empty")
                    .font(.title2.weight(.semibold))
                Text("Add a PDF to start reading.")
                    .foregroundStyle(.secondary)
                Button { showingImporter = true } label: {
                    Label("Import a PDF", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(IOSDesign.accent)
                Button { showingLinkSheet = true } label: { Label("Add from a link", systemImage: "link") }
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Or send one from another app")
                        .font(.subheadline.weight(.semibold))
                    importStep("paperplane", "Telegram", "Open the PDF → Share → More → BookLand")
                    importStep("envelope", "Mail", "Press and hold the attachment → Share → BookLand")
                    importStep("folder", "Files or Safari", "Share → BookLand")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(IOSDesign.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
    }

    private func importStep(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(IOSDesign.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// A short confirmation pill that fades after a moment.
struct IOSToastModifier: ViewModifier {
    @Binding var message: String?
    var edge: VerticalEdge = .bottom

    func body(content: Content) -> some View {
        content.overlay(alignment: edge == .top ? .top : .bottom) {
            if let message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thickMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .padding(edge == .top ? .top : .bottom, edge == .top ? 64 : 24)
                    .transition(.move(edge: edge == .top ? .top : .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: message)
    }
}

extension View {
    func iosToast(_ message: Binding<String?>, edge: VerticalEdge = .bottom) -> some View {
        modifier(IOSToastModifier(message: message, edge: edge))
    }
}
