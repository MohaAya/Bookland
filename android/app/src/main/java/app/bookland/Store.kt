package app.bookland

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import java.util.UUID

/** Everything BookLand keeps on the phone: imported PDFs, covers, highlights and notes, and settings. */
class Store(private val context: Context) {
    private val booksDir = File(context.filesDir, "books").apply { mkdirs() }
    private val coversDir = File(context.filesDir, "covers").apply { mkdirs() }
    private val notesDir = File(context.filesDir, "annotations").apply { mkdirs() }
    private val indexFile = File(context.filesDir, "library.json")
    private val prefs = context.getSharedPreferences("bookland", Context.MODE_PRIVATE)

    fun pdfFile(id: String) = File(booksDir, "$id.pdf")
    fun coverFile(id: String) = File(coversDir, "$id.png")

    // ---- settings (observable, so every screen follows a change at once) ----
    private var themeState by mutableStateOf(
        runCatching { PaperTheme.valueOf(prefs.getString("theme", "Milky")!!) }.getOrDefault(PaperTheme.Milky)
    )
    var theme: PaperTheme
        get() = themeState
        set(v) { themeState = v; prefs.edit().putString("theme", v.name).apply() }

    private var modeState by mutableStateOf(
        runCatching { ReadingMode.valueOf(prefs.getString("mode", "PageTurn")!!) }.getOrDefault(ReadingMode.PageTurn)
    )
    var mode: ReadingMode
        get() = modeState
        set(v) { modeState = v; prefs.edit().putString("mode", v.name).apply() }

    private var keepAwakeState by mutableStateOf(prefs.getBoolean("keepAwake", true))
    var keepAwake: Boolean
        get() = keepAwakeState
        set(v) { keepAwakeState = v; prefs.edit().putBoolean("keepAwake", v).apply() }

    private var sortState by mutableStateOf(
        runCatching { LibrarySort.valueOf(prefs.getString("sort", "Recent")!!) }.getOrDefault(LibrarySort.Recent)
    )
    var sort: LibrarySort
        get() = sortState
        set(v) { sortState = v; prefs.edit().putString("sort", v.name).apply() }

