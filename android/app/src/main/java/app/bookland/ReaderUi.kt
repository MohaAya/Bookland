package app.bookland

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.widget.Toast
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
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
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** Light themes multiply the paper over the white page; dark themes turn the page into paper and the text white. */
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

// ---------------------------------------------------------------------------------------------
// The reading area (page turn / vertical scroll)
// ---------------------------------------------------------------------------------------------

@Composable
fun ReaderPane(state: ReaderState, store: Store, modifier: Modifier = Modifier, onTapEmpty: (Float) -> Unit) {
    val theme = store.theme
    Box(modifier.background(theme.paper)) {
        val s = state.session
        when {
            state.failed -> Text("This PDF could not be opened.", Modifier.align(Alignment.Center).padding(24.dp), color = theme.ink)
            s == null -> CircularProgressIndicator(Modifier.align(Alignment.Center))
            else -> ReaderContent(state, s, theme, store.mode, onTapEmpty)
        }
    }
}

@Composable
private fun ReaderContent(state: ReaderState, session: PdfSession, theme: PaperTheme, mode: ReadingMode, onTapEmpty: (Float) -> Unit) {
    val count = session.pageCount
    val pageMatches by remember(state) { derivedStateOf { state.matches.groupBy { it.page } } }
    BoxWithConstraints(
        Modifier.fillMaxSize().pointerInput(state) {
            // Two-finger pinch zooms; single-finger drags still go to page turning and scrolling.
            awaitEachGesture {
                awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                var zoomed = false
                do {
                    val event = awaitPointerEvent(PointerEventPass.Initial)
                    if (event.changes.count { it.pressed } >= 2) {
                        val z = event.calculateZoom()
                        if (z != 1f) {
                            state.zoom = (state.zoom * z).coerceIn(1f, 4f)
                            zoomed = true
                            event.changes.forEach { it.consume() }
                        }
                    }
                } while (event.changes.any { it.pressed })
                if (zoomed && state.zoom < 1.08f) state.zoom = 1f
            }
        },
    ) {
        val density = LocalDensity.current
        val viewW = with(density) { maxWidth.toPx() }
        val viewH = with(density) { maxHeight.toPx() }
        val boxMaxW = maxWidth
        val boxMaxH = maxHeight
        val zoom = state.zoom

        @Composable
        fun Page(i: Int, widthPx: Float, heightPx: Float) {
            PageView(
                session = session, index = i,
                widthPx = widthPx.coerceAtLeast(1f), heightPx = heightPx.coerceAtLeast(1f),
                theme = theme,
                highlights = state.notes.filter { it.isHighlight && it.page == i },
                matchRects = pageMatches[i]?.flatMap { it.rects } ?: emptyList(),
                currentRects = state.matches.getOrNull(state.matchIndex)?.takeIf { it.page == i }?.rects ?: emptyList(),
                selection = state.selection?.takeIf { it.page == i },
                onSelection = { state.selection = it },
                onTapHighlight = { state.editingNoteId = it },
                onTapEmpty = { fx ->
                    if (state.selection != null) state.selection = null
                    else if (mode == ReadingMode.PageTurn && zoom == 1f && fx < 0.18f) state.goTo(state.page - 1)
                    else if (mode == ReadingMode.PageTurn && zoom == 1f && fx > 0.82f) state.goTo(state.page + 1)
                    else onTapEmpty(fx)
                },
            )
        }

        when (mode) {
            ReadingMode.PageTurn -> {
                val pager = rememberPagerState(initialPage = state.page.coerceIn(0, count - 1), pageCount = { count })
                LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.collect { state.onPageChanged(it) } }
                LaunchedEffect(state.jump) {
                    val j = state.jump ?: return@LaunchedEffect
                    if (j != pager.currentPage) {
                        if (abs(j - pager.currentPage) == 1) pager.animateScrollToPage(j) else pager.scrollToPage(j)
                    }
                    state.jump = null
                }
                HorizontalPager(state = pager, modifier = Modifier.fillMaxSize(), beyondViewportPageCount = 1, key = { it }) { i ->
                    val (pw, ph) = session.sizes.getOrNull(i) ?: (612f to 792f)
                    val fit = min(viewW / pw, viewH / ph) * zoom
                    val vs = rememberScrollState()
                    val hs = rememberScrollState()
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Box(
                            Modifier.widthIn(max = boxMaxW).heightIn(max = boxMaxH)
                                .then(if (zoom > 1f) Modifier.verticalScroll(vs).horizontalScroll(hs) else Modifier),
                        ) { Page(i, pw * fit, ph * fit) }
                    }
                }
            }
            ReadingMode.Scroll -> {
                val list = rememberLazyListState(initialFirstVisibleItemIndex = state.page.coerceIn(0, count - 1))
                LaunchedEffect(list) { snapshotFlow { centerPage(list) }.collect { state.onPageChanged(it) } }
                LaunchedEffect(state.jump) {
                    val j = state.jump ?: return@LaunchedEffect
                    list.scrollToItem(j)
                    state.jump = null
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
    theme: PaperTheme,
    highlights: List<Note>,
    matchRects: List<Rf>,
    currentRects: List<Rf>,
    selection: Selection?,
    onSelection: (Selection?) -> Unit,
    onTapHighlight: (String) -> Unit,
    onTapEmpty: (Float) -> Unit,
) {
    val density = LocalDensity.current
    // Render in 128px steps so pinch-zooming doesn't ask for a new bitmap on every frame.
    val bitmapW = (kotlin.math.ceil(min(widthPx, 2600f) / 128f).toInt() * 128).coerceAtLeast(128)
    val bmp by produceState<Bitmap?>(session.cached(index, bitmapW), session, index, bitmapW) {
        val hit = session.cached(index, bitmapW)
        if (hit != null) { value = hit; return@produceState }
        if (value != null) delay(180) // keep showing the old bitmap while the fingers are still moving
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
            if (theme.sketchy) drawSketchPaper()
            fun draw(rs: List<Rf>, color: Color) {
                rs.forEach { r ->
                    drawRect(color, Offset(r.l * size.width, r.t * size.height), Size((r.r - r.l) * size.width, (r.b - r.t) * size.height))
                }
            }
            highlights.forEach { draw(it.rects, (it.color ?: HighlightColor.Yellow).color.copy(alpha = 0.38f)) }
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

/** Faint wavy ruled lines and paper fibres, the "Sketchbook" paper treatment. */
private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawSketchPaper() {
    val brown = Color(0xFF8B5A2B)
    var y = 22.dp.toPx()
    val step = 25.dp.toPx()
    val dx = 22.dp.toPx()
    while (y < size.height) {
        var x = 0f
        var px = 0f
        var py = y
        while (x <= size.width) {
            val wob = (sin((x + y) * 0.035f) * 0.8f)
            val ny = y + wob
            if (x > 0f) drawLine(brown.copy(alpha = 0.09f), Offset(px, py), Offset(x, ny), strokeWidth = 0.7.dp.toPx(), cap = StrokeCap.Butt)
            px = x; py = ny
            x += dx
        }
        y += step
    }
    var fx = 12.dp.toPx()
    while (fx < size.width) {
        drawLine(brown.copy(alpha = 0.025f), Offset(fx, 0f), Offset(fx + 5.dp.toPx(), size.height), strokeWidth = 0.8.dp.toPx())
        fx += 38.dp.toPx()
    }
}

// ---------------------------------------------------------------------------------------------
// Selection toolbar
// ---------------------------------------------------------------------------------------------

@Composable
fun SelectionBar(state: ReaderState, modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    val sel = state.selection ?: return
    val session = state.session ?: return
    val text by produceState("", sel, session) { value = session.text(sel.page).stringFor(sel.from, sel.to) }
    Surface(modifier = modifier, shape = RoundedCornerShape(24.dp), tonalElevation = 6.dp, shadowElevation = 8.dp) {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            Text(
                text, maxLines = 2, overflow = TextOverflow.Ellipsis, fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                HighlightColor.values().forEach { c ->
                    Box(Modifier.padding(4.dp).size(34.dp).clip(CircleShape).background(c.color).clickable { state.addHighlight(c) })
                }
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { state.selection = null }) { Icon(Icons.Default.Close, "Clear selection") }
            }
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                TextButton(onClick = { state.startNoteFromSelection() }) { Text("Add note") }
                TextButton(onClick = { state.saveSelectionAsQuote() }) { Text("Save") }
                TextButton(onClick = { copyText(ctx, text); Toast.makeText(ctx, "Copied", Toast.LENGTH_SHORT).show() }) { Text("Copy") }
                TextButton(onClick = { state.translating = text }) { Text("Translate") }
            }
        }
    }
}

fun copyText(ctx: Context, text: String) {
    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText("BookLand", text))
}

