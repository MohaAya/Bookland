package app.bookland

import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** The Notes tab: every book that has highlights or notes, then one book's list. */
@Composable
fun NotesTab(
    books: List<Book>,
    store: Store,
    selectedId: String?,
    onSelect: (String?) -> Unit,
    onOpenAt: (Book, Int) -> Unit,
) {
    val ctx = LocalContext.current
    val selected = books.firstOrNull { it.id == selectedId }
    if (selected != null) {
        Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding()) {
            BookNotesContent(
                book = selected, store = store, modifier = Modifier.fillMaxSize(),
                onBack = { onSelect(null) },
                onOpen = { page -> onOpenAt(selected, page) },
            )
        }
        return
    }

    var search by remember { mutableStateOf("") }
    val withNotes = books.filter { b ->
        val list = store.notes(b.id)
        list.isNotEmpty() && (search.isBlank() || b.title.contains(search, true) ||
            list.any { it.text.contains(search, true) || (it.quote ?: "").contains(search, true) })
    }.sortedBy { it.title.lowercase() }
    val anyNotes = books.any { store.notes(it.id).isNotEmpty() }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Notes", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground, modifier = Modifier.weight(1f))
            if (anyNotes) IconButton(onClick = { shareText(ctx, store.allNotesMarkdown(books), "BookLand notes") }) {
                Icon(Icons.Default.Share, "Share the notes of every book")
            }
        }
        if (!anyNotes) {
            EmptyState("No highlights yet", "While reading, select text and choose a colour, Save or Add note. Each book keeps its own list here, ready to copy or share.")
            return@Column
        }
        OutlinedTextField(
            search, { search = it }, singleLine = true, label = { Text("Search notes and books") },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        )
        LazyColumn(Modifier.fillMaxSize().padding(top = 8.dp)) {
            items(withNotes, key = { it.id }) { b ->
                Row(
                    Modifier.fillMaxWidth().clickable { onSelect(b.id) }.padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    BookCover(b, store, Modifier.width(44.dp).height(60.dp))
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(b.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onBackground)
                        store.notes(b.id).summary()?.let { Text(it, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                }
                HorizontalDivider()
            }
        }
    }
}

@Composable
fun EmptyState(title: String, message: String, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxSize().padding(40.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onBackground)
        Spacer(Modifier.height(8.dp))
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private enum class NoteFilter(val label: String) { All("All"), Highlights("Highlights"), Notes("Notes") }

/**
 * Every highlight, saved passage and note of one book, with copy and share on each.
 * Used by the Notes tab and by the reader's own "Highlights & notes" sheet.
 */
@Composable
fun BookNotesContent(
    book: Book,
    store: Store,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    onOpen: (Int) -> Unit,
) {
    val ctx = LocalContext.current
    val notes = store.notes(book.id)
    var filter by remember { mutableStateOf(NoteFilter.All) }
    var search by remember { mutableStateOf("") }
    var byPage by remember { mutableStateOf(true) }
    var menu by remember { mutableStateOf(false) }

    val shown = notes.filter { n ->
        val okFilter = when (filter) {
            NoteFilter.All -> true
            NoteFilter.Highlights -> n.isHighlight || n.isQuote
            NoteFilter.Notes -> n.kind == NoteKind.Note
        }
        okFilter && (search.isBlank() || n.text.contains(search, true) || (n.quote ?: "").contains(search, true))
    }.let { if (byPage) it.sortedWith(compareBy<Note>({ it.page }, { it.createdAt })) else it.sortedByDescending { n -> n.createdAt } }

    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
            Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                Text(book.title, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onBackground)
                Text(notes.summary() ?: "Nothing saved yet", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Box {
                IconButton(onClick = { menu = true }, enabled = notes.isNotEmpty()) { Icon(Icons.Default.MoreVert, "Copy, share and sort") }
                DropdownMenu(menu, { menu = false }) {
                    val which = if (filter == NoteFilter.All && search.isBlank()) "all" else "shown"
                    DropdownMenuItem(text = { Text("Copy $which") }, onClick = {
                        menu = false
                        copyText(ctx, book.notesMarkdown(shown))
                        Toast.makeText(ctx, if (shown.size == 1) "Copied 1 item" else "Copied ${shown.size} items", Toast.LENGTH_SHORT).show()
                    })
                    DropdownMenuItem(text = { Text("Share $which…") }, onClick = { menu = false; shareText(ctx, book.notesMarkdown(shown), book.title) })
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text("Order by page") },
                        leadingIcon = { if (byPage) Icon(Icons.Default.Check, null) },
                        onClick = { byPage = true; menu = false },
                    )
                    DropdownMenuItem(
                        text = { Text("Newest first") },
                        leadingIcon = { if (!byPage) Icon(Icons.Default.Check, null) },
                        onClick = { byPage = false; menu = false },
                    )
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NoteFilter.values().forEach { f ->
                FilterChip(selected = filter == f, onClick = { filter = f }, label = { Text(f.label) })
            }
        }
        OutlinedTextField(
            search, { search = it }, singleLine = true, label = { Text("Search this book’s notes") },
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        )
        if (notes.isEmpty()) {
            Text(
                "Nothing yet. Press and hold a word in the book, drag to extend, then choose a colour, Save or Add note.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 24.dp),
            )
        } else if (shown.isEmpty()) {
            Text("No matches.", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 24.dp))
        }
        LazyColumn(Modifier.fillMaxWidth().weight(1f, fill = false)) {
            items(shown, key = { it.id }) { n ->
                NoteRow(book, n, store, ctx, onOpen)
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun NoteRow(book: Book, n: Note, store: Store, ctx: Context, onOpen: (Int) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.Top) {
        Row(Modifier.weight(1f).clickable { onOpen(n.page) }, verticalAlignment = Alignment.Top) {
            if (n.isHighlight) {
                Box(
                    Modifier.padding(top = 2.dp).width(4.dp).height(36.dp).clip(RoundedCornerShape(2.dp))
                        .background((n.color ?: HighlightColor.Yellow).color),
                )
            } else {
                Text(if (n.isQuote) "❝" else "✎", color = MaterialTheme.colorScheme.primary, fontSize = 16.sp, modifier = Modifier.width(18.dp))
            }
            Spacer(Modifier.width(10.dp))
            Column {
                Text(n.text, maxLines = 8, overflow = TextOverflow.Ellipsis, fontSize = 15.sp, color = MaterialTheme.colorScheme.onBackground)
                if (!n.quote.isNullOrEmpty()) {
                    Text(
                        n.quote, maxLines = 3, overflow = TextOverflow.Ellipsis, fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 4.dp, start = 8.dp),
                    )
                }
                Text("Page ${n.page + 1} · ${n.kind.label}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 4.dp))
            }
        }
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "Options") }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem(text = { Text("Copy with page number") }, onClick = {
                    menu = false; copyText(ctx, book.citation(n)); Toast.makeText(ctx, "Copied with page number", Toast.LENGTH_SHORT).show()
                })
                DropdownMenuItem(text = { Text("Copy text only") }, onClick = {
                    menu = false; copyText(ctx, n.text); Toast.makeText(ctx, "Copied text only", Toast.LENGTH_SHORT).show()
                })
                DropdownMenuItem(text = { Text("Share…") }, onClick = { menu = false; shareText(ctx, book.citation(n)) })
                DropdownMenuItem(
                    text = { Text("Delete") },
                    leadingIcon = { Icon(Icons.Default.Delete, null) },
                    onClick = { menu = false; store.notes(book.id).removeAll { it.id == n.id }; store.saveNotes(book.id) },
                )
            }
        }
    }
}
