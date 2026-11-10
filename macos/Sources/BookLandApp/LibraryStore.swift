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
        backfillPageCounts()
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

        let count = fileExtension == "pdf" ? PDFDocument(url: destinationURL)?.pageCount : nil
        let book = LibraryBook(id: id, title: cleanTitle, fileName: fileName, sourcePath: sourceURL.path, pageCount: count)
        books.insert(book, at: 0)
        save()
        return book
    }

    /// Adds several files at once, named after the files. Returns the books added and one message per failure.
    func importBooks(from urls: [URL]) -> (added: [LibraryBook], failures: [String]) {
        var added: [LibraryBook] = []
        var failures: [String] = []
        for url in urls {
            do {
                added.append(try importBook(from: url, title: ""))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (added, failures)
    }

    /// Downloads a PDF from a web link and adds it to the library.
    /// Returns a short error message, or nil when the book was added.
    func addBook(fromLink text: String) async -> (book: LibraryBook?, error: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https", parsed.host?.isEmpty == false else {
            return (nil, "That doesn’t look like a web link. Paste an address that starts with https://")
        }
        var request = URLRequest(url: Self.directDownloadURL(parsed), timeoutInterval: 60)
        request.setValue("application/pdf,*/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            let (temporary, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: temporary)
                return (nil, http.statusCode == 401 || http.statusCode == 403
                    ? "That link needs you to sign in, so BookLand can’t download it. Save the PDF to your Mac and import it from there."
                    : "The website answered with an error (\(http.statusCode)). Check the link and try again.")
            }
            // A real PDF starts with %PDF; web pages and sign-in screens don't.
            let head = (try? FileHandle(forReadingFrom: temporary).read(upToCount: 1024)) ?? Data()
            guard head.range(of: Data("%PDF".utf8)) != nil else {
                try? FileManager.default.removeItem(at: temporary)
                return (nil, "That link didn’t give a PDF. It may open a web page, or need you to sign in.")
            }
            let id = UUID()
            let fileName = "\(id.uuidString).pdf"
            let destination = pdfFolderURL.appendingPathComponent(fileName)
            try FileManager.default.moveItem(at: temporary, to: destination)
            let document = PDFDocument(url: destination)
            let embedded = (document?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let suggested = ((response.suggestedFilename ?? "") as NSString).deletingPathExtension
            let title = !embedded.isEmpty ? embedded : (!suggested.isEmpty && suggested != "Unknown" ? suggested : (parsed.host ?? "Downloaded PDF"))
            let book = LibraryBook(id: id, title: title, fileName: fileName, sourcePath: parsed.absoluteString, pageCount: document?.pageCount)
            books.insert(book, at: 0)
            save()
            return (book, nil)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: return (nil, "")
            case .notConnectedToInternet, .networkConnectionLost: return (nil, "No internet connection. Try again when you are online.")
            case .timedOut: return (nil, "The download took too long. Try again.")
            default: return (nil, "Couldn’t download that link (\(error.localizedDescription)).")
            }
        } catch {
            return (nil, "Couldn’t save the downloaded PDF (\(error.localizedDescription)).")
        }
    }

    /// Turns common "share" links into direct file downloads (Dropbox, Google Drive).
    nonisolated static func directDownloadURL(_ url: URL) -> URL {
        guard let host = url.host?.lowercased() else { return url }
        if host.hasSuffix("dropbox.com"), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = (parts.queryItems ?? []).filter { $0.name != "dl" }
            items.append(URLQueryItem(name: "dl", value: "1"))
            parts.queryItems = items
            return parts.url ?? url
        }
        if host == "drive.google.com" {
            let pieces = url.pathComponents
            if let index = pieces.firstIndex(of: "d"), pieces.indices.contains(index + 1) {
                return URL(string: "https://drive.google.com/uc?export=download&id=\(pieces[index + 1])") ?? url
            }
        }
        return url
    }

    func updatePageCount(for id: UUID, count: Int) {
        guard count > 0, let index = books.firstIndex(where: { $0.id == id }), books[index].pageCount != count else { return }
        books[index].pageCount = count
        save()
    }

    /// Books added by an older version don't know their length yet; fill it in quietly.
    private func backfillPageCounts() {
        var changed = false
        for index in books.indices where books[index].pageCount == nil && !books[index].isMarkdown {
            books[index].pageCount = PDFDocument(url: pdfURL(for: books[index]))?.pageCount
            changed = changed || books[index].pageCount != nil
        }
        if changed { save() }
    }

    /// Every highlight and note as Markdown, grouped by book.
    func notesMarkdown(for ids: [UUID]? = nil) -> String {
        books.filter { (ids?.contains($0.id) ?? true) && !$0.notes.isEmpty }
            .map { $0.notesMarkdown() }
            .joined(separator: "\n")
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

    func setArchived(_ id: UUID, _ archived: Bool) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].isArchived = archived
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
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        guard let decoded = try? JSONDecoder.library.decode([LibraryBook].self, from: data) else {
            // Keep an unreadable file instead of overwriting it with an empty library.
            let backup = libraryFolderURL.appendingPathComponent("library-unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: metadataURL, to: backup)
            return
        }
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
