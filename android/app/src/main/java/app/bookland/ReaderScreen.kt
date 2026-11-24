package app.bookland

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Create
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

@Composable
fun ReaderScreen(book: Book, store: Store, startPage: Int?, onBack: () -> Unit, onProgress: (Int) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val state = remember(book.id, startPage) { ReaderState(book, store, ctx, scope, startPage ?: book.lastPage, onProgress) }
    var chrome by remember { mutableStateOf(true) }
    var menuOpen by remember { mutableStateOf(false) }

    LaunchedEffect(state) { state.open() }
    DisposableEffect(state) { onDispose { state.close() } }
    DisposableEffect(store.keepAwake) {
        view.keepScreenOn = store.keepAwake
        onDispose { view.keepScreenOn = false }
    }

    BackHandler {
        if (state.selection != null) state.selection = null
        else onBack()
    }

    val theme = store.theme
    Box(Modifier.fillMaxSize().background(theme.paper)) {
        ReaderPane(state, store, Modifier.fillMaxSize()) { chrome = !chrome }

        if (state.session != null) {
            val count = state.pageCount
            val barColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f)
            val sel = state.selection

            if (chrome && sel == null) {
                Surface(color = barColor, tonalElevation = 3.dp, modifier = Modifier.align(Alignment.TopCenter).fillMaxWidth()) {
                    Column(Modifier.windowInsetsPadding(WindowInsets.statusBars)) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back to library") }
                            Text(
                                book.title, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface,
                            )
                            IconButton(onClick = { state.sheet = Sheet.Search }) { Icon(Icons.Default.Search, "Search in book") }
                            IconButton(onClick = { state.sheet = Sheet.Browser }) { Icon(Icons.Default.Menu, "Pages and index") }
                            IconButton(onClick = { state.sheet = Sheet.Notes }) { Icon(Icons.Default.Create, "Highlights and notes") }
                            Box {
                                IconButton(onClick = { menuOpen = true }) { Icon(Icons.Default.MoreVert, "More") }
                                DropdownMenu(menuOpen, { menuOpen = false }) {
                                    ReadingMode.values().forEach { m ->
                                        DropdownMenuItem(
                                            text = { Text(m.label) },
                                            leadingIcon = { if (store.mode == m) Icon(Icons.Default.Check, null) else Spacer(Modifier.size(24.dp)) },
                                            onClick = { store.mode = m; menuOpen = false },
                                        )
                                    }
                                    HorizontalDivider()
                                    DropdownMenuItem(text = { Text("Paper theme…") }, onClick = { menuOpen = false; state.sheet = Sheet.Theme })
                                    DropdownMenuItem(text = { Text("Zoom in") }, onClick = { state.zoomIn(); menuOpen = false })
                                    DropdownMenuItem(text = { Text("Zoom out") }, onClick = { state.zoomOut(); menuOpen = false })
                                    DropdownMenuItem(text = { Text("Fit to screen") }, onClick = { state.fit(); menuOpen = false })
                                    HorizontalDivider()
                                    DropdownMenuItem(text = { Text("Reading history") }, onClick = { menuOpen = false; state.sheet = Sheet.History })
                                    DropdownMenuItem(text = { Text("Undo last highlight") }, onClick = { menuOpen = false; state.undoLastHighlight() })
                                    DropdownMenuItem(text = { Text("Add note…") }, onClick = { menuOpen = false; state.noteDraft = NoteDraft(state.page, "") })
                                    DropdownMenuItem(text = { Text("Go to page…") }, onClick = { menuOpen = false; state.sheet = Sheet.Jump })
                                }
                            }
                        }
                        SearchStrip(state, Modifier.padding(bottom = 4.dp))
                    }
                }
            }

            if (chrome && sel == null) {
                Surface(color = barColor, tonalElevation = 3.dp, modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
                    Column(Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 8.dp)) {
                        PageControls(state, count)
                    }
                }
            }

            if (sel != null) {
                SelectionBar(
                    state,
                    Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.navigationBars).padding(12.dp),
                )
            }
        }
    }

    ReaderSheets(state, store)
}

/** Page slider, previous/next and the page counter (tap it to jump). Used by the reader and the Compare panes. */
@Composable
fun PageControls(state: ReaderState, count: Int) {
    var dragging by remember { mutableStateOf(false) }
    var sliderValue by remember { mutableFloatStateOf(0f) }
    if (count > 1) {
        Slider(
            value = if (dragging) sliderValue else state.page.toFloat(),
            onValueChange = { dragging = true; sliderValue = it; state.goTo(it.roundToInt(), record = false) },
            onValueChangeFinished = { dragging = false; state.goTo(sliderValue.roundToInt()) },
            valueRange = 0f..(count - 1).toFloat(),
            modifier = Modifier.padding(horizontal = 8.dp),
        )
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        IconButton(onClick = { state.goTo(state.page - 1) }, enabled = state.page > 0) { Icon(Icons.Default.KeyboardArrowLeft, "Previous page") }
        TextButton(onClick = { state.sheet = Sheet.Jump }) { Text("Page ${state.page + 1} of $count") }
        IconButton(onClick = { state.goTo(state.page + 1) }, enabled = state.page < count - 1) { Icon(Icons.Default.KeyboardArrowRight, "Next page") }
    }
}
