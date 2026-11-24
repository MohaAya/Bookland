package app.bookland

import android.content.Intent
import android.net.Uri
import android.text.format.Formatter
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
private fun SectionTitle(text: String) {
    Text(text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(start = 20.dp, top = 20.dp, bottom = 6.dp))
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = MaterialTheme.colorScheme.onBackground)
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Para(text: String) {
    Text(text, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
}

@Composable
fun SettingsTab(books: List<Book>, store: Store) {
    val ctx = LocalContext.current
    var showTheme by remember { mutableStateOf(false) }
    val version = remember {
        runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }.getOrNull() ?: "?"
    }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding().verticalScroll(rememberScrollState())) {
        Text("Settings", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground, modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 4.dp))

        SectionTitle("Reading")
        Row(Modifier.fillMaxWidth().clickable { showTheme = true }.padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Paper", color = MaterialTheme.colorScheme.onBackground)
            Text(store.theme.label, color = MaterialTheme.colorScheme.primary)
        }
        Text("Turning pages", Modifier.padding(horizontal = 20.dp, vertical = 6.dp), color = MaterialTheme.colorScheme.onBackground)
        ReadingMode.values().forEach { m ->
            Row(Modifier.fillMaxWidth().clickable { store.mode = m }.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                RadioButton(selected = store.mode == m, onClick = { store.mode = m })
                Text(m.label, color = MaterialTheme.colorScheme.onBackground)
            }
        }
        var langMenu by remember { mutableStateOf(false) }
        androidx.compose.foundation.layout.Box {
            Row(Modifier.fillMaxWidth().clickable { langMenu = true }.padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Translate to", color = MaterialTheme.colorScheme.onBackground)
                Text(languageName(store.translateLang), color = MaterialTheme.colorScheme.primary)
            }
            LanguageMenu(store, langMenu) { langMenu = false }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Keep screen on while reading", Modifier.weight(1f), color = MaterialTheme.colorScheme.onBackground)
            Switch(checked = store.keepAwake, onCheckedChange = { store.keepAwake = it })
        }

        SectionTitle("Library")
        InfoRow("Books", "${books.size}")
        InfoRow("Space used", Formatter.formatFileSize(ctx, store.storageBytes(books)))
        Para("Highlights and notes are kept inside BookLand, next to each book, and are removed together with it.")

        SectionTitle("Importing PDFs")
        Para("Files, Telegram, Mail or a browser: open the PDF or tap Share, then choose BookLand.")
        Para("Library → + → Import from Files, or Add from a link (direct links, Dropbox and Google Drive share links).")
        Para("A link to a PDF in a browser or in a message can also open straight in BookLand.")

        SectionTitle("About BookLand")
        InfoRow("BookLand", "Version $version")
        Para("A calm research reading space.")
        Para("BookLand makes it convenient to read two books at the same time. Open two different PDFs, move through their pages independently, and compare them side by side without leaving the reading workspace.")
        Para("Compared with a standard PDF viewer, BookLand combines a local book library, titles and tags, page history, thumbnails and index navigation, search, notes, highlights, study themes, zoom, and independent comparison panes in one place.")
        HorizontalDivider(Modifier.padding(vertical = 8.dp))
        InfoRow("Concept and design ideas", "Mohammad Ayati")
        InfoRow("Created", "August 2026")
        Para("The original BookLand product concept, research-reading workflow, information architecture, interaction ideas, visual direction, study themes, and comparison-reader design are attributed to Mohammad Ayati.")
        InfoRow("Logo designer", "Lida Samadi")
        TextButton(onClick = {
            ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.instagram.com/lidasamadi.design/")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }, modifier = Modifier.padding(horizontal = 12.dp)) { Text("Instagram · @lidasamadi.design") }
        Para("BookLand logo artwork and logo-specific visual-identity design are credited to Lida Samadi. These logo rights are separate from the MIT-licensed source code.")
        Para("© Mohammad Ayati, August 2026. BookLand source code is released under the MIT License.")
        Para("Imported PDFs, annotations, and other user-provided materials remain subject to their respective owners’ rights.")
        androidx.compose.foundation.layout.Spacer(Modifier.padding(bottom = 24.dp))
    }

    if (showTheme) ThemeDialog(store) { showTheme = false }
}
