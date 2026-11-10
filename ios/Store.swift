// BookLand — Copyright (c) 2026 Mohammad Ayati
// Licensed under the MIT License. See ../LICENSE.

import Foundation
import PDFKit
import SwiftUI
import UIKit

enum IOSStorage {
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

struct IOSLibraryNote: Identifiable, Hashable, Codable {
    let id: UUID
    let page: Int
    /// The highlighted passage (kind "Highlight") or the note body (kind "Note").
    var text: String
    var kind: String
    /// For notes written on top of a selection: the passage the note refers to.
    var quote: String?
    var date: Date?

    init(id: UUID = UUID(), page: Int, text: String, kind: String, quote: String? = nil, date: Date? = .now) {
        self.id = id
        self.page = page
        self.text = text
        self.kind = kind
        self.quote = quote
        self.date = date
    }

    var isHighlight: Bool { kind == "Highlight" }
}

struct IOSLibraryBook: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    /// File name inside the app's Documents folder. Only the name is stored, never the
    /// full path: the app container's path changes when the app is re-signed or reinstalled,
    /// and an absolute path would then silently orphan every book.
    var fileName: String
    var tags: [String]
    var lastPage: Int
    var notes: [IOSLibraryNote]
    var dateAdded: Date
    var lastOpenedAt: Date?
    var pageCount: Int?

    var fileURL: URL { IOSStorage.documentsURL.appendingPathComponent(fileName) }

    var progress: Double {
        guard let count = pageCount, count > 1 else { return 0 }
        return min(1, max(0, Double(lastPage - 1) / Double(count - 1)))
    }

    var progressText: String {
        if let count = pageCount { return "Page \(min(lastPage, count)) of \(count)" }
        return "Page \(lastPage)"
    }

    init(id: UUID = UUID(), title: String, fileName: String, tags: [String] = [], lastPage: Int = 1, notes: [IOSLibraryNote] = [], dateAdded: Date = .now, lastOpenedAt: Date? = nil, pageCount: Int? = nil) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.tags = tags
        self.lastPage = lastPage
        self.notes = notes
        self.dateAdded = dateAdded
        self.lastOpenedAt = lastOpenedAt
        self.pageCount = pageCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, fileName, fileURL, tags, lastPage, notes, dateAdded, lastOpenedAt, pageCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        if let name = try c.decodeIfPresent(String.self, forKey: .fileName) {
            fileName = name
        } else if let legacy = try c.decodeIfPresent(URL.self, forKey: .fileURL) {
            // Library written by BookLand 0.1, which stored an absolute URL.
            fileName = legacy.lastPathComponent
        } else {
            throw DecodingError.dataCorruptedError(forKey: .fileName, in: c, debugDescription: "Missing file name")
        }
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        lastPage = try c.decodeIfPresent(Int.self, forKey: .lastPage) ?? 1
        notes = try c.decodeIfPresent([IOSLibraryNote].self, forKey: .notes) ?? []
        dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? .now
        lastOpenedAt = try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(tags, forKey: .tags)
        try c.encode(lastPage, forKey: .lastPage)
        try c.encode(notes, forKey: .notes)
        try c.encode(dateAdded, forKey: .dateAdded)
        try c.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
        try c.encodeIfPresent(pageCount, forKey: .pageCount)
    }
}

@MainActor
final class IOSLibraryStore: ObservableObject {
    @Published private(set) var books: [IOSLibraryBook] = []
    @Published var importError: String?
    @Published var pendingImportURL: URL?
    @Published var pendingImportTitle = ""
    /// Short confirmation shown after an import ("Added “Title”").
    @Published var lastAddedTitle: String?

    private var documentsURL: URL { IOSStorage.documentsURL }
    private var metadataURL: URL { documentsURL.appendingPathComponent("library.json") }

    init() {
        load()
        backfillPageCounts()
    }

    /// Books imported by an older version don't know their length yet; fill it in quietly.
    private func backfillPageCounts() {
        let missing = books.filter { $0.pageCount == nil }
        guard !missing.isEmpty else { return }
        Task {
            for book in missing {
                let url = book.fileURL
                let count = await Task.detached(priority: .utility) { PDFDocument(url: url)?.pageCount }.value
                if let count { setPageCount(count, for: book) }
            }
        }
    }

    func book(_ id: UUID) -> IOSLibraryBook? { books.first { $0.id == id } }

