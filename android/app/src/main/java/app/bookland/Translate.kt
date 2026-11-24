package app.bookland

import android.annotation.SuppressLint
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import java.net.URLEncoder
import androidx.compose.ui.Alignment

val TranslateLanguages = listOf(
    "en" to "English", "fa" to "Persian (فارسی)", "ar" to "Arabic (العربية)", "fi" to "Finnish", "sv" to "Swedish",
    "tr" to "Turkish", "de" to "German", "fr" to "French", "es" to "Spanish", "it" to "Italian", "pt" to "Portuguese",
    "nl" to "Dutch", "ru" to "Russian", "zh-CN" to "Chinese", "ja" to "Japanese", "ko" to "Korean", "hi" to "Hindi", "ur" to "Urdu",
)

fun languageName(code: String) = TranslateLanguages.firstOrNull { it.first == code }?.second ?: code

@Composable
fun LanguageMenu(store: Store, expanded: Boolean, onDismiss: () -> Unit) {
    DropdownMenu(expanded, onDismiss) {
        TranslateLanguages.forEach { (code, name) ->
            DropdownMenuItem(
                text = { Text(name) },
                leadingIcon = { if (store.translateLang == code) Icon(Icons.Default.Check, null) },
                onClick = { store.translateLang = code; onDismiss() },
            )
        }
    }
}

/** Google Translate shown inside the app, for the selected word or sentence. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun TranslateDialog(text: String, store: Store, onDismiss: () -> Unit) {
    val query = text.trim().take(1500)
    val lang = store.translateLang
    var menu by remember { mutableStateOf(false) }
    var engine by remember { mutableStateOf(0) } // 0 = Google, 1 = Bing
    val enc = URLEncoder.encode(query, "UTF-8")
    val url = if (engine == 0)
        "https://translate.google.com/?sl=auto&tl=$lang&text=$enc&op=translate"
    else
        "https://www.bing.com/translator?from=auto&to=${if (lang == "zh-CN") "zh-Hans" else lang}&text=$enc"
    val ctx = androidx.compose.ui.platform.LocalContext.current

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(
            Modifier.fillMaxWidth(0.94f).fillMaxHeight(0.74f),
            shape = RoundedCornerShape(24.dp), tonalElevation = 6.dp,
        ) {
            Column {
                Row(Modifier.padding(start = 20.dp, end = 4.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Translate", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f))
                    androidx.compose.foundation.layout.Box {
                        TextButton(onClick = { menu = true }) {
                            Text("To ${languageName(lang).substringBefore(" (")}")
                            Icon(Icons.Default.KeyboardArrowDown, null)
                        }
                        LanguageMenu(store, menu) { menu = false }
                    }
                    IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, "Close") }
                }
                Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    androidx.compose.material3.FilterChip(engine == 0, { engine = 0 }, { Text("Google") })
                    androidx.compose.foundation.layout.Spacer(Modifier.padding(horizontal = 4.dp))
                    androidx.compose.material3.FilterChip(engine == 1, { engine = 1 }, { Text("Bing") })
                    androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                    TextButton(onClick = {
                        runCatching { ctx.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url)).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) }
                    }) { Text("Open in browser") }
                }
                Text(
                    query, maxLines = 2, overflow = TextOverflow.Ellipsis, fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
                )
                AndroidView(
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    factory = { ctx ->
                        WebView(ctx).apply {
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = true
                            // Look like regular mobile Chrome instead of an embedded "wv" browser.
                            settings.userAgentString = settings.userAgentString.replace("; wv", "")
                            webViewClient = WebViewClient()
                        }
                    },
                    update = { wv ->
                        if (wv.tag != url) { wv.tag = url; wv.loadUrl(url) }
                    },
                    onRelease = { it.destroy() },
                )
            }
        }
    }
}
