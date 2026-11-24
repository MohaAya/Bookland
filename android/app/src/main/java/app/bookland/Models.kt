package app.bookland

import androidx.compose.ui.graphics.Color

/** A PDF in the library. The file itself lives in filesDir/books/<id>.pdf */
data class Book(
    val id: String,
    val title: String,
    val tags: List<String> = emptyList(),
    val pageCount: Int,
    val lastPage: Int,          // 0-based
    val addedAt: Long,
    val lastOpened: Long,       // 0 = never opened
) {
    val progress: Float get() = if (pageCount > 1) (lastPage.toFloat() / (pageCount - 1)).coerceIn(0f, 1f) else 0f
}

enum class HighlightColor(val label: String, val color: Color) {
    Yellow("Yellow", Color(0xFFFFD60A)),
    Green("Green", Color(0xFF30D158)),
    Pink("Pink", Color(0xFFFF375F)),
    Blue("Blue", Color(0xFF0A84FF)),
}

/** Rectangles are fractions of the page (0..1) so they stay correct at any zoom or screen size. */
data class Rf(val l: Float, val t: Float, val r: Float, val b: Float)

enum class NoteKind(val label: String) {
    Highlight("Highlight"),   // drawn on the page
    Quote("Quote"),           // a passage saved to the notes without drawing on the page
    Note("Note"),             // your own text, optionally about a selected passage
}

data class Note(
    val id: String,
    val page: Int,            // 0-based
    val text: String,
    val kind: NoteKind,
    val quote: String? = null,
    val color: HighlightColor? = null,
    val rects: List<Rf> = emptyList(),
    val createdAt: Long,
) {
    val isHighlight get() = kind == NoteKind.Highlight
    val isQuote get() = kind == NoteKind.Quote
}

fun List<Note>.highlightCount() = count { it.isHighlight || it.isQuote }
fun List<Note>.noteCount() = count { it.kind == NoteKind.Note }

fun List<Note>.summary(): String? {
    val h = highlightCount()
    val n = noteCount()
    val parts = ArrayList<String>()
    if (h > 0) parts.add(if (h == 1) "1 highlight" else "$h highlights")
    if (n > 0) parts.add(if (n == 1) "1 note" else "$n notes")
    return if (parts.isEmpty()) null else parts.joinToString(" · ")
}

/** One passage ready to paste: the text, then where it came from. */
fun Book.citation(note: Note): String {
    val p = note.page + 1
    if (note.isHighlight || note.isQuote) return "“${note.text}” — $title, p. $p"
    var out = note.text
    if (!note.quote.isNullOrEmpty()) out += "\n> ${note.quote}"
    return "$out\n— $title, p. $p"
}

/** Several passages as Markdown, in page order, headed by the book title. */
fun Book.notesMarkdown(list: List<Note>): String {
    val sb = StringBuilder("# $title\n")
    list.sortedBy { it.page }.forEach { n ->
        val p = n.page + 1
        if (n.isHighlight || n.isQuote) sb.append("\n- p. $p — “${n.text}”")
        else {
            sb.append("\n- p. $p — ${n.text}")
            if (!n.quote.isNullOrEmpty()) sb.append("\n  > ${n.quote}")
        }
    }
    return sb.append("\n").toString()
}

enum class LibrarySort(val label: String) {
    Recent("Recently read"),
    Title("Title"),
    Added("Date added"),
}

enum class ReadingMode(val label: String) {
    PageTurn("Page turn"),
    Scroll("Vertical scroll"),
}

/**
 * Same paper themes as iOS. Light themes multiply the paper colour over the white page (ink stays black);
 * dark themes turn the page into the paper colour and the text white.
 */
enum class PaperTheme(
    val label: String,
    val paper: Color,
    val dark: Boolean,
    val sketchy: Boolean = false,
) {
    Milky("Milky paper", Color(0xFFF5F0DB), false),
    White("White", Color.White, false),
    Sepia("Sepia paper", Color(0xFFEBD6AD), false),
    Blue("Blue grey", Color(0xFFD1E6FA), false),
    Sage("Sage study", Color(0xFFDEEDDE), false),
    Sketchbook("Sketchbook", Color(0xFFF2EBD1), false, sketchy = true),
    Midnight("Midnight navy", Color(0xFF0E172E), true),
    Graphite("Graphite night", Color(0xFF1F242B), true),
    NightAmber("Amber night", Color(0xFF332617), true);

    val ink: Color get() = if (dark) Color.White else Color.Black
}
