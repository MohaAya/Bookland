package app.bookland

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color as AColor
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.LruCache
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** One character on a page. Coordinates are fractions of the page (0..1, origin top-left). */
class PChar(val s: String, val l: Float, val t: Float, val r: Float, val b: Float, val sep: Boolean)

class PageText(val chars: List<PChar>, val wPts: Float, val hPts: Float) {
    /** Flat string used for searching, plus a map from string index back to character index. */
    val flat: String
    private val flatToChar: IntArray

    init {
        val sb = StringBuilder()
        val map = ArrayList<Int>()
        chars.forEachIndexed { i, c -> for (k in c.s.indices) { sb.append(c.s[k]); map.add(i) } }
        flat = sb.toString()
        flatToChar = map.toIntArray()
    }

    fun charAtFlat(i: Int): Int = flatToChar[i.coerceIn(0, max(0, flatToChar.size - 1))]

    /** Nearest real character to a point (fractions), or -1 if none is within maxPts points. */
    fun indexAt(fx: Float, fy: Float, maxPts: Float = 28f): Int {
        val px = fx * wPts
        val py = fy * hPts
        var best = -1
        var bd = Float.MAX_VALUE
        for (i in chars.indices) {
            val c = chars[i]
            if (c.sep) continue
            val dx = max(max(c.l * wPts - px, px - c.r * wPts), 0f)
            val dy = max(max(c.t * hPts - py, py - c.b * hPts), 0f)
            val d = dx * dx + dy * dy
            if (d < bd) { bd = d; best = i }
        }
        return if (best >= 0 && bd <= maxPts * maxPts) best else -1
    }

    /** The word around a character, without surrounding punctuation. */
    fun wordRange(i: Int): IntRange {
        var a = i
        var b = i
        while (a > 0 && !chars[a - 1].sep) a--
        while (b < chars.size - 1 && !chars[b + 1].sep) b++
        while (a < b && !chars[a].s.first().isLetterOrDigit()) a++
        while (b > a && !chars[b].s.last().isLetterOrDigit()) b--
        return a..b
    }

    fun rectsFor(a: Int, b: Int): List<Rf> {
        val out = ArrayList<Rf>()
        var cur: FloatArray? = null
        var curMid = 0f
        for (i in a..b) {
            val c = chars.getOrNull(i) ?: continue
            if (c.sep) continue
            val mid = (c.t + c.b) / 2
            val h = c.b - c.t
            val line = cur
            if (line != null && abs(mid - curMid) < h * 0.6f) {
                line[0] = min(line[0], c.l); line[1] = min(line[1], c.t)
                line[2] = max(line[2], c.r); line[3] = max(line[3], c.b)
            } else {
                if (line != null) out.add(Rf(line[0], line[1], line[2], line[3]))
                cur = floatArrayOf(c.l, c.t, c.r, c.b)
                curMid = mid
            }
        }
        cur?.let { out.add(Rf(it[0], it[1], it[2], it[3])) }
        return out
    }

    fun stringFor(a: Int, b: Int): String {
        val sb = StringBuilder()
        for (i in a..b) chars.getOrNull(i)?.let { sb.append(it.s) }
        return sb.toString().replace(Regex("\\s+"), " ").trim()
    }
}

data class SearchHit(val page: Int, val rects: List<Rf>, val snippet: String)

private class Collector(val pw: Float, val ph: Float) : PDFTextStripper() {
    val out = ArrayList<PChar>()
    private fun sepChar() = PChar(" ", 0f, 0f, 0f, 0f, true)

    override fun writeString(text: String, textPositions: MutableList<TextPosition>) {
        for (tp in textPositions) {
            val u = tp.unicode ?: continue
            if (u.isBlank()) { if (out.lastOrNull()?.sep == false) out.add(sepChar()); continue }
            val fs = (if (tp.fontSizeInPt > 0f) tp.fontSizeInPt else tp.heightDir).coerceAtLeast(1f)
            val x = tp.xDirAdj
            val y = tp.yDirAdj
            val w = tp.widthDirAdj
            out.add(PChar(
                u,
                (x / pw).coerceIn(0f, 1f),
                ((y - fs * 0.82f) / ph).coerceIn(0f, 1f),
                ((x + w) / pw).coerceIn(0f, 1f),
                ((y + fs * 0.22f) / ph).coerceIn(0f, 1f),
                false,
            ))
        }
    }

