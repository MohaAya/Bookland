package app.bookland

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun LibraryScreen(
    books: List<Book>,
    store: Store,
    busy: Boolean,
    onImportFiles: () -> Unit,
    onAddLink: () -> Unit,
    onOpen: (Book) -> Unit,
    onRename: (Book, String) -> Unit,
    onTags: (Book, List<String>) -> Unit,
    onDelete: (Book) -> Unit,
    onNotes: (Book) -> Unit,
) {
    var search by remember { mutableStateOf("") }
    var renaming by remember { mutableStateOf<Book?>(null) }
    var tagging by remember { mutableStateOf<Book?>(null) }
    var deleting by remember { mutableStateOf<Book?>(null) }
    var sortMenu by remember { mutableStateOf(false) }
    var addMenu by remember { mutableStateOf(false) }

    val sort = store.sort
    val visible = books.filter {
        search.isBlank() || it.title.contains(search, true) || it.tags.any { t -> t.contains(search, true) }
    }.let { list ->
        when (sort) {
            LibrarySort.Recent -> list.sortedByDescending { if (it.lastOpened > 0) it.lastOpened else it.addedAt }
            LibrarySort.Title -> list.sortedBy { it.title.lowercase() }
            LibrarySort.Added -> list.sortedByDescending { it.addedAt }
        }
    }
    val recent = books.filter { it.lastOpened > 0 }.maxByOrNull { it.lastOpened }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Library", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground, modifier = Modifier.weight(1f))
            if (busy) CircularProgressIndicator(Modifier.height(24.dp).width(24.dp), strokeWidth = 2.dp)
            Box {
                TextButton(onClick = { sortMenu = true }, enabled = books.isNotEmpty()) { Text(sort.label); Icon(Icons.Default.KeyboardArrowDown, null) }
                DropdownMenu(sortMenu, { sortMenu = false }) {
                    LibrarySort.values().forEach { s ->
                        DropdownMenuItem(
                            text = { Text(s.label) },
                            leadingIcon = { if (sort == s) Icon(Icons.Default.Check, null) },
                            onClick = { store.sort = s; sortMenu = false },
                        )
                    }
                }
            }
            Box {
                IconButton(onClick = { addMenu = true }) { Icon(Icons.Default.Add, "Add a PDF") }
                DropdownMenu(addMenu, { addMenu = false }) {
                    DropdownMenuItem(text = { Text("Import from Files") }, onClick = { addMenu = false; onImportFiles() })
                    DropdownMenuItem(text = { Text("Add from a link…") }, onClick = { addMenu = false; onAddLink() })
                }
            }
        }

        if (books.isEmpty()) {
            Column(
                Modifier.fillMaxSize().padding(40.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("Your library is empty", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onBackground)
                Spacer(Modifier.height(8.dp))
                Text(
                    "Import PDFs from your phone, or paste a web link. You can also open a PDF from Files, Telegram, Mail or a browser and choose BookLand.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(20.dp))
                Button(onClick = onImportFiles) { Text("Import a PDF") }
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = onAddLink) { Text("Add from a link") }
            }
            return@Column
        }

        OutlinedTextField(
            search, { search = it }, singleLine = true, label = { Text("Search titles and tags") },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
        )

        LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp)) {
            if (search.isBlank() && recent != null) {
                item("continue") {
                    Text("Continue reading", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 20.dp, top = 12.dp, bottom = 6.dp))
                    Surface(
                        color = MaterialTheme.colorScheme.primaryContainer,
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth().clickable { onOpen(recent) },
                    ) {
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            BookCover(recent, store, Modifier.width(60.dp).height(82.dp))
                            Spacer(Modifier.width(14.dp))
                            Column(Modifier.weight(1f)) {
                                Text(recent.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onPrimaryContainer)
                                Text("Page ${recent.lastPage + 1} of ${recent.pageCount}", fontSize = 13.sp, color = MaterialTheme.colorScheme.onPrimaryContainer)
                                LinearProgressIndicator(progress = { recent.progress }, modifier = Modifier.padding(top = 8.dp).fillMaxWidth())
                            }
                        }
                    }
                }
            }
            item("header") {
                Text(
                    if (search.isBlank()) "All books · ${visible.size}" else "Results · ${visible.size}",
                    fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 4.dp),
                )
            }
            if (visible.isEmpty()) {
                item("none") { Text("No books match “$search”.", Modifier.padding(20.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            items(visible, key = { it.id }) { book ->
                var menu by remember { mutableStateOf(false) }
                Row(
                    Modifier.fillMaxWidth().clickable { onOpen(book) }.padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    BookCover(book, store, Modifier.width(52.dp).height(70.dp))
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(book.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onBackground)
                        if (book.tags.isNotEmpty()) {
                            Text(book.tags.joinToString("  ·  ") { "#$it" }, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.primary)
                        }
                        Text(
                            "Page ${book.lastPage + 1} of ${book.pageCount}" + (store.notes(book.id).summary()?.let { " · $it" } ?: ""),
                            fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        LinearProgressIndicator(progress = { book.progress }, modifier = Modifier.padding(top = 6.dp).fillMaxWidth())
                    }
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "More") }
                        DropdownMenu(menu, { menu = false }) {
                            DropdownMenuItem(text = { Text("Highlights & notes") }, onClick = { menu = false; onNotes(book) })
                            DropdownMenuItem(text = { Text("Rename") }, onClick = { menu = false; renaming = book })
                            DropdownMenuItem(text = { Text("Edit tags") }, onClick = { menu = false; tagging = book })
                            HorizontalDivider()
                            DropdownMenuItem(text = { Text("Delete…") }, onClick = { menu = false; deleting = book })
                        }
                    }
                }
            }
        }
    }

    renaming?.let { b ->
        var name by remember(b.id) { mutableStateOf(b.title) }
        AlertDialog(
            onDismissRequest = { renaming = null },
            title = { Text("Rename") },
            text = { OutlinedTextField(name, { name = it }, singleLine = true, label = { Text("Title") }) },
            confirmButton = { TextButton(onClick = { onRename(b, name); renaming = null }) { Text("Save") } },
            dismissButton = { TextButton(onClick = { renaming = null }) { Text("Cancel") } },
        )
    }
    tagging?.let { b ->
        var text by remember(b.id) { mutableStateOf(b.tags.joinToString(", ")) }
        AlertDialog(
            onDismissRequest = { tagging = null },
            title = { Text("Tags") },
            text = {
                Column {
                    OutlinedTextField(text, { text = it }, label = { Text("research, thesis, to read") })
                    Text("Separate tags with commas.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    onTags(b, text.split(',').map { it.trim().removePrefix("#") }.filter { it.isNotEmpty() }.distinct())
                    tagging = null
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { tagging = null }) { Text("Cancel") } },
        )
    }
    deleting?.let { b ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("Delete “${b.title}”?") },
            text = { Text("This removes the PDF and its highlights and notes from this phone. It cannot be undone.") },
            confirmButton = { TextButton(onClick = { onDelete(b); deleting = null }) { Text("Delete PDF and notes") } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("Cancel") } },
        )
    }
}