    var mostRecentlyOpened: IOSLibraryBook? {
        books.filter { $0.lastOpenedAt != nil }.max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    // MARK: Import

    /// Receives a PDF from Telegram, Mail, Safari, Files, or another app's Share / Open in.
    /// The file is staged immediately because the security-scoped URL may not remain
    /// available while the title sheet is open.
    func prepareIncomingPDF(from incomingURL: URL) {
        guard incomingURL.isFileURL, incomingURL.pathExtension.lowercased() == "pdf" else {
            importError = "BookLand can receive PDF files only."
            return
        }
        let accessed = incomingURL.startAccessingSecurityScopedResource()
        defer { if accessed { incomingURL.stopAccessingSecurityScopedResource() } }

        let stagedURL = documentsURL.appendingPathComponent("incoming-\(UUID().uuidString).pdf")
        do {
            try FileManager.default.copyItem(at: incomingURL, to: stagedURL)
            pendingImportURL = stagedURL
            pendingImportTitle = incomingURL.deletingPathExtension().lastPathComponent
        } catch {
            importError = "Could not receive this PDF from the other app. Please try Share → Open in BookLand again."
        }
    }

    func completePendingImport() {
        guard let pendingImportURL else { return }
        let title = pendingImportTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        addStagedPDF(at: pendingImportURL, title: title.isEmpty ? "Untitled PDF" : title)
        self.pendingImportURL = nil
        pendingImportTitle = ""
    }

    func cancelPendingImport() {
        if let pendingImportURL { try? FileManager.default.removeItem(at: pendingImportURL) }
        pendingImportURL = nil
        pendingImportTitle = ""
    }

    @discardableResult
    func importPDF(from incomingURL: URL, preferredTitle: String? = nil) -> Bool {
        guard incomingURL.isFileURL else {
            importError = "BookLand received an invalid file location."
            return false
        }
        let accessed = incomingURL.startAccessingSecurityScopedResource()
        defer { if accessed { incomingURL.stopAccessingSecurityScopedResource() } }

        let trimmed = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmed.isEmpty ? incomingURL.deletingPathExtension().lastPathComponent : trimmed
        let fileName = "\(UUID().uuidString).pdf"
        do {
            try FileManager.default.copyItem(at: incomingURL, to: documentsURL.appendingPathComponent(fileName))
            addBook(title: title, fileName: fileName)
            return true
        } catch {
            importError = "Could not copy this PDF into BookLand. Please try Share → Save to Files first, then import it again."
            return false
        }
    }

    /// Downloads a PDF from a web link and adds it to the library.
    /// Returns a short error message for the user, or nil when the book was added.
    func addBook(fromLink text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https", parsed.host?.isEmpty == false else {
            return "That doesn’t look like a web link. Paste an address that starts with https://"
        }
        var request = URLRequest(url: Self.directDownloadURL(parsed), timeoutInterval: 60)
        request.setValue("application/pdf,*/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            let (temporary, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: temporary)
                return http.statusCode == 401 || http.statusCode == 403
                    ? "That link needs you to sign in, so BookLand can’t download it. Save the PDF to Files and import it from there."
                    : "The website answered with an error (\(http.statusCode)). Check the link and try again."
            }
            // A real PDF starts with %PDF; web pages and sign-in screens don't.
            let head = (try? FileHandle(forReadingFrom: temporary).read(upToCount: 1024)) ?? Data()
            guard head.range(of: Data("%PDF".utf8)) != nil else {
                try? FileManager.default.removeItem(at: temporary)
                return "That link didn’t give a PDF. It may open a web page, or need you to sign in."
            }
            let fileName = "\(UUID().uuidString).pdf"
            let destination = documentsURL.appendingPathComponent(fileName)
            try FileManager.default.moveItem(at: temporary, to: destination)
            let embedded = (PDFDocument(url: destination)?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let suggested = ((response.suggestedFilename ?? "") as NSString).deletingPathExtension
            let title = !embedded.isEmpty ? embedded : (!suggested.isEmpty && suggested != "Unknown" ? suggested : (parsed.host ?? "Downloaded PDF"))
            addBook(title: title, fileName: fileName)
            return nil
        } catch let error as URLError {
            switch error.code {
            case .cancelled: return ""
            case .appTransportSecurityRequiresSecureConnection: return "iPhone blocks plain http links. Try the https:// version of the address."
            case .notConnectedToInternet, .networkConnectionLost: return "No internet connection. Try again when you are online."
            case .timedOut: return "The download took too long. Try again."
            default: return "Couldn’t download that link (\(error.localizedDescription))."
            }
        } catch is CancellationError {
            return ""
        } catch {
            return "Couldn’t save the downloaded PDF. Check that your iPhone has free space."
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

    private func addStagedPDF(at sourceURL: URL, title: String) {
        let fileName = "\(UUID().uuidString).pdf"
        do {
            try FileManager.default.moveItem(at: sourceURL, to: documentsURL.appendingPathComponent(fileName))
            addBook(title: title, fileName: fileName)
        } catch {
            importError = "Could not copy this PDF into BookLand. Please try Share → Open in BookLand again."
            try? FileManager.default.removeItem(at: sourceURL)
        }
    }

    private func addBook(title: String, fileName: String) {
        let count = PDFDocument(url: documentsURL.appendingPathComponent(fileName))?.pageCount
        books.insert(IOSLibraryBook(title: title, fileName: fileName, pageCount: count), at: 0)
        lastAddedTitle = title
        save()
    }

    // MARK: Editing

    func removeBook(_ book: IOSLibraryBook) {
        books.removeAll { $0.id == book.id }
        try? FileManager.default.removeItem(at: book.fileURL)
        save()
    }

    func rename(_ book: IOSLibraryBook, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].title = trimmed
        save()
    }

    func setTags(_ tags: [String], for book: IOSLibraryBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].tags = tags
        save()
    }