    override fun writeWordSeparator() { out.add(sepChar()) }
    override fun writeLineSeparator() { out.add(sepChar()) }
    override fun writeParagraphSeparator() { out.add(sepChar()) }
}

/** Opens a PDF for reading: Android's PdfRenderer draws pages, PDFBox supplies text positions. */
class PdfSession private constructor(
    private val appContext: Context,
    private val file: File,
    private val fd: ParcelFileDescriptor,
    private val renderer: PdfRenderer,
) {
    val pageCount: Int = renderer.pageCount
    var sizes: List<Pair<Float, Float>> = emptyList()
        private set

    private val renderLock = Mutex()
    private val textLock = Mutex()
    private val textCache = HashMap<Int, PageText>()
    private var doc: PDDocument? = null

    private val bitmaps = object : LruCache<String, Bitmap>(96 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }

    companion object {
        suspend fun open(context: Context, file: File): PdfSession? = withContext(Dispatchers.IO) {
            runCatching {
                val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                try {
                    PdfSession(context.applicationContext, file, fd, PdfRenderer(fd))
                } catch (e: Exception) { fd.close(); throw e }
            }.getOrNull()
        }
    }

    suspend fun loadSizes() = withContext(Dispatchers.IO) {
        renderLock.withLock {
            sizes = List(pageCount) { i -> renderer.openPage(i).use { it.width.toFloat() to it.height.toFloat() } }
        }
    }

    fun cached(page: Int, widthPx: Int): Bitmap? = bitmaps.get("$page@$widthPx")

    suspend fun render(page: Int, widthPx: Int): Bitmap {
        cached(page, widthPx)?.let { return it }
        return withContext(Dispatchers.IO) {
            renderLock.withLock {
                ensureActive() // the page may have scrolled away while waiting
                cached(page, widthPx)?.let { return@withLock it }
                renderer.openPage(page).use { p ->
                    val h = (widthPx * p.height / p.width.toFloat()).roundToInt().coerceAtLeast(1)
                    val bmp = Bitmap.createBitmap(widthPx, h, Bitmap.Config.ARGB_8888)
                    bmp.eraseColor(AColor.WHITE)
                    p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    bitmaps.put("$page@$widthPx", bmp)
                    bmp
                }
            }
        }
    }

    suspend fun text(page: Int): PageText = withContext(Dispatchers.IO) {
        textLock.withLock {
            textCache[page]?.let { return@withLock it }
            val (w, h) = sizes.getOrNull(page) ?: (612f to 792f)
            val pt = try {
                PdfBoxInit.ensure(appContext)
                val d = doc ?: PDDocument.load(file, MemoryUsageSetting.setupTempFileOnly()).also { doc = it }
                val c = Collector(w, h)
                c.setStartPage(page + 1)
                c.setEndPage(page + 1)
                c.getText(d)
                PageText(c.out, w, h)
            } catch (e: Throwable) {
                PageText(emptyList(), w, h)
            }
            textCache[page] = pt
            pt
        }
    }

    suspend fun search(query: String, limit: Int = 400, onHit: (SearchHit) -> Unit) {
        val q = query.trim()
        if (q.isEmpty()) return
        var found = 0
        for (p in 0 until pageCount) {
            val pt = text(p)
            var from = 0
            while (true) {
                val i = pt.flat.indexOf(q, from, ignoreCase = true)
                if (i < 0) break
                val a = pt.charAtFlat(i)
                val b = pt.charAtFlat(i + q.length - 1)
                val s0 = (i - 36).coerceAtLeast(0)
                val s1 = (i + q.length + 56).coerceAtMost(pt.flat.length)
                onHit(SearchHit(p, pt.rectsFor(a, b), pt.flat.substring(s0, s1).replace(Regex("\\s+"), " ").trim()))
                found++
                from = i + max(1, q.length)
                if (found >= limit) return
            }
        }
    }

    suspend fun close() = withContext(Dispatchers.IO) {
        renderLock.withLock {
            textLock.withLock {
                runCatching { doc?.close() }
                runCatching { renderer.close() }
                runCatching { fd.close() }
                bitmaps.evictAll()
            }
        }
    }
}
