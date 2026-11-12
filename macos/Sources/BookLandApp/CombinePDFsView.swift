// BookLand - Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// One PDF in the combine list, with the details shown in its row.
struct CombineItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let pageCount: Int
    let fileSize: Int64
    let thumbnail: NSImage?
    /// Set when the file cannot be combined (damaged or password protected).
    let problem: String?

    static func == (lhs: CombineItem, rhs: CombineItem) -> Bool { lhs.id == rhs.id }

    var isUsable: Bool { problem == nil }

    static func load(_ url: URL) -> CombineItem {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) } ?? 0
        guard let document = PDFDocument(url: url) else {
            return CombineItem(url: url, pageCount: 0, fileSize: size, thumbnail: nil, problem: "Can't be opened")
        }
        if document.isLocked, !document.unlock(withPassword: "") {
            return CombineItem(url: url, pageCount: 0, fileSize: size, thumbnail: nil, problem: "Password protected")
        }
        let thumbnail = document.page(at: 0)?.thumbnail(of: NSSize(width: 84, height: 112), for: .cropBox)
        return CombineItem(url: url, pageCount: document.pageCount, fileSize: size, thumbnail: thumbnail, problem: nil)
    }
}

struct CombinePDFsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CombineItem] = []
    @State private var selection = Set<CombineItem.ID>()
    @State private var addBookmarks = true
    @State private var isDropTargeted = false
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var savedURL: URL?
    @State private var errorMessage: String?

    private var usableItems: [CombineItem] { items.filter(\.isUsable) }
    private var totalPages: Int { usableItems.reduce(0) { $0 + $1.pageCount } }
    private var totalSize: Int64 { usableItems.reduce(0) { $0 + $1.fileSize } }
    private var canCombine: Bool { !usableItems.isEmpty && !isSaving && !isLoading }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                if items.isEmpty {
                    emptyState
                } else {
                    fileList
                }
                if isDropTargeted { dropOverlay }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dropDestination(for: URL.self) { urls, _ in
                add(urls)
                return !urls.isEmpty
            } isTargeted: { isDropTargeted = $0 }
            Divider()
            footer
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 560, idealHeight: 620)
        .alert("Combine PDFs", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Combine PDFs")
                    .font(.title2.weight(.semibold))
                Text("Add as many files as you need, put them in order, then save one PDF.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !items.isEmpty {
                Menu {
                    Button("Sort by Name (A→Z)") { items.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending } }
                    Button("Reverse Order") { items.reverse() }
                    Divider()
                    Button("Remove All", role: .destructive) { items.removeAll(); selection.removeAll(); savedURL = nil }
                } label: {
                    Label("Arrange", systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Button {
                chooseFiles()
            } label: {
                Label("Add PDFs…", systemImage: "plus")
            }
            .disabled(isSaving)
        }
        .padding(16)
    }

    // MARK: List

    private var fileList: some View {
        List(selection: $selection) {
            ForEach(items) { item in
                row(for: item)
                    .tag(item.id)
                    .contextMenu {
                        Button("Move Up") { move(item, by: -1) }
                        Button("Move Down") { move(item, by: 1) }
                        Divider()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                        Button("Remove", role: .destructive) { remove([item.id]) }
                    }
            }
            .onMove { items.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.inset)
        .onDeleteCommand { remove(selection) }
    }

    private func row(for item: CombineItem) -> some View {
        HStack(spacing: 12) {
            Text("\((items.firstIndex(of: item) ?? 0) + 1)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            thumbnailView(for: item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.deletingPathExtension().lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let problem = item.problem {
                    Label("\(problem) · will be skipped", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("\(item.pageCount) page\(item.pageCount == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                remove([item.id])
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from list")
            .disabled(isSaving)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
        }
        .padding(.vertical, 4)
    }

    private func thumbnailView(for item: CombineItem) -> some View {
        Group {
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 42, height: 56)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.15)))
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
    }

    // MARK: Empty and drop states

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Drop PDFs here")
                .font(.title3.weight(.semibold))
            Text("or choose several files at once. You can keep adding more.")
                .foregroundStyle(.secondary)
            Button("Choose PDFs…") { chooseFiles() }
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
            .background(Color.accentColor.opacity(0.08))
            .overlay(Label("Drop to add", systemImage: "plus.circle.fill").font(.title3.weight(.semibold)).foregroundStyle(Color.accentColor))
            .padding(10)
            .allowsHitTesting(false)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            if let savedURL {
                HStack {
                    Label("Saved \(savedURL.lastPathComponent)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .lineLimit(1)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([savedURL]) }
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryText)
                        .font(.callout.weight(.medium))
                    Text("Pages are copied as they are. Text, images and quality are not changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading || isSaving {
                    ProgressView().controlSize(.small)
                }
                Toggle("Bookmark each file", isOn: $addBookmarks)
                    .toggleStyle(.checkbox)
                    .help("Adds a clickable table-of-contents entry for each file")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Combine & Save…") { combine() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCombine)
            }
        }
        .padding(16)
    }

    private var summaryText: String {
        if items.isEmpty { return "No files yet" }
        let files = usableItems.count
        return "\(files) file\(files == 1 ? "" : "s") · \(totalPages) page\(totalPages == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))"
    }

    // MARK: Actions

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Select one or more PDFs. Hold ⌘ or Shift to choose several."
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    /// Appends files to the list (never replaces it). A batch is placed in
    /// natural filename order, because pickers and drag and drop do not
    /// guarantee the order the user selected.
    private func add(_ urls: [URL]) {
        let pdfs = urls
            .filter { $0.isFileURL && $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !pdfs.isEmpty else {
            if !urls.isEmpty { errorMessage = "Only PDF files can be combined." }
            return
        }
        savedURL = nil
        isLoading = true
        Task { @MainActor in
            for url in pdfs {
                items.append(CombineItem.load(url))
                await Task.yield()
            }
            isLoading = false
        }
    }

    private func remove(_ ids: Set<CombineItem.ID>) {
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        savedURL = nil
    }

    private func move(_ item: CombineItem, by offset: Int) {
        guard let index = items.firstIndex(of: item) else { return }
        let target = index + offset
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }

    private func combine() {
        let urls = usableItems.map(\.url)
        guard !urls.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "BookLand-combined.pdf"
        panel.canCreateDirectories = true
        panel.directoryURL = urls.first?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let bookmarks = addBookmarks
        isSaving = true
        savedURL = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BookLandDocumentTools.combinePDFs(urls: urls, addBookmarks: bookmarks, to: destination)
                }.value
                savedURL = destination
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
