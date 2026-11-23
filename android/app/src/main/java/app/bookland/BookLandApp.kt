package app.bookland

import android.app.Application
import android.content.Context
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

object PdfBoxInit {
    private var done = false
    @Synchronized
    fun ensure(context: Context) {
        if (!done) {
            PDFBoxResourceLoader.init(context.applicationContext)
            done = true
        }
    }
}

class BookLandApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // PDFBox needs its font/glyph resources; warm it up off the main thread so the first text selection is quick.
        CoroutineScope(Dispatchers.IO).launch { runCatching { PdfBoxInit.ensure(this@BookLandApp) } }
    }
}
