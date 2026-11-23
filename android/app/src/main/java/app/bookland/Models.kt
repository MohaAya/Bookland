package app.bookland

import androidx.compose.ui.graphics.Color

/** A PDF in the library. The file itself lives in filesDir/books/<id>.pdf */
data class Book(
    val id: String,
    val title: String,
    val pageCount: Int,
    val lastPage: Int,          // 0-based
    val addedAt: Long,
    val lastOpened: Long,
)

enum class HighlightColor(val label: String, val color: Color) {
    Yellow("Yellow", Color(0xFFFFD60A)),
    Green("Green", Color(0xFF30D158)),
    Pink("Pink", Color(0xFFFF375F)),
    Blue("Blue", Color(0xFF0A84FF)),
}

/** Rectangles are fractions of the page (0..1) so they stay correct at any zoom or screen size. */
data class Rf(val l: Float, val t: Float, val r: Float, val b: Float)

data class Highlight(
    val id: String,
    val page: Int,              // 0-based
    val rects: List<Rf>,
    val color: HighlightColor,
    val text: String,
    val note: String,
    val createdAt: Long,
)

enum class ReadingMode(val label: String) {
    PageTurn("Page turn"),
    Scroll("Vertical scroll"),
}

/** Same paper themes as the iOS app. Dark themes flip ink and paper. */
enum class PaperTheme(
    val label: String,
    val paper: Color,
    val ink: Color,
    val dark: Boolean,
) {
    Milky("Milky paper", Color(0xFFF5F0DB), Color(0xFF14202E), false),
    White("White", Color.White, Color.Black, false),
    Sepia("Sepia paper", Color(0xFFEBD6AD), Color(0xFF3B2A14), false),
    Blue("Blue grey", Color(0xFFD1E6FA), Color(0xFF12202E), false),
    Sage("Sage study", Color(0xFFDEEDDE), Color(0xFF1B2A1B), false),
    Sketchbook("Sketchbook", Color(0xFFF2EBD1), Color(0xFF2B2620), false),
    Midnight("Midnight navy", Color(0xFF0E172E), Color(0xFFC9D6F0), true),
    Graphite("Graphite night", Color(0xFF1F242B), Color(0xFFD5DAE0), true),
    NightAmber("Amber night", Color(0xFF332617), Color(0xFFE8C894), true),
}
