package app.bookland

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Everything BookLand keeps on the phone: imported PDFs, covers, highlights and settings. */
class Store(private val context: Context) {
    private val booksDir = File(context.filesDir, "books").apply { mkdirs() }
    private val coversDir = File(context.filesDir, "covers").apply { mkdirs() }
    private val notesDir = File(context.filesDir, "annotations").apply { mkdirs() }
    private val indexFile = File(context.filesDir, "library.json")
    private val prefs = context.getSharedPreferences("bookland", Context.MODE_PRIVATE)

    fun pdfFile(id: String) = File(booksDir, "$id.pdf")
    fun coverFile(id: String) = File(coversDir, "$id.png")

    // ---- settings ----
    var theme: PaperTheme
        get() = runCatching { PaperTheme.valueOf(prefs.getString("theme", "Milky")!!) }.getOrDefault(PaperTheme.Milky)
        set(v) { prefs.edit().putString("theme", v.name).apply() }

    var mode: ReadingMode
        get() = runCatching { ReadingMode.valueOf(prefs.getString("mode", "PageTurn")!!) }.getOrDefault(ReadingMode.PageTurn)
        set(v) { prefs.edit().putString("mode", v.name).apply() }

    // ---- library ----
    fun loadBooks(): List<Book> {
        if (!indexFile.exists()) return emptyList()
        return runCatching {
            val arr = JSONArray(indexFile.readText())
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Book(
                    id = o.getString("id"),
                    title = o.getString("title"),
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
            })
        }
        indexFile.writeText(arr.toString())
    }

    /** Copies the PDF into app storage, reads its page count and renders a cover. Returns null if it isn't a readable PDF. */
    fun importPdf(uri: Uri): Book? {
        val id = UUID.randomUUID().toString()
        val dest = pdfFile(id)
        try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { input.copyTo(it) }
            } ?: return null
            val pages = pageCountOf(dest) ?: run { dest.delete(); return null }
            val now = System.currentTimeMillis()
            val book = Book(id, titleFor(uri), pages, 0, now, now)
            renderCover(book)
            return book
        } catch (e: Exception) {
            dest.delete()
            return null
        }
    }

    private fun titleFor(uri: Uri): String {
        var name: String? = null
        if (uri.scheme == "content") {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0)
            }
        }
        if (name == null) name = uri.lastPathSegment
        return (name ?: "Untitled").removeSuffix(".pdf").removeSuffix(".PDF").replace('_', ' ').trim().ifEmpty { "Untitled" }
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
    }

    // ---- highlights & notes ----
    fun loadHighlights(bookId: String): List<Highlight> {
        val f = File(notesDir, "$bookId.json")
        if (!f.exists()) return emptyList()
        return runCatching {
            val arr = JSONArray(f.readText())
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                val rs = o.getJSONArray("rects")
                Highlight(
                    id = o.getString("id"),
                    page = o.getInt("page"),
                    rects = (0 until rs.length()).map { j ->
                        val r = rs.getJSONArray(j)
                        Rf(r.getDouble(0).toFloat(), r.getDouble(1).toFloat(), r.getDouble(2).toFloat(), r.getDouble(3).toFloat())
                    },
                    color = runCatching { HighlightColor.valueOf(o.getString("color")) }.getOrDefault(HighlightColor.Yellow),
                    text = o.optString("text"),
                    note = o.optString("note"),
                    createdAt = o.optLong("createdAt"),
                )
            }
        }.getOrDefault(emptyList())
    }

    fun saveHighlights(bookId: String, list: List<Highlight>) {
        val arr = JSONArray()
        list.forEach { h ->
            arr.put(JSONObject().apply {
                put("id", h.id); put("page", h.page); put("color", h.color.name)
                put("text", h.text); put("note", h.note); put("createdAt", h.createdAt)
                put("rects", JSONArray().apply {
                    h.rects.forEach { r -> put(JSONArray().put(r.l.toDouble()).put(r.t.toDouble()).put(r.r.toDouble()).put(r.b.toDouble())) }
                })
            })
        }
        File(notesDir, "$bookId.json").writeText(arr.toString())
    }
}
