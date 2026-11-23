package app.bookland

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Create
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.text.KeyboardOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt

data class Selection(val page: Int, val from: Int, val to: Int)

private val ZoomSteps = listOf(1f, 1.25f, 1.5f, 2f, 3f)

private fun themeMatrix(t: PaperTheme): ColorMatrix {
    val p = t.paper
    val i = t.ink
    return ColorMatrix(
        floatArrayOf(
            p.red - i.red, 0f, 0f, 0f, i.red * 255f,
            0f, p.green - i.green, 0f, 0f, i.green * 255f,
            0f, 0f, p.blue - i.blue, 0f, i.blue * 255f,
            0f, 0f, 0f, 1f, 0f,
        )
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(book: Book, store: Store, onBack: () -> Unit, onProgress: (Int) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val view = LocalView.current

    var session by remember { mutableStateOf<PdfSession?>(null) }
    var failed by remember { mutableStateOf(false) }
    val holder = remember { arrayOfNulls<PdfSession>(1) }

    var theme by remember { mutableStateOf(store.theme) }
    var mode by remember { mutableStateOf(store.mode) }
    var zoom by remember { mutableFloatStateOf(1f) }
    var page by remember { mutableIntStateOf(book.lastPage.coerceIn(0, (book.pageCount - 1).coerceAtLeast(0))) }
    var jump by remember { mutableStateOf<Int?>(null) }
    var chrome by remember { mutableStateOf(true) }

    val highlights = remember { mutableStateListOf<Highlight>().also { it.addAll(store.loadHighlights(book.id)) } }
    var selection by remember { mutableStateOf<Selection?>(null) }
    var editingId by remember { mutableStateOf<String?>(null) }

    var menuOpen by remember { mutableStateOf(false) }
    var showTheme by remember { mutableStateOf(false) }
    var showJump by remember { mutableStateOf(false) }
    var showNotes by remember { mutableStateOf(false) }
    var showSearch by remember { mutableStateOf(false) }

    var query by remember { mutableStateOf("") }
    val matches = remember { mutableStateListOf<SearchHit>() }
    var matchIndex by remember { mutableIntStateOf(-1) }
    var searching by remember { mutableStateOf(false) }
    var searchJob by remember { mutableStateOf<Job?>(null) }

    // ---- open the PDF ----
    LaunchedEffect(book.id) {
        val s = PdfSession.open(ctx, store.pdfFile(book.id))
        if (s == null) { failed = true; return@LaunchedEffect }
        holder[0] = s
        s.loadSizes()
        session = s
        // Warm up text extraction for the current page so the first selection is instant.
        launch { s.text(page) }
    }
    DisposableEffect(book.id) {
        onDispose {
            val s = holder[0]
            holder[0] = null
            if (s != null) CoroutineScope(Dispatchers.IO).launch { s.close() }
        }
    }
    DisposableEffect(Unit) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
    LaunchedEffect(page) { delay(500); onProgress(page) }

    fun persistHighlights() = store.saveHighlights(book.id, highlights.toList())

    fun goTo(p: Int) {
        val count = session?.pageCount ?: book.pageCount
        val t = p.coerceIn(0, (count - 1).coerceAtLeast(0))
        page = t
        jump = t
    }

    fun clearSearch() {
        searchJob?.cancel(); matches.clear(); matchIndex = -1; searching = false; query = ""
    }

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

    fun stepMatch(delta: Int) {
        if (matches.isEmpty()) return
        val n = if (matchIndex < 0) (if (delta > 0) 0 else matches.size - 1) else (matchIndex + delta + matches.size) % matches.size
        matchIndex = n
        goTo(matches[n].page)
    }

    fun addHighlight(color: HighlightColor, thenEdit: Boolean) {
        val sel = selection ?: return
        val s = session ?: return
        scope.launch {
            val pt = s.text(sel.page)
            val rects = pt.rectsFor(sel.from, sel.to)
            if (rects.isEmpty()) return@launch
            val h = Highlight(UUID.randomUUID().toString(), sel.page, rects, color, pt.stringFor(sel.from, sel.to), "", System.currentTimeMillis())
            highlights.add(h)
            persistHighlights()
            selection = null
            if (thenEdit) editingId = h.id
        }
    }

    BackHandler {
        when {
            selection != null -> selection = null
            else -> { onProgress(page); onBack() }
        }
    }

    val activeSession = session
    Box(Modifier.fillMaxSize().background(theme.paper)) {
        when {
            failed -> Column(Modifier.fillMaxSize().padding(32.dp), Arrangement.Center, Alignment.CenterHorizontally) {
                Text("This PDF could not be opened.", color = theme.ink, fontSize = 18.sp)
                TextButton(onClick = onBack) { Text("Back to library") }
            }
            activeSession == null -> CircularProgressIndicator(Modifier.align(Alignment.Center))
            else -> {
                val pageMatches by remember { derivedStateOf { matches.groupBy { it.page } } }
                ReaderContent(
                    session = activeSession,
                    theme = theme,
                    mode = mode,
                    zoom = zoom,
                    page = page,
                    jump = jump,
                    onJumpConsumed = { jump = null },
                    onPage = { p ->
                        if (p != page) { page = p }
                        if (selection != null && selection?.page != p) selection = null
                    },
                    highlights = highlights,
                    pageMatches = pageMatches,
                    currentMatch = matches.getOrNull(matchIndex),
                    selection = selection,
                    onSelection = { selection = it },
                    onTapHighlight = { editingId = it },
                    onTapEmpty = { fx ->
                        if (selection != null) selection = null
                        else if (mode == ReadingMode.PageTurn && zoom == 1f && fx < 0.18f) goTo(page - 1)
                        else if (mode == ReadingMode.PageTurn && zoom == 1f && fx > 0.82f) goTo(page + 1)
                        else chrome = !chrome
                    },
                )
            }
        }

        if (activeSession != null) {
            val count = activeSession.pageCount
            val barColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f)

            // ---- top bar ----
            if (chrome && selection == null) {
                Surface(
                    color = barColor, tonalElevation = 3.dp,
                    modifier = Modifier.align(Alignment.TopCenter).fillMaxWidth(),
                ) {
                    Column(Modifier.windowInsetsPadding(WindowInsets.statusBars)) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = { onProgress(page); onBack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back to library") }
                            Text(
                                book.title, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface,
                            )
                            IconButton(onClick = { showSearch = true }) { Icon(Icons.Default.Search, "Search in book") }
                            IconButton(onClick = { showNotes = true }) { Icon(Icons.AutoMirrored.Filled.List, "Highlights and notes") }
                            Box {
                                IconButton(onClick = { menuOpen = true }) { Icon(Icons.Default.MoreVert, "More") }
                                DropdownMenu(menuOpen, { menuOpen = false }) {
                                    ReadingMode.values().forEach { m ->
                                        DropdownMenuItem(
                                            text = { Text(m.label) },
                                            leadingIcon = { if (mode == m) Icon(Icons.Default.Check, null) else Spacer(Modifier.size(24.dp)) },
                                            onClick = { mode = m; store.mode = m; menuOpen = false },
                                        )
                                    }
                                    HorizontalDivider()
                                    DropdownMenuItem(text = { Text("Paper theme…") }, onClick = { menuOpen = false; showTheme = true })
                                    DropdownMenuItem(text = { Text("Zoom in") }, onClick = {
                                        ZoomSteps.firstOrNull { it > zoom + 0.01f }?.let { zoom = it }; menuOpen = false
                                    })
                                    DropdownMenuItem(text = { Text("Zoom out") }, onClick = {
                                        ZoomSteps.lastOrNull { it < zoom - 0.01f }?.let { zoom = it }; menuOpen = false
                                    })
                                    DropdownMenuItem(text = { Text("Fit to screen") }, onClick = { zoom = 1f; menuOpen = false })
                                    HorizontalDivider()
                                    DropdownMenuItem(text = { Text("Go to page…") }, onClick = { menuOpen = false; showJump = true })
                                }
                            }
                        }
                        if (matches.isNotEmpty() || searching) {
                            Row(
                                Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, bottom = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    if (matchIndex >= 0) "“$query” · ${matchIndex + 1} of ${matches.size}" else "“$query” · ${matches.size} found",
                                    Modifier.weight(1f), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                IconButton(onClick = { stepMatch(-1) }) { Icon(Icons.Default.KeyboardArrowUp, "Previous match") }
                                IconButton(onClick = { stepMatch(1) }) { Icon(Icons.Default.KeyboardArrowDown, "Next match") }
                                IconButton(onClick = { clearSearch() }) { Icon(Icons.Default.Close, "Clear search") }
                            }
                        }
                    }
                }
            }

            // ---- bottom bar ----
            if (chrome && selection == null) {
                var dragging by remember { mutableStateOf(false) }
                var sliderValue by remember { mutableFloatStateOf(0f) }
                Surface(
                    color = barColor, tonalElevation = 3.dp,
                    modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth(),
                ) {
                    Column(Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 8.dp)) {
                        if (count > 1) {
                            Slider(
                                value = if (dragging) sliderValue else page.toFloat(),
                                onValueChange = { dragging = true; sliderValue = it },
                                onValueChangeFinished = { dragging = false; goTo(sliderValue.roundToInt()) },
                                valueRange = 0f..(count - 1).toFloat(),
                                modifier = Modifier.padding(horizontal = 8.dp),
                            )
                        }
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                            IconButton(onClick = { goTo(page - 1) }, enabled = page > 0) { Icon(Icons.Default.KeyboardArrowLeft, "Previous page") }
                            TextButton(onClick = { showJump = true }) {
                                val shown = if (dragging) sliderValue.roundToInt() else page
                                Text("Page ${shown + 1} of $count")
                            }
                            IconButton(onClick = { goTo(page + 1) }, enabled = page < count - 1) { Icon(Icons.Default.KeyboardArrowRight, "Next page") }
                        }
                    }
                }
            }

            // ---- selection toolbar ----
            val sel = selection
            if (sel != null) {
                SelectionBar(
                    session = activeSession,
                    selection = sel,
                    modifier = Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.navigationBars).padding(12.dp),
                    onHighlight = { addHighlight(it, false) },
                    onNote = { addHighlight(HighlightColor.Yellow, true) },
                    onClose = { selection = null },
                    ctx = ctx,
                )
            }
        }
    }

    // ---- dialogs & sheets ----
    if (showTheme) {
        AlertDialog(
            onDismissRequest = { showTheme = false },
            title = { Text("Paper theme") },
            text = {
                LazyColumn {
                    items(PaperTheme.values().toList()) { t ->
                        Row(
                            Modifier.fillMaxWidth().clickable { theme = t; store.theme = t; showTheme = false }.padding(vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(
                                Modifier.size(40.dp).clip(CircleShape).background(t.paper)
                                    .border(2.dp, if (t == theme) MaterialTheme.colorScheme.primary else Color.Gray.copy(alpha = 0.4f), CircleShape),
                                contentAlignment = Alignment.Center,
                            ) { Text("Aa", color = t.ink, fontWeight = FontWeight.Bold) }
                            Spacer(Modifier.width(14.dp))
                            Text(t.label, Modifier.weight(1f))
                            if (t == theme) Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showTheme = false }) { Text("Done") } },
        )
    }

    if (showJump) {
        val count = session?.pageCount ?: book.pageCount
        var text by remember { mutableStateOf("${page + 1}") }
        AlertDialog(
            onDismissRequest = { showJump = false },
            title = { Text("Go to page") },
            text = {
                OutlinedTextField(
                    text, { text = it.filter(Char::isDigit).take(6) }, singleLine = true,
                    label = { Text("1 – $count") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
            },
            confirmButton = {
                TextButton(onClick = { text.toIntOrNull()?.let { goTo(it - 1) }; showJump = false }) { Text("Go") }
            },
            dismissButton = { TextButton(onClick = { showJump = false }) { Text("Cancel") } },
        )
    }

    if (showSearch) {
        ModalBottomSheet(
            onDismissRequest = { showSearch = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            LaunchedEffect(query) { if (query.isNotBlank()) { delay(450); runSearch(query) } }
            Column(Modifier.fillMaxWidth().heightIn(min = 320.dp).padding(horizontal = 16.dp)) {
                OutlinedTextField(
                    query, { query = it; if (it.isBlank()) { searchJob?.cancel(); matches.clear(); matchIndex = -1; searching = false } },
                    modifier = Modifier.fillMaxWidth(), singleLine = true, label = { Text("Search in this book") },
                    leadingIcon = { Icon(Icons.Default.Search, null) },
                )
                if (searching) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 8.dp))
                Spacer(Modifier.size(8.dp))
                if (!searching && query.isNotBlank() && matches.isEmpty()) {
                    Text("No matches (scanned PDFs without text can't be searched).", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 16.dp))
                }
                LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp)) {
                    items(matches.size) { i ->
                        val m = matches[i]
                        Column(
                            Modifier.fillMaxWidth().clickable { matchIndex = i; goTo(m.page); showSearch = false }.padding(vertical = 10.dp),
                        ) {
                            Text("Page ${m.page + 1}", fontSize = 12.sp, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                            Text(m.snippet, maxLines = 2, overflow = TextOverflow.Ellipsis, fontSize = 14.sp)
                        }
                        HorizontalDivider()
                    }
                }
            }
        }
    }

    if (showNotes) {
        ModalBottomSheet(
            onDismissRequest = { showNotes = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            val sorted = highlights.sortedWith(compareBy({ it.page }, { it.createdAt }))
            Column(Modifier.fillMaxWidth().heightIn(min = 320.dp).padding(horizontal = 16.dp)) {
                Text("Highlights & notes", fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 8.dp))
                if (sorted.isEmpty()) {
                    Text(
                        "Nothing yet. Press and hold a word in the book, drag to extend, then choose a highlight colour or add a note.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 16.dp),
                    )
                }
                LazyColumn(Modifier.fillMaxWidth().heightIn(max = 560.dp)) {
                    items(sorted, key = { it.id }) { h ->
                        Row(
                            Modifier.fillMaxWidth().clickable { goTo(h.page); showNotes = false }.padding(vertical = 10.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            Box(Modifier.padding(top = 4.dp).size(14.dp).clip(CircleShape).background(h.color.color))
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text("Page ${h.page + 1}", fontSize = 12.sp, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                                Text(h.text, maxLines = 3, overflow = TextOverflow.Ellipsis, fontSize = 14.sp)
                                if (h.note.isNotBlank()) Text(h.note, fontStyle = FontStyle.Italic, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            IconButton(onClick = { editingId = h.id }) { Icon(Icons.Default.Create, "Edit note") }
                            IconButton(onClick = { highlights.removeAll { it.id == h.id }; persistHighlights() }) { Icon(Icons.Default.Delete, "Delete highlight") }
                        }
                        HorizontalDivider()
                    }
                }
            }
        }
    }

    editingId?.let { id ->
        val h = highlights.firstOrNull { it.id == id }
        if (h == null) { editingId = null } else {
            var note by remember(id) { mutableStateOf(h.note) }
            var color by remember(id) { mutableStateOf(h.color) }
            AlertDialog(
                onDismissRequest = { editingId = null },
                title = { Text("Highlight") },
                text = {
                    Column {
                        Text(h.text, maxLines = 5, overflow = TextOverflow.Ellipsis, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.size(12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            HighlightColor.values().forEach { c ->
                                Box(
                                    Modifier.size(34.dp).clip(CircleShape).background(c.color)
                                        .border(if (c == color) 3.dp else 0.dp, MaterialTheme.colorScheme.onSurface, CircleShape)
                                        .clickable { color = c },
                                )
                            }
                        }
                        Spacer(Modifier.size(12.dp))
                        OutlinedTextField(note, { note = it }, label = { Text("Note") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
                    }
                },
                confirmButton = {
                    TextButton(onClick = {
                        val i = highlights.indexOfFirst { it.id == id }
                        if (i >= 0) { highlights[i] = highlights[i].copy(note = note.trim(), color = color); persistHighlights() }
                        editingId = null
                    }) { Text("Save") }
                },
                dismissButton = {
                    Row {
                        TextButton(onClick = { highlights.removeAll { it.id == id }; persistHighlights(); editingId = null }) { Text("Delete") }
                        TextButton(onClick = { editingId = null }) { Text("Cancel") }
                    }
                },
            )
        }
    }
}

@Composable
private fun SelectionBar(
    session: PdfSession,
    selection: Selection,
    modifier: Modifier,
    onHighlight: (HighlightColor) -> Unit,
    onNote: () -> Unit,
    onClose: () -> Unit,
    ctx: Context,
) {
    val text by produceState("", selection, session) { value = session.text(selection.page).stringFor(selection.from, selection.to) }
    Surface(modifier = modifier, shape = RoundedCornerShape(28.dp), tonalElevation = 6.dp, shadowElevation = 8.dp) {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            Text(
                text, maxLines = 2, overflow = TextOverflow.Ellipsis, fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                HighlightColor.values().forEach { c ->
                    Box(Modifier.padding(4.dp).size(34.dp).clip(CircleShape).background(c.color).clickable { onHighlight(c) })
                }
                TextButton(onClick = onNote) { Text("Note") }
                TextButton(onClick = {
                    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("BookLand", text))
                    Toast.makeText(ctx, "Copied", Toast.LENGTH_SHORT).show()
                }) { Text("Copy") }
                TextButton(onClick = {
                    // Hands the selected text to a translation app (Google Translate etc.); falls back to a share sheet.
                    val i = Intent(Intent.ACTION_PROCESS_TEXT).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_PROCESS_TEXT, text)
                        putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
                    }
                    try { ctx.startActivity(Intent.createChooser(i, "Translate").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    catch (e: Exception) {
                        val s = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
                        ctx.startActivity(Intent.createChooser(s, "Share").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                }) { Text("Translate") }
                IconButton(onClick = onClose) { Icon(Icons.Default.Close, "Clear selection") }
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Pages
// ---------------------------------------------------------------------------------------------

@Composable
private fun ReaderContent(
    session: PdfSession,
    theme: PaperTheme,
    mode: ReadingMode,
    zoom: Float,
    page: Int,
    jump: Int?,
    onJumpConsumed: () -> Unit,
    onPage: (Int) -> Unit,
    highlights: List<Highlight>,
    pageMatches: Map<Int, List<SearchHit>>,
    currentMatch: SearchHit?,
    selection: Selection?,
    onSelection: (Selection?) -> Unit,
    onTapHighlight: (String) -> Unit,
    onTapEmpty: (Float) -> Unit,
) {
    val count = session.pageCount
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val viewW = with(density) { maxWidth.toPx() }
        val viewH = with(density) { maxHeight.toPx() }
        val maxBitmapW = 2200f
        val boxMaxW = maxWidth
        val boxMaxH = maxHeight

        @Composable
        fun Page(i: Int, widthPx: Float, heightPx: Float) {
            PageView(
                session = session, index = i,
                widthPx = widthPx.coerceAtLeast(1f), heightPx = heightPx.coerceAtLeast(1f),
                maxBitmapW = maxBitmapW, theme = theme,
                highlights = highlights.filter { it.page == i },
                matchRects = pageMatches[i]?.flatMap { it.rects } ?: emptyList(),
                currentRects = if (currentMatch?.page == i) currentMatch.rects else emptyList(),
                selection = selection?.takeIf { it.page == i },
                onSelection = onSelection, onTapHighlight = onTapHighlight, onTapEmpty = onTapEmpty,
            )
        }

        when (mode) {
            ReadingMode.PageTurn -> {
                val pager = rememberPagerState(initialPage = page.coerceIn(0, count - 1), pageCount = { count })
                LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.collect { onPage(it) } }
                LaunchedEffect(jump) {
                    val j = jump ?: return@LaunchedEffect
                    if (j != pager.currentPage) {
                        if (abs(j - pager.currentPage) == 1) pager.animateScrollToPage(j) else pager.scrollToPage(j)
                    }
                    onJumpConsumed()
                }
                HorizontalPager(state = pager, modifier = Modifier.fillMaxSize(), beyondViewportPageCount = 1, key = { it }) { i ->
                    val (pw, ph) = session.sizes.getOrNull(i) ?: (612f to 792f)
                    val fit = min(viewW / pw, viewH / ph) * zoom
                    val w = pw * fit
                    val h = ph * fit
                    val vs = rememberScrollState()
                    val hs = rememberScrollState()
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Box(
                            Modifier.widthIn(max = boxMaxW).heightIn(max = boxMaxH)
                                .then(if (zoom > 1f) Modifier.verticalScroll(vs).horizontalScroll(hs) else Modifier),
                        ) { Page(i, w, h) }
                    }
                }
            }
            ReadingMode.Scroll -> {
                val list = rememberLazyListState(initialFirstVisibleItemIndex = page.coerceIn(0, count - 1))
                LaunchedEffect(list) { snapshotFlow { centerPage(list) }.collect { onPage(it) } }
                LaunchedEffect(jump) {
                    val j = jump ?: return@LaunchedEffect
                    list.scrollToItem(j)
                    onJumpConsumed()
                }
                val contentW = viewW * zoom
                Box(Modifier.fillMaxSize().horizontalScroll(rememberScrollState())) {
                    LazyColumn(
                        Modifier.width(with(density) { contentW.toDp() }).fillMaxHeight(),
                        state = list,
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        items(count, key = { it }) { i ->
                            val (pw, ph) = session.sizes.getOrNull(i) ?: (612f to 792f)
                            Page(i, contentW, contentW * ph / pw)
                        }
                    }
                }
            }
        }
    }
}

private fun centerPage(list: LazyListState): Int {
    val info = list.layoutInfo
    val probe = info.viewportStartOffset + (info.viewportEndOffset - info.viewportStartOffset) * 3 / 10
    val hit = info.visibleItemsInfo.firstOrNull { it.offset <= probe && it.offset + it.size >= probe }
    return (hit ?: info.visibleItemsInfo.firstOrNull())?.index ?: list.firstVisibleItemIndex
}

@Composable
private fun PageView(
    session: PdfSession,
    index: Int,
    widthPx: Float,
    heightPx: Float,
    maxBitmapW: Float,
    theme: PaperTheme,
    highlights: List<Highlight>,
    matchRects: List<Rf>,
    currentRects: List<Rf>,
    selection: Selection?,
    onSelection: (Selection?) -> Unit,
    onTapHighlight: (String) -> Unit,
    onTapEmpty: (Float) -> Unit,
) {
    val density = LocalDensity.current
    val bitmapW = min(widthPx, maxBitmapW).roundToInt().coerceAtLeast(1)
    val bmp by produceState<Bitmap?>(session.cached(index, bitmapW), session, index, bitmapW) {
        value = session.render(index, bitmapW)
    }
    val pageText by produceState<PageText?>(null, session, index) { value = session.text(index) }
    val filter = remember(theme) { ColorFilter.colorMatrix(themeMatrix(theme)) }

    val ptState = rememberUpdatedState(pageText)
    val selState = rememberUpdatedState(selection)
    val hlState = rememberUpdatedState(highlights)
    val onSel = rememberUpdatedState(onSelection)
    val onTapHl = rememberUpdatedState(onTapHighlight)
    val onTapE = rememberUpdatedState(onTapEmpty)

    val selRects = remember(selection, pageText) {
        val pt = pageText
        if (selection != null && pt != null) pt.rectsFor(selection.from, selection.to) else emptyList()
    }

    Box(
        Modifier
            .size(with(density) { widthPx.toDp() }, with(density) { heightPx.toDp() })
            .background(theme.paper)
            .pointerInput(index) {
                detectTapGestures { off ->
                    val fx = off.x / size.width
                    val fy = off.y / size.height
                    val hit = hlState.value.lastOrNull { h ->
                        h.rects.any { r -> fx >= r.l - 0.004f && fx <= r.r + 0.004f && fy >= r.t - 0.004f && fy <= r.b + 0.004f }
                    }
                    if (hit != null) onTapHl.value(hit.id) else onTapE.value(fx)
                }
            }
            .pointerInput(index) {
                var anchorA = -1
                var anchorB = -1
                detectDragGesturesAfterLongPress(
                    onDragStart = { off ->
                        val pt = ptState.value ?: return@detectDragGesturesAfterLongPress
                        val fx = off.x / size.width
                        val fy = off.y / size.height
                        val cur = selState.value
                        anchorA = -1
                        if (cur != null) {
                            // Grab a selection handle to adjust the start or the end.
                            val rs = pt.rectsFor(cur.from, cur.to)
                            if (rs.isNotEmpty()) {
                                val s = Offset(rs.first().l * size.width, rs.first().b * size.height)
                                val e = Offset(rs.last().r * size.width, rs.last().b * size.height)
                                val reach = 44.dp.toPx()
                                if ((off - s).getDistance() < reach && (off - s).getDistance() <= (off - e).getDistance()) { anchorA = cur.to; anchorB = cur.to }
                                else if ((off - e).getDistance() < reach) { anchorA = cur.from; anchorB = cur.from }
                            }
                        }
                        if (anchorA < 0) {
                            val i = pt.indexAt(fx, fy)
                            if (i < 0) return@detectDragGesturesAfterLongPress
                            val w = pt.wordRange(i)
                            anchorA = w.first; anchorB = w.last
                            onSel.value(Selection(index, w.first, w.last))
                        }
                    },
                    onDrag = { change, _ ->
                        if (anchorA >= 0) {
                            change.consume()
                            val pt = ptState.value
                            if (pt != null) {
                                val i = pt.indexAt(change.position.x / size.width, change.position.y / size.height, maxPts = 400f)
                                if (i >= 0) onSel.value(Selection(index, min(anchorA, i), maxOf(anchorB, i)))
                            }
                        }
                    },
                )
            },
    ) {
        bmp?.let {
            Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds, colorFilter = filter)
        }
        Canvas(Modifier.fillMaxSize()) {
            fun draw(rs: List<Rf>, color: Color) {
                rs.forEach { r ->
                    drawRect(color, Offset(r.l * size.width, r.t * size.height), Size((r.r - r.l) * size.width, (r.b - r.t) * size.height))
                }
            }
            highlights.forEach { draw(it.rects, it.color.color.copy(alpha = 0.38f)) }
            draw(matchRects, Color(0xFFFF9F0A).copy(alpha = 0.40f))
            draw(currentRects, Color(0xFFFF453A).copy(alpha = 0.50f))
            draw(selRects, Color(0xFF0A84FF).copy(alpha = 0.32f))
            if (selRects.isNotEmpty()) {
                val s = selRects.first()
                val e = selRects.last()
                val accent = Color(0xFF0A84FF)
                drawCircle(accent, 7.dp.toPx(), Offset(s.l * size.width, s.b * size.height + 7.dp.toPx()))
                drawCircle(accent, 7.dp.toPx(), Offset(e.r * size.width, e.b * size.height + 7.dp.toPx()))
            }
        }
    }
}