    func markOpened(_ book: IOSLibraryBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].lastOpenedAt = .now
        save()
    }

    func updatePage(_ page: Int, for book: IOSLibraryBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        let clamped = max(1, page)
        guard books[index].lastPage != clamped else { return }
        books[index].lastPage = clamped
        save()
    }

    func setPageCount(_ count: Int, for book: IOSLibraryBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }), books[index].pageCount != count else { return }
        books[index].pageCount = count
        save()
    }

    func addNote(_ note: IOSLibraryNote, to book: IOSLibraryBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].notes.insert(note, at: 0)
        save()
    }

    func deleteNote(_ note: IOSLibraryNote, from book: IOSLibraryBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].notes.removeAll { $0.id == note.id }
        save()
    }

    // MARK: Export

    /// Every highlight and note as Markdown, grouped by book — for the Notes tab's share button.
    func notesMarkdown() -> String {
        var out = "# BookLand notes\n"
        for book in books where !book.notes.isEmpty {
            out += "\n## \(book.title)\n"
            for note in book.notes.sorted(by: { $0.page < $1.page }) {
                if note.isHighlight {
                    out += "\n- p. \(note.page) — “\(note.text)”"
                } else {
                    out += "\n- p. \(note.page) — \(note.text)"
                    if let quote = note.quote, !quote.isEmpty { out += "\n  > \(quote)" }
                }
            }
            out += "\n"
        }
        return out
    }

    var storageBytes: Int64 {
        books.reduce(0) { total, book in
            let size = (try? FileManager.default.attributesOfItem(atPath: book.fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: metadataURL) {
            if let saved = try? JSONDecoder().decode([IOSLibraryBook].self, from: data) {
                books = saved.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
            } else {
                // Keep an unreadable file instead of overwriting it with an empty library.
                try? FileManager.default.copyItem(at: metadataURL, to: documentsURL.appendingPathComponent("library-unreadable.json"))
            }
        }
        recoverOrphanedPDFs()
        // Migrates a 0.1 library (absolute paths) to file names on first launch.
        save()
    }

    /// Any PDF sitting in Documents without a library entry (restored from a backup, or the
    /// library file was lost) is added back, so a re-signed install never "loses" books.
    private func recoverOrphanedPDFs() {
        let known = Set(books.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: documentsURL.path)) ?? []
        for name in files where name.lowercased().hasSuffix(".pdf") && !name.hasPrefix("incoming-") && !known.contains(name) {
            let base = (name as NSString).deletingPathExtension
            let title = UUID(uuidString: base) != nil ? "Recovered PDF" : base
            let count = PDFDocument(url: documentsURL.appendingPathComponent(name))?.pageCount
            books.append(IOSLibraryBook(title: title, fileName: name, pageCount: count))
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }
}

/// Cover thumbnails (first page), rendered off the main thread and cached.
enum IOSCoverCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for book: IOSLibraryBook) async -> UIImage? {
        let key = "\(book.id.uuidString)-\(book.fileName)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let url = book.fileURL
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 180, height: 240), for: .cropBox)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