fun shareText(ctx: Context, text: String, title: String = "Share") {
    val s = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
    ctx.startActivity(Intent.createChooser(s, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** Hands the selected text to a translation app (Google Translate etc.); falls back to a share sheet. */
fun translateText(ctx: Context, text: String) {
    val i = Intent(Intent.ACTION_PROCESS_TEXT).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_PROCESS_TEXT, text)
        putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
    }
    try { ctx.startActivity(Intent.createChooser(i, "Translate").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    catch (e: Exception) { shareText(ctx, text) }
}

// ---------------------------------------------------------------------------------------------
// Sheets and dialogs (shared by the reader and the Compare panes)
// ---------------------------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderSheets(state: ReaderState, store: Store) {
    val theme = store.theme

    when (state.sheet) {
        Sheet.Theme -> ThemeDialog(store) { state.sheet = null }
        Sheet.Jump -> JumpDialog(state)
        Sheet.Search -> SearchSheet(state)
        Sheet.History -> HistorySheet(state)
        Sheet.Browser -> BrowserSheet(state)
        Sheet.Notes -> ModalBottomSheet(
            onDismissRequest = { state.sheet = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            BookNotesContent(
                book = state.book, store = store, modifier = Modifier.heightIn(min = 360.dp, max = 640.dp),
                onOpen = { p -> state.goTo(p); state.sheet = null },
            )
        }
        null -> {}
    }

    state.translating?.let { t -> TranslateDialog(t, store) { state.translating = null } }

    state.noteDraft?.let { draft ->
        var text by remember(draft) { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { state.noteDraft = null },
            title = { Text("Add note · page ${draft.page + 1}") },
            text = {
                Column {
                    if (draft.quote.isNotBlank()) {
                        Text(draft.quote, maxLines = 5, overflow = TextOverflow.Ellipsis, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.size(10.dp))
                    }
                    OutlinedTextField(text, { text = it }, label = { Text("Your note") }, modifier = Modifier.fillMaxWidth(), minLines = 3)
                }
            },
            confirmButton = {
                TextButton(enabled = text.isNotBlank(), onClick = { state.addNote(draft, text); state.noteDraft = null }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { state.noteDraft = null }) { Text("Cancel") } },
        )
    }

    state.editingNoteId?.let { id ->
        val n = state.notes.firstOrNull { it.id == id }
        if (n == null) { state.editingNoteId = null } else {
            AlertDialog(
                onDismissRequest = { state.editingNoteId = null },
                title = { Text("Highlight · page ${n.page + 1}") },
                text = {
                    Column {
                        Text(n.text, maxLines = 6, overflow = TextOverflow.Ellipsis, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.size(12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            HighlightColor.values().forEach { c ->
                                Box(
                                    Modifier.size(34.dp).clip(CircleShape).background(c.color)
                                        .border(if (c == n.color) 3.dp else 0.dp, MaterialTheme.colorScheme.onSurface, CircleShape)
                                        .clickable { state.recolor(id, c) },
                                )
                            }
                        }
                    }
                },
                confirmButton = { TextButton(onClick = { state.editingNoteId = null }) { Text("Done") } },
                dismissButton = {
                    Row {
                        TextButton(onClick = { state.noteDraft = NoteDraft(n.page, n.text); state.editingNoteId = null }) { Text("Add note") }
                        TextButton(onClick = { state.deleteNote(id); state.editingNoteId = null }) { Text("Remove") }
                    }
                },
            )
        }
    }
}

@Composable
fun ThemeDialog(store: Store, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Paper theme") },
        text = {
            LazyColumn {
                items(PaperTheme.values().toList()) { t ->
                    Row(
                        Modifier.fillMaxWidth().clickable { store.theme = t; onDismiss() }.padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            Modifier.size(40.dp).clip(CircleShape).background(t.paper)
                                .border(2.dp, if (t == store.theme) MaterialTheme.colorScheme.primary else Color.Gray.copy(alpha = 0.4f), CircleShape),
                            contentAlignment = Alignment.Center,
                        ) { Text("Aa", color = t.ink, fontWeight = FontWeight.Bold) }
                        Spacer(Modifier.width(14.dp))
                        Text(t.label, Modifier.weight(1f))
                        if (t == store.theme) Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
    )
}

@Composable
private fun JumpDialog(state: ReaderState) {
    val count = state.pageCount
    var text by remember { mutableStateOf("${state.page + 1}") }
    AlertDialog(
        onDismissRequest = { state.sheet = null },
        title = { Text("Jump to page") },
        text = {
            OutlinedTextField(
                text, { text = it.filter(Char::isDigit).take(6) }, singleLine = true,
                label = { Text("1 – $count") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )
        },
        confirmButton = {
            TextButton(
                enabled = text.toIntOrNull()?.let { it in 1..count } == true,
                onClick = { text.toIntOrNull()?.let { state.goTo(it - 1) }; state.sheet = null },
            ) { Text("Go") }
        },
        dismissButton = { TextButton(onClick = { state.sheet = null }) { Text("Cancel") } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchSheet(state: ReaderState) {
    ModalBottomSheet(
        onDismissRequest = { state.sheet = null },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        LaunchedEffect(state.query) { if (state.query.isNotBlank()) { delay(450); state.runSearch(state.query) } }
        Column(Modifier.fillMaxWidth().heightIn(min = 320.dp).padding(horizontal = 16.dp)) {
            OutlinedTextField(
                state.query,
                { state.query = it; if (it.isBlank()) { state.runSearch("") } },
                modifier = Modifier.fillMaxWidth(), singleLine = true, label = { Text("Search in this book") },
                leadingIcon = { Icon(Icons.Default.Search, null) },
            )
            if (state.searching) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 8.dp))
            Spacer(Modifier.size(8.dp))
            if (!state.searching && state.query.isNotBlank() && state.matches.isEmpty()) {
                Text("No matches. Scanned PDFs without real text can’t be searched.", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 16.dp))
            }
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp)) {
                items(state.matches.size) { i ->
                    val m = state.matches[i]
                    Column(
                        Modifier.fillMaxWidth().clickable { state.matchIndex = i; state.goTo(m.page); state.sheet = null }.padding(vertical = 10.dp),
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HistorySheet(state: ReaderState) {
    ModalBottomSheet(
        onDismissRequest = { state.sheet = null },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(Modifier.fillMaxWidth().heightIn(min = 300.dp).padding(horizontal = 16.dp)) {
            Text("Page history", fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 8.dp))
            if (state.history.size <= 1) {
                Text("Pages you jump to are listed here so you can go back.", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 16.dp))
            }
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp)) {
                items(state.history.indices.reversed().toList()) { i ->
                    Row(
                        Modifier.fillMaxWidth().clickable { state.goToHistory(i); state.sheet = null }.padding(vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Page ${state.history[i] + 1}", Modifier.weight(1f))
                        if (i == state.historyIndex) {
                            Text("You are here", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.width(8.dp))
                            Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                    HorizontalDivider()
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BrowserSheet(state: ReaderState) {
    val session = state.session ?: return
    var tab by remember { mutableStateOf(0) }
    val outline by produceState<List<OutlineRow>?>(null, session) { value = session.outline() }
    ModalBottomSheet(
        onDismissRequest = { state.sheet = null },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(Modifier.fillMaxWidth().heightIn(min = 420.dp)) {
            Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("Pages", "Index").forEachIndexed { i, label ->
                    Surface(
                        shape = RoundedCornerShape(20.dp),
                        color = if (tab == i) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier.clickable { tab = i },
                    ) { Text(label, Modifier.padding(horizontal = 18.dp, vertical = 8.dp), fontWeight = FontWeight.SemiBold) }
                }
            }
            Spacer(Modifier.size(8.dp))
            if (tab == 0) {
                val grid = rememberLazyGridState(initialFirstVisibleItemIndex = (state.page - 2).coerceAtLeast(0))
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(92.dp), state = grid,
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
                    modifier = Modifier.heightIn(max = 640.dp),
                ) {
                    items((0 until session.pageCount).toList(), key = { it }) { i ->
                        val thumb by produceState<Bitmap?>(null, session, i) { value = session.render(i, 200) }
                        val current = i == state.page
                        val ratio = session.sizes.getOrNull(i)?.let { it.first / it.second } ?: 0.72f
                        Column(
                            Modifier.clickable { state.goTo(i); state.sheet = null },
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Box(
                                Modifier.fillMaxWidth().aspectRatio(ratio.coerceIn(0.4f, 2f)).clip(RoundedCornerShape(6.dp)).background(Color.White)
                                    .border(if (current) 2.5.dp else 0.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(6.dp)),
                            ) {
                                thumb?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds) }
                            }
                            Text(
                                "Page ${i + 1}", fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp),
                                color = if (current) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                fontWeight = if (current) FontWeight.SemiBold else FontWeight.Normal,
                            )
                        }
                    }
                }
            } else {
                val rows = outline
                when {
                    rows == null -> Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                    rows.isEmpty() -> Text(
                        "This PDF does not contain a navigable index.", color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(24.dp),
                    )
                    else -> LazyColumn(Modifier.heightIn(max = 640.dp)) {
                        items(rows.size) { i ->
                            val r = rows[i]
                            Row(
                                Modifier.fillMaxWidth()
                                    .then(if (r.page != null) Modifier.clickable { state.goTo(r.page); state.sheet = null } else Modifier)
                                    .padding(start = 16.dp + 16.dp * r.depth, end = 16.dp, top = 12.dp, bottom = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(r.title, Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis,
                                    color = if (r.page != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                                if (r.page != null) Text("${r.page + 1}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}

/** Search match navigation strip (shown while a search is active). */
@Composable
fun SearchStrip(state: ReaderState, modifier: Modifier = Modifier) {
    if (state.matches.isEmpty() && !state.searching) return
    Row(modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            if (state.matchIndex >= 0) "“${state.query}” · ${state.matchIndex + 1} of ${state.matches.size}" else "“${state.query}” · ${state.matches.size} found",
            Modifier.weight(1f), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        IconButton(onClick = { state.stepMatch(-1) }) { Icon(Icons.Default.KeyboardArrowUp, "Previous match") }
        IconButton(onClick = { state.stepMatch(1) }) { Icon(Icons.Default.KeyboardArrowDown, "Next match") }
        IconButton(onClick = { state.clearSearch() }) { Icon(Icons.Default.Close, "Clear search") }
    }
}