@Composable
fun BookCover(book: Book, store: Store, modifier: Modifier) {
    val image by produceState<ImageBitmap?>(null, book.id) {
        value = withContext(Dispatchers.IO) { BitmapFactory.decodeFile(store.coverFile(book.id).path)?.asImageBitmap() }
    }
    val shape = RoundedCornerShape(8.dp)
    Box(modifier.clip(shape).background(Color.White).border(1.dp, MaterialTheme.colorScheme.surfaceVariant, shape)) {
        image?.let { Image(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter) }
    }
}

/** Paste or type a link; downloads the PDF into the library. [onSubmit] returns an error message, or null on success. */
@Composable
fun LinkDialog(initial: String, autoStart: Boolean, onDismiss: () -> Unit, onSubmit: suspend (String) -> String?) {
    var text by remember { mutableStateOf(initial) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun go() {
        if (busy) return
        scope.launch {
            busy = true; error = null
            val e = onSubmit(text)
            busy = false
            if (e == null) onDismiss() else error = e
        }
    }
    LaunchedEffect(Unit) { if (autoStart && text.isNotBlank()) go() }

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("Add from a link") },
        text = {
            Column {
                OutlinedTextField(text, { text = it }, label = { Text("Paste or type a link") }, enabled = !busy, modifier = Modifier.fillMaxWidth(), minLines = 2)
                if (busy) {
                    Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.height(20.dp).width(20.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(10.dp))
                        Text("Downloading…")
                    }
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp)) }
                Text(
                    "Works with a direct link to a PDF, and with Dropbox and Google Drive share links. The file is saved on this phone, so you can read it offline.",
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 10.dp),
                )
            }
        },
        confirmButton = { TextButton(enabled = text.isNotBlank() && !busy, onClick = { go() }) { Text("Download") } },
        dismissButton = { TextButton(enabled = !busy, onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
fun TitleDialog(initial: String, onConfirm: (String) -> Unit, onDismiss: () -> Unit) {
    var title by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add PDF") },
        text = {
            Column {
                OutlinedTextField(title, { title = it }, singleLine = true, label = { Text("Library title") })
                Text(
                    "The PDF is copied into BookLand, so it stays available even if the original disappears from the other app.",
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp),
                )
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm(title) }) { Text("Import") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
