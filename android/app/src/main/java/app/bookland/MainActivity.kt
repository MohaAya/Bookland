package app.bookland

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private val incoming = mutableStateOf<Uri?>(null)

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
        val uri: Uri? = when (i?.action) {
            Intent.ACTION_VIEW -> i.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else i.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri != null) incoming.value = uri
    }
}

@Composable
fun AppRoot(store: Store, incoming: MutableState<Uri?>) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var books by remember { mutableStateOf(store.loadBooks()) }
    var openId by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }

    fun importAll(uris: List<Uri>) {
        if (uris.isEmpty()) return
        scope.launch {
            busy = true
            val added = withContext(Dispatchers.IO) { uris.mapNotNull { store.importPdf(it) } }
            if (added.size < uris.size) Toast.makeText(ctx, "Some files could not be opened as PDFs.", Toast.LENGTH_LONG).show()
            if (added.isNotEmpty()) {
                books = (added + books)
                withContext(Dispatchers.IO) { store.saveBooks(books) }
                if (uris.size == 1) openId = added.first().id
            }
            busy = false
        }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { importAll(it) }

    LaunchedEffect(incoming.value) {
        incoming.value?.let { importAll(listOf(it)); incoming.value = null }
    }

    val open = books.firstOrNull { it.id == openId }
    if (open != null) {
        ReaderScreen(
            book = open,
            store = store,
            onBack = { openId = null },
            onProgress = { page ->
                books = books.map { if (it.id == open.id) it.copy(lastPage = page, lastOpened = System.currentTimeMillis()) else it }
                store.saveBooks(books)
            },
        )
    } else {
        LibraryScreen(
            books = books.sortedByDescending { it.lastOpened },
            busy = busy,
            store = store,
            onAdd = { picker.launch(arrayOf("application/pdf")) },
            onOpen = { openId = it.id },
            onRename = { b, name ->
                books = books.map { if (it.id == b.id) it.copy(title = name.trim().ifEmpty { it.title }) else it }
                store.saveBooks(books)
            },
            onDelete = { b ->
                books = books.filter { it.id != b.id }
                store.saveBooks(books)
                scope.launch(Dispatchers.IO) { store.delete(b) }
            },
        )
    }
}
