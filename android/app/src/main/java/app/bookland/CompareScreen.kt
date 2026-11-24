package app.bookland

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

val CompareIcon: ImageVector by lazy {
    ImageVector.Builder("Compare", 24.dp, 24.dp, 24f, 24f).path(fill = SolidColor(Color.Black)) {
        moveTo(3f, 4f); horizontalLineTo(11f); verticalLineTo(20f); horizontalLineTo(3f); close()
        moveTo(13f, 4f); horizontalLineTo(21f); verticalLineTo(20f); horizontalLineTo(13f); close()
    }.build()
}

/** Two books side by side (landscape) or stacked (portrait), each with its own page and controls. */
@Composable
fun CompareTab(
    books: List<Book>,
    store: Store,
    leftId: String?,
    rightId: String?,
    onChange: (String?, String?) -> Unit,
    onProgress: (String, Int) -> Unit,
) {
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 12.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Compare", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground, modifier = Modifier.weight(1f))
            TextButton(onClick = { onChange(rightId ?: books.getOrNull(1)?.id, leftId ?: books.firstOrNull()?.id) }, enabled = books.size >= 2) { Text("Swap") }
        }
        if (books.isEmpty()) {
            EmptyState("Import a PDF first", "Pick two books from your library and read them side by side.")
            return@Column
        }
        val left = books.firstOrNull { it.id == leftId } ?: books.first()
        val right = books.firstOrNull { it.id == rightId } ?: books.getOrNull(1) ?: books.first()
        BoxWithConstraints(Modifier.fillMaxSize().padding(horizontal = 8.dp, vertical = 4.dp)) {
            val side = maxWidth > maxHeight
            val a: @Composable (Modifier) -> Unit = { m ->
                ComparePane(if (side) "Left" else "Top", left, books, store, { onChange(it, right.id) }, { onProgress(left.id, it) }, m)
            }
            val b: @Composable (Modifier) -> Unit = { m ->
                ComparePane(if (side) "Right" else "Bottom", right, books, store, { onChange(left.id, it) }, { onProgress(right.id, it) }, m)
            }
            if (side) Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                a(Modifier.weight(1f).fillMaxSize()); b(Modifier.weight(1f).fillMaxSize())
            } else Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                a(Modifier.weight(1f).fillMaxWidth()); b(Modifier.weight(1f).fillMaxWidth())
            }
        }
    }
}

@Composable
private fun ComparePane(
    label: String,
    book: Book,
    books: List<Book>,
    store: Store,
    onSelect: (String) -> Unit,
    onProgress: (Int) -> Unit,
    modifier: Modifier,
) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val theme = store.theme
    val shape = RoundedCornerShape(16.dp)
    var bookMenu by remember { mutableStateOf(false) }
    var modeMenu by remember { mutableStateOf(false) }
    var showTheme by remember { mutableStateOf(false) }

    Column(modifier.clip(shape).background(theme.paper).border(0.5.dp, Color.Gray.copy(alpha = 0.4f), shape)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                TextButton(onClick = { bookMenu = true }) {
                    Text(book.title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold, color = theme.ink, fontSize = 14.sp, modifier = Modifier.weight(1f, fill = false))
                    Icon(Icons.Default.KeyboardArrowDown, "$label book", tint = theme.ink)
                }
                DropdownMenu(bookMenu, { bookMenu = false }) {
                    books.forEach { b ->
                        DropdownMenuItem(
                            text = { Text(b.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                            leadingIcon = { if (b.id == book.id) Icon(Icons.Default.Check, null) },
                            onClick = { bookMenu = false; onSelect(b.id) },
                        )
                    }
                }
            }
            Box {
                TextButton(onClick = { modeMenu = true }) { Text(store.mode.label, color = theme.ink, fontSize = 12.sp) }
                DropdownMenu(modeMenu, { modeMenu = false }) {
                    ReadingMode.values().forEach { m ->
                        DropdownMenuItem(
                            text = { Text(m.label) },
                            leadingIcon = { if (store.mode == m) Icon(Icons.Default.Check, null) },
                            onClick = { store.mode = m; modeMenu = false },
                        )
                    }
                }
            }
            TextButton(onClick = { showTheme = true }) { Text("Paper", color = theme.ink, fontSize = 12.sp) }
        }

        val state = remember(book.id) { ReaderState(book, store, ctx, scope, book.lastPage, onProgress) }
        LaunchedEffect(state) { state.open() }
        DisposableEffect(state) { onDispose { state.close() } }

        Box(Modifier.weight(1f).fillMaxWidth()) {
            ReaderPane(state, store, Modifier.fillMaxSize()) { }
            if (state.selection != null) SelectionBar(state, Modifier.align(Alignment.BottomCenter).padding(8.dp))
        }

        if (state.session != null) {
            val count = state.pageCount
            var dragging by remember(book.id) { mutableStateOf(false) }
            var sv by remember(book.id) { mutableStateOf(0f) }
            Column(Modifier.background(theme.paper)) {
                SearchStrip(state)
                Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { state.goTo(state.page - 1) }, enabled = state.page > 0) { Icon(Icons.Default.KeyboardArrowLeft, "Previous page", tint = theme.ink) }
                    TextButton(onClick = { state.sheet = Sheet.Jump }) {
                        Text("${(if (dragging) sv.roundToInt() else state.page) + 1}/$count", color = theme.ink, fontSize = 13.sp)
                    }
                    if (count > 1) Slider(
                        value = if (dragging) sv else state.page.toFloat(),
                        onValueChange = { dragging = true; sv = it; state.goTo(it.roundToInt(), record = false) },
                        onValueChangeFinished = { dragging = false; state.goTo(sv.roundToInt()) },
                        valueRange = 0f..(count - 1).toFloat(),
                        modifier = Modifier.weight(1f),
                    ) else Box(Modifier.weight(1f))
                    IconButton(onClick = { state.goTo(state.page + 1) }, enabled = state.page < count - 1) { Icon(Icons.Default.KeyboardArrowRight, "Next page", tint = theme.ink) }
                    IconButton(onClick = { state.sheet = Sheet.Search }) { Icon(Icons.Default.Search, "Search", tint = theme.ink) }
                    IconButton(onClick = { state.sheet = Sheet.Browser }) { Icon(Icons.Default.Menu, "Pages and index", tint = theme.ink) }
                }
            }
        }
        ReaderSheets(state, store)
        if (showTheme) ThemeDialog(store) { showTheme = false }
    }
}
