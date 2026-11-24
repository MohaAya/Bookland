package app.bookland

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Create
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

/** What other apps handed to BookLand (Open with / Share). */
class Incoming {
    var file by mutableStateOf<Uri?>(null)
    var link by mutableStateOf<String?>(null)
}

class MainActivity : ComponentActivity() {
    private val incoming = Incoming()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val store = Store(this)
        handle(intent)
        setContent { BookLandTheme { AppRoot(store, incoming) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    @Suppress("DEPRECATION")
    private fun handle(i: Intent?) {
        when (i?.action) {
            Intent.ACTION_VIEW -> {
                val d = i.data ?: return
                if (d.scheme == "http" || d.scheme == "https") incoming.link = d.toString() else incoming.file = d
            }
            Intent.ACTION_SEND -> {
                val stream: Uri? =
                    if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    else i.getParcelableExtra(Intent.EXTRA_STREAM)
                if (stream != null) incoming.file = stream
                else {
                    val text = i.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
                    Regex("https?://\\S+").find(text)?.let { incoming.link = it.value }
                }
            }
        }
    }
}

private enum class Tab(val label: String) { Library("Library"), Notes("Notes"), Compare("Compare"), Settings("Settings") }

@Composable
fun AppRoot(store: Store, incoming: Incoming) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var books by remember { mutableStateOf(store.loadBooks()) }
    var tab by remember { mutableStateOf(Tab.Library) }
    var reader by remember { mutableStateOf<Pair<String, Int?>?>(null) }
    var busy by remember { mutableStateOf(false) }
    var pendingFile by remember { mutableStateOf<Uri?>(null) }
    var linkDialog by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var notesBookId by remember { mutableStateOf<String?>(null) }
    var leftId by remember { mutableStateOf<String?>(null) }
    var rightId by remember { mutableStateOf<String?>(null) }

    fun updateBooks(f: (List<Book>) -> List<Book>) {
        books = f(books)
        store.saveBooks(books)
    }

    fun openBook(b: Book, page: Int? = null) {
        updateBooks { l -> l.map { if (it.id == b.id) it.copy(lastOpened = System.currentTimeMillis()) else it } }
        reader = b.id to page
    }

    fun addBook(b: Book) {
        updateBooks { listOf(b) + it }
        Toast.makeText(ctx, "Added “${b.title}”", Toast.LENGTH_SHORT).show()
    }

    fun importMany(uris: List<Uri>) {
        scope.launch {
            busy = true
            val added = withContext(Dispatchers.IO) { uris.mapNotNull { store.importPdf(it) } }
            busy = false
            if (added.size < uris.size) Toast.makeText(ctx, "Some files could not be opened as PDFs.", Toast.LENGTH_LONG).show()
            if (added.isNotEmpty()) {
                updateBooks { added + it }
                if (added.size > 1) Toast.makeText(ctx, "Added ${added.size} PDFs", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun importOne(uri: Uri, title: String) {
        scope.launch {
            busy = true
            val b = withContext(Dispatchers.IO) { store.importPdf(uri, title) }
            busy = false
            if (b == null) Toast.makeText(ctx, "That file could not be opened as a PDF.", Toast.LENGTH_LONG).show() else addBook(b)
        }
    }

    suspend fun downloadLink(text: String): String? = withContext(Dispatchers.IO) {
        try {
            val b = store.importUrl(text)
            withContext(Dispatchers.Main) { addBook(b) }
            null
        } catch (e: IOException) {
            e.message ?: "Couldn’t download that link."
        }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.size == 1) pendingFile = uris.first() else importMany(uris)
    }

    LaunchedEffect(incoming.file) { incoming.file?.let { pendingFile = it; incoming.file = null; reader = null; tab = Tab.Library } }
    LaunchedEffect(incoming.link) { incoming.link?.let { linkDialog = it to true; incoming.link = null; reader = null; tab = Tab.Library } }

    val open = reader?.let { r -> books.firstOrNull { it.id == r.first }?.let { it to r.second } }
    if (open != null) {
        ReaderScreen(
            book = open.first, store = store, startPage = open.second,
            onBack = { reader = null },
            onProgress = { page -> updateBooks { l -> l.map { if (it.id == open.first.id) it.copy(lastPage = page) else it } } },
        )
    } else {
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.weight(1f)) {
                when (tab) {
                    Tab.Library -> LibraryScreen(
                        books = books, store = store, busy = busy,
                        onImportFiles = { picker.launch(arrayOf("application/pdf")) },
                        onAddLink = {
                            val clip = (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip
                                ?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString().orEmpty().trim()
                            linkDialog = (if (clip.startsWith("http", true)) clip else "") to false
                        },
                        onOpen = { openBook(it) },
                        onRename = { b, name -> updateBooks { l -> l.map { if (it.id == b.id) it.copy(title = name.trim().ifEmpty { it.title }) else it } } },
                        onTags = { b, tags -> updateBooks { l -> l.map { if (it.id == b.id) it.copy(tags = tags) else it } } },
                        onDelete = { b ->
                            updateBooks { l -> l.filter { it.id != b.id } }
                            scope.launch(Dispatchers.IO) { store.delete(b) }
                        },
                        onNotes = { b -> notesBookId = b.id; tab = Tab.Notes },
                    )
                    Tab.Notes -> NotesTab(books, store, notesBookId, { notesBookId = it }) { b, page -> openBook(b, page) }
                    Tab.Compare -> CompareTab(
                        books, store, leftId, rightId, { l, r -> leftId = l; rightId = r },
                        { id, page -> updateBooks { l -> l.map { if (it.id == id) it.copy(lastPage = page) else it } } },
                    )
                    Tab.Settings -> SettingsTab(books, store)
                }
            }
            NavigationBar {
                Tab.values().forEach { t ->
                    NavigationBarItem(
                        selected = tab == t,
                        onClick = { if (t == Tab.Notes && tab != Tab.Notes) notesBookId = null; tab = t },
                        icon = {
                            Icon(
                                when (t) {
                                    Tab.Library -> Icons.Default.Home
                                    Tab.Notes -> Icons.Default.Create
                                    Tab.Compare -> CompareIcon
                                    Tab.Settings -> Icons.Default.Settings
                                }, t.label,
                            )
                        },
                        label = { Text(t.label) },
                    )
                }
            }
        }
    }

    pendingFile?.let { uri ->
        TitleDialog(
            initial = remember(uri) { store.titleFor(uri) },
            onConfirm = { title -> pendingFile = null; importOne(uri, title) },
            onDismiss = { pendingFile = null },
        )
    }
    linkDialog?.let { (initial, auto) ->
        LinkDialog(initial, auto, onDismiss = { linkDialog = null }, onSubmit = { downloadLink(it) })
    }
}
