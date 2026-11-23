package app.bookland

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Accent = Color(0xFF1F6B7A)
val AccentDark = Color(0xFF61BDC7)

@Composable
fun BookLandTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scheme = if (dark) darkColorScheme(
        primary = AccentDark, onPrimary = Color(0xFF00363D),
        background = Color(0xFF12161B), surface = Color(0xFF1B2128),
        surfaceVariant = Color(0xFF26303A), onSurfaceVariant = Color(0xFFB6C2CC),
        primaryContainer = Color(0xFF1B4A53), onPrimaryContainer = Color(0xFFBDEBF2),
    ) else lightColorScheme(
        primary = Accent, onPrimary = Color.White,
        background = Color(0xFFF7F4EA), surface = Color(0xFFFFFDF6),
        surfaceVariant = Color(0xFFEAE6D6), onSurfaceVariant = Color(0xFF4A5560),
        primaryContainer = Color(0xFFCDEAEF), onPrimaryContainer = Color(0xFF0B3A43),
    )
    MaterialTheme(colorScheme = scheme, content = content)
}