    // ---- library ----
    fun loadBooks(): List<Book> {
        if (!indexFile.exists()) return emptyList()
        return runCatching {
            val arr = JSONArray(indexFile.readText())
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                val tags = o.optJSONArray("tags")
                Book(
                    id = o.getString("id"),
                    title = o.getString("title"),
                    tags = if (tags == null) emptyList() else (0 until tags.length()).map { tags.getString(it) },
                    pageCount = o.optInt("pageCount", 1),
                    lastPage = o.optInt("lastPage", 0),
                    addedAt = o.optLong("addedAt"),
                    lastOpened = o.optLong("lastOpened"),
                )
            }.filter { pdfFile(it.id).exists() }
        }.getOrDefault(emptyList())
    }

    fun saveBooks(books: List<Book>) {
        val arr = JSONArray()
        books.forEach { b ->
            arr.put(JSONObject().apply {
                put("id", b.id); put("title", b.title); put("pageCount", b.pageCount)
                put("lastPage", b.lastPage); put("addedAt", b.addedAt); put("lastOpened", b.lastOpened)
                put("tags", JSONArray().apply { b.tags.forEach { put(it) } })
            })
        }
        indexFile.writeText(arr.toString())
    }

    fun storageBytes(books: List<Book>): Long = books.sumOf { pdfFile(it.id).length() }

    /** Suggested title for a file the user picked or opened from another app. */
    fun titleFor(uri: Uri): String {
        var name: String? = null
        if (uri.scheme == "content") {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0)
            }
        }
        if (name == null) name = uri.lastPathSegment
        return cleanTitle(name ?: "Untitled")
    }

    private fun cleanTitle(raw: String) =
        raw.removeSuffix(".pdf").removeSuffix(".PDF").replace('_', ' ').trim().ifEmpty { "Untitled" }

    /** Copies the PDF into app storage, reads its page count and renders a cover. Returns null if it isn't a readable PDF. */
    fun importPdf(uri: Uri, title: String? = null): Book? {
        val id = UUID.randomUUID().toString()
        val dest = pdfFile(id)
        try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { input.copyTo(it) }
            } ?: return null
            val pages = pageCountOf(dest) ?: run { dest.delete(); return null }
            val now = System.currentTimeMillis()
            val book = Book(id, (title ?: titleFor(uri)).trim().ifEmpty { "Untitled" }, emptyList(), pages, 0, now, 0)
            renderCover(book)
            return book
        } catch (e: Exception) {
            dest.delete()
            return null
        }
    }

    /** Turns common "share" links into direct file downloads (Dropbox, Google Drive). */
    fun directDownloadUrl(link: URL): URL {
        val host = link.host.lowercase()
        if (host.endsWith("dropbox.com")) {
            val base = link.toString().substringBefore('#')
            val cleaned = base.replace(Regex("([?&])dl=[^&]*&?"), "$1").trimEnd('?', '&')
            return URL(cleaned + (if (cleaned.contains('?')) "&" else "?") + "dl=1")
        }
        if (host == "drive.google.com") {
            val parts = link.path.split('/')
            val i = parts.indexOf("d")
            if (i >= 0 && parts.size > i + 1) return URL("https://drive.google.com/uc?export=download&id=${parts[i + 1]}")
        }
        return link
    }

    /** Downloads a PDF from a web link and adds it to the library. Throws IOException with a readable message. Call off the main thread. */
    fun importUrl(raw: String, onProgress: (Float) -> Unit = {}): Book {
        var link = raw.trim()
        if (link.isEmpty()) throw IOException("Paste a link to a PDF first.")
        if (!link.startsWith("http://", true) && !link.startsWith("https://", true)) link = "https://$link"
        val first = try { URL(link) } catch (e: Exception) { throw IOException("That doesn’t look like a web link. Paste an address that starts with https://") }
        if (first.host.isNullOrEmpty()) throw IOException("That doesn’t look like a web link. Paste an address that starts with https://")
        val id = UUID.randomUUID().toString()
        val dest = pdfFile(id)
        try {
            var target = directDownloadUrl(first)
            var conn: HttpURLConnection
            var hops = 0
            while (true) {
                conn = (target.openConnection() as HttpURLConnection).apply {
                    instanceFollowRedirects = false
                    connectTimeout = 20000
                    readTimeout = 30000
                    setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) BookLand")
                    setRequestProperty("Accept", "application/pdf,*/*;q=0.8")
                }
                val code = conn.responseCode
                if (code in 300..399 && hops < 8) {
                    val loc = conn.getHeaderField("Location") ?: throw IOException("The link redirects to nowhere.")
                    target = URL(target, loc)
                    conn.disconnect()
                    hops++
                    continue
                }
                if (code == 401 || code == 403) throw IOException("That link needs you to sign in, so BookLand can’t download it. Save the PDF to Files and import it from there.")
                if (code !in 200..299) throw IOException("The website answered with an error ($code). Check the link and try again.")
                break
            }
            val total = conn.contentLengthLong
            conn.inputStream.use { input ->
                dest.outputStream().use { out ->
                    val buf = ByteArray(64 * 1024)
                    var done = 0L
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        done += n
                        if (total > 0) onProgress((done / total.toFloat()).coerceIn(0f, 1f))
                    }
                }
            }
            val head = ByteArray(1024)
            val n = dest.inputStream().use { it.read(head) }
            if (n <= 0 || String(head, 0, n, Charsets.ISO_8859_1).indexOf("%PDF") < 0) {
                throw IOException("That link didn’t give a PDF. It may open a web page, or need you to sign in.")
            }
            val pages = pageCountOf(dest) ?: throw IOException("The PDF could not be read (it may be password protected).")
            val now = System.currentTimeMillis()
            val book = Book(id, titleFromLink(first, conn.getHeaderField("Content-Disposition")), emptyList(), pages, 0, now, 0)
            renderCover(book)
            return book
        } catch (e: Exception) {
            dest.delete()
            throw when (e) {
                is IOException -> if (e is java.net.UnknownHostException || e is java.net.ConnectException)
                    IOException("No internet connection, or the address doesn’t exist.") else if (e is java.net.SocketTimeoutException)
                    IOException("The download took too long. Try again.") else e
                else -> IOException(e.message ?: "Download failed.")
            }
        }
    }

    private fun titleFromLink(url: URL, disposition: String?): String {
        var name: String? = null
        if (disposition != null) {
            Regex("filename\\*?=(?:UTF-8'')?\"?([^\";]+)\"?", RegexOption.IGNORE_CASE).find(disposition)?.let {
                name = runCatching { URLDecoder.decode(it.groupValues[1], "UTF-8") }.getOrDefault(it.groupValues[1])
            }
        }
        if (name.isNullOrBlank()) {
            name = url.path.substringAfterLast('/').let { runCatching { URLDecoder.decode(it, "UTF-8") }.getOrDefault(it) }
        }
        if (name.isNullOrBlank()) name = url.host
        return cleanTitle(name!!.replace('-', ' '))
    }

    private fun pageCountOf(file: File): Int? = runCatching {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { it.pageCount }
        }
    }.getOrNull()

    private fun renderCover(book: Book) {
        runCatching {
            ParcelFileDescriptor.open(pdfFile(book.id), ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { r ->
                    r.openPage(0).use { p ->
                        val w = 420
                        val h = (w * p.height / p.width.toFloat()).toInt().coerceAtLeast(1)
                        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                        bmp.eraseColor(android.graphics.Color.WHITE)
                        p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        coverFile(book.id).outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 90, it) }
                        bmp.recycle()
                    }
                }
            }
        }
    }

    fun delete(book: Book) {
        pdfFile(book.id).delete(); coverFile(book.id).delete(); File(notesDir, "${book.id}.json").delete()
        noteCache.remove(book.id)
    }

    // ---- highlights, saved passages and notes: one shared observable list per book ----
    private val noteCache = HashMap<String, SnapshotStateList<Note>>()

    fun notes(bookId: String): SnapshotStateList<Note> = noteCache.getOrPut(bookId) {
        mutableStateListOf<Note>().also { it.addAll(readNotes(bookId)) }
    }

    fun saveNotes(bookId: String) {
        val list = notes(bookId).toList()
        val arr = JSONArray()
        list.forEach { n ->
            arr.put(JSONObject().apply {
                put("id", n.id); put("page", n.page); put("kind", n.kind.name)
                put("text", n.text); put("createdAt", n.createdAt)
                n.quote?.let { put("quote", it) }
                n.color?.let { put("color", it.name) }
                put("rects", JSONArray().apply {
                    n.rects.forEach { r -> put(JSONArray().put(r.l.toDouble()).put(r.t.toDouble()).put(r.r.toDouble()).put(r.b.toDouble())) }
                })
            })
        }
        File(notesDir, "$bookId.json").writeText(arr.toString())
    }

    private fun readNotes(bookId: String): List<Note> {
        val f = File(notesDir, "$bookId.json")
        if (!f.exists()) return emptyList()
        return runCatching {
            val arr = JSONArray(f.readText())
            val out = ArrayList<Note>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val rs = o.optJSONArray("rects")
                val rects = if (rs == null) emptyList() else (0 until rs.length()).map { j ->
                    val r = rs.getJSONArray(j)
                    Rf(r.getDouble(0).toFloat(), r.getDouble(1).toFloat(), r.getDouble(2).toFloat(), r.getDouble(3).toFloat())
                }
                val color = o.optString("color").takeIf { it.isNotEmpty() }?.let { c -> runCatching { HighlightColor.valueOf(c) }.getOrNull() }
                val kind = runCatching { NoteKind.valueOf(o.optString("kind", "Highlight")) }.getOrDefault(NoteKind.Highlight)
                val created = o.optLong("createdAt")
                out.add(Note(o.getString("id"), o.getInt("page"), o.optString("text"), kind,
                    o.optString("quote").takeIf { it.isNotEmpty() }, color ?: if (kind == NoteKind.Highlight) HighlightColor.Yellow else null, rects, created))
                // Version 0.1 stored a note inside the highlight; keep it as its own note.
                val old = o.optString("note")
                if (kind == NoteKind.Highlight && old.isNotBlank()) {
                    out.add(Note(UUID.randomUUID().toString(), o.getInt("page"), old, NoteKind.Note, o.optString("text"), null, emptyList(), created))
                }
            }
            out
        }.getOrDefault(emptyList())
    }

    fun allNotesMarkdown(books: List<Book>): String =
        books.filter { notes(it.id).isNotEmpty() }.joinToString("\n") { it.notesMarkdown(notes(it.id)) }
}
