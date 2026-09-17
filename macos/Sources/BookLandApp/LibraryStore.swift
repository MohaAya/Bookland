// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../../LICENSE.

import Foundation
import Combine
import PDFKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [LibraryBook] = []

    let libraryFolderURL: URL
    private let pdfFolderURL: URL
    private let metadataURL: URL

    init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bookLandFolder = applicationSupport.appendingPathComponent("BookLand", isDirectory: true)
        let legacyFolder = applicationSupport.appendingPathComponent("QuietLibrary", isDirectory: true)
        if !FileManager.default.fileExists(atPath: bookLandFolder.path), FileManager.default.fileExists(atPath: legacyFolder.path) {
            try? FileManager.default.moveItem(at: legacyFolder, to: bookLandFolder)
        }
        libraryFolderURL = bookLandFolder
        pdfFolderURL = libraryFolderURL.appendingPathComponent("PDFs", isDirectory: true)
        metadataURL = libraryFolderURL.appendingPathComponent("library.json")
        createFolders()
        load()
    }

    func pdfURL(for book: LibraryBook) -> URL {
        pdfFolderURL.appendingPathComponent(book.fileName)
    }

    @discardableResult
    func importBook(from sourceURL: URL, title: String) throws -> LibraryBook {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? sourceURL.deletingPathExtension().lastPathComponent
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID()
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let fileExtension = sourceExtension == "markdown" ? "md" : sourceExtension
        guard ["pdf", "md"].contains(fileExtension) else {
            throw LibraryImportError.unsupportedFileType
        }
        let fileName = "\(id.uuidString).\(fileExtension)"
        let destinationURL = pdfFolderURL.appendingPathComponent(fileName)

        if sourceURL.startAccessingSecurityScopedResource() {
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }

        let book = LibraryBook(id: id, title: cleanTitle, fileName: fileName, sourcePath: sourceURL.path)
        books.insert(book, at: 0)
        save()
        return book
    }

    func updateLastPage(for id: UUID, page: Int) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].lastPage = max(1, page)
        save()
    }

    func updateBook(_ id: UUID, title: String, tags: [String]) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? books[index].title : title.trimmingCharacters(in: .whitespacesAndNewlines)
        books[index].tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        save()
    }

    func markOpened(_ id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].lastOpenedAt = .now
        books[index].openCount += 1
        save()
    }

    func markRead(_ id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].lastReadAt = .now
        books[index].readCount += 1
        save()
    }

    func addNote(_ note: LibraryNote, to id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].notes.insert(note, at: 0)
        save()
    }

    func deleteNote(_ note: LibraryNote, from id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].notes.removeAll { $0.id == note.id }
        save()
    }

    func deleteHighlight(page: Int, text: String, from id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].notes.removeAll {
            $0.kind == .highlight && $0.page == page && (text.isEmpty || $0.text == text)
        }
        save()
    }

    func removeBook(_ book: LibraryBook) {
        books.removeAll { $0.id == book.id }
        try? FileManager.default.removeItem(at: pdfURL(for: book))
        save()
    }

    private func createFolders() {
        try? FileManager.default.createDirectory(at: pdfFolderURL, withIntermediateDirectories: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder.library.decode([LibraryBook].self, from: data) else { return }
        books = decoded.filter { FileManager.default.fileExists(atPath: pdfURL(for: $0).path) }
    }

    private func save() {
        guard let data = try? JSONEncoder.library.encode(books) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }
}

enum LibraryImportError: LocalizedError {
    case unsupportedFileType

    var errorDescription: String? {
        "BookLand supports PDF and Markdown (.md) files."
    }
}

private extension JSONEncoder {
    static var library: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var library: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
