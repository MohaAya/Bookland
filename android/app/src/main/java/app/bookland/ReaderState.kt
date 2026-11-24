package app.bookland

import android.content.Context
import android.widget.Toast
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.math.max

data class Selection(val page: Int, val from: Int, val to: Int)
data class NoteDraft(val page: Int, val quote: String)

enum class Sheet { Search, Notes, Browser, History, Jump, Theme }

/** Everything about one open book: the PDF, current page, selection, search, history and notes. */
@Stable
class ReaderState(
    val book: Book,
    val store: Store,
    private val ctx: Context,
    private val scope: CoroutineScope,
    startPage: Int,
    private val onProgress: (Int) -> Unit,
) {
    var session by mutableStateOf<PdfSession?>(null)
        private set
    var failed by mutableStateOf(false)
        private set
    private var opened: PdfSession? = null

    val notes = store.notes(book.id)

    var page by mutableIntStateOf(startPage.coerceIn(0, max(0, book.pageCount - 1)))
    var jump by mutableStateOf<Int?>(null)
    var zoom by mutableFloatStateOf(1f)
    var selection by mutableStateOf<Selection?>(null)
    var sheet by mutableStateOf<Sheet?>(null)
    var noteDraft by mutableStateOf<NoteDraft?>(null)
    var editingNoteId by mutableStateOf<String?>(null)
    var translating by mutableStateOf<String?>(null)

    val history = mutableStateListOf(page)
    var historyIndex by mutableIntStateOf(0)

    var query by mutableStateOf("")
    val matches = mutableStateListOf<SearchHit>()
    var matchIndex by mutableIntStateOf(-1)
    var searching by mutableStateOf(false)
        private set
    private var searchJob: Job? = null
    private var progressJob: Job? = null
    private var lastHighlightId: String? = null

    val pageCount: Int get() = session?.pageCount ?: book.pageCount

    fun toast(msg: String) = Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()

    suspend fun open() {
        val s = PdfSession.open(ctx, store.pdfFile(book.id))
        if (s == null) { failed = true; return }
        opened = s
        s.loadSizes()
        session = s
        scope.launch { s.text(page) } // warm up text extraction so the first selection is instant
    }

    fun close() {
        progressJob?.cancel()
        searchJob?.cancel()
        onProgress(page)
        val s = opened
        opened = null
        if (s != null) CoroutineScope(Dispatchers.IO).launch { s.close() }
    }

    // ---- navigation ----
    /** Called when the user flips or scrolls to another page. */
    fun onPageChanged(p: Int) {
        if (p == page) return
        page = p
        if (selection != null && selection?.page != p) selection = null
        scheduleProgress()
    }

    private fun scheduleProgress() {
        progressJob?.cancel()
        progressJob = scope.launch { delay(500); onProgress(page) }
    }

    fun goTo(p: Int, record: Boolean = true) {
        val t = p.coerceIn(0, max(0, pageCount - 1))
        page = t
        jump = t
        if (record) recordVisit(t)
        scheduleProgress()
    }

    private fun recordVisit(t: Int) {
        while (history.size > historyIndex + 1) history.removeAt(history.lastIndex)
        if (history.last() != t) history.add(t)
        historyIndex = history.lastIndex
    }

    fun goToHistory(i: Int) {
        if (i !in history.indices) return
        historyIndex = i
        goTo(history[i], record = false)
    }

    private val zoomSteps = listOf(1f, 1.25f, 1.5f, 2f, 3f)
    fun zoomIn() { zoomSteps.firstOrNull { it > zoom + 0.01f }?.let { zoom = it } }
    fun zoomOut() { zoomSteps.lastOrNull { it < zoom - 0.01f }?.let { zoom = it } }
    fun fit() { zoom = 1f }

    // ---- search ----
    fun runSearch(q: String) {
        val s = session ?: return
        searchJob?.cancel()
        matches.clear(); matchIndex = -1
        if (q.isBlank()) { searching = false; return }
        searching = true
        searchJob = scope.launch {
            try { s.search(q) { matches.add(it) } } finally { searching = false }
        }
    }

    fun clearSearch() {
        searchJob?.cancel(); matches.clear(); matchIndex = -1; searching = false; query = ""
    }

    fun stepMatch(delta: Int) {
        if (matches.isEmpty()) return
        val n = if (matchIndex < 0) (if (delta > 0) 0 else matches.size - 1) else (matchIndex + delta + matches.size) % matches.size
        matchIndex = n
        goTo(matches[n].page)
    }

    // ---- highlights, saved passages and notes ----
    private fun persist() = store.saveNotes(book.id)

    fun addHighlight(color: HighlightColor) {
        val sel = selection ?: return
        val s = session ?: return
        scope.launch {
            val pt = s.text(sel.page)
            val rects = pt.rectsFor(sel.from, sel.to)
            if (rects.isEmpty()) return@launch
            val n = Note(UUID.randomUUID().toString(), sel.page, pt.stringFor(sel.from, sel.to), NoteKind.Highlight, null, color, rects, System.currentTimeMillis())
            notes.add(n)
            lastHighlightId = n.id
            persist()
            selection = null
        }
    }

    fun saveSelectionAsQuote() {
        val sel = selection ?: return
        val s = session ?: return
        scope.launch {
            val text = s.text(sel.page).stringFor(sel.from, sel.to)
            if (text.isBlank()) return@launch
            notes.add(Note(UUID.randomUUID().toString(), sel.page, text, NoteKind.Quote, null, null, emptyList(), System.currentTimeMillis()))
            persist()
            selection = null
            toast("Saved to notes")
        }
    }

    fun startNoteFromSelection() {
        val sel = selection
        val s = session
        if (sel == null || s == null) { noteDraft = NoteDraft(page, ""); return }
        scope.launch {
            noteDraft = NoteDraft(sel.page, s.text(sel.page).stringFor(sel.from, sel.to))
            selection = null
        }
    }

    fun addNote(draft: NoteDraft, text: String) {
        if (text.isBlank()) return
        notes.add(Note(UUID.randomUUID().toString(), draft.page, text.trim(), NoteKind.Note, draft.quote.ifBlank { null }, null, emptyList(), System.currentTimeMillis()))
        persist()
    }

    fun deleteNote(id: String) { notes.removeAll { it.id == id }; persist() }

    fun updateNote(id: String, text: String, color: HighlightColor?) {
        val i = notes.indexOfFirst { it.id == id }
        if (i < 0) return
        notes[i] = notes[i].copy(text = text, color = color ?: notes[i].color)
        persist()
    }

    fun recolor(id: String, color: HighlightColor) {
        val i = notes.indexOfFirst { it.id == id }
        if (i >= 0) { notes[i] = notes[i].copy(color = color); persist() }
    }

    fun undoLastHighlight() {
        val id = lastHighlightId ?: notes.lastOrNull { it.isHighlight }?.id
        if (id == null) { toast("No highlight to undo."); return }
        notes.removeAll { it.id == id }
        lastHighlightId = null
        persist()
    }
}
