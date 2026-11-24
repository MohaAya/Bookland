# BookLand for Android

Native Kotlin + Jetpack Compose reader. Version 0.3 (full feature set + pinch zoom + in-app Google Translate).

- Library: covers, progress, tags, sort (recently read / title / date added), search titles and tags, Continue reading, rename, tags, delete
- Add PDFs: import several at once, Open with / Share from Files, Telegram, Mail or a browser, and **Add from a link** (direct links, Dropbox and Google Drive share links)
- Reader: page turn and vertical scroll, page slider, jump to page, zoom and fit, tap to hide controls, keep screen on, page history, Pages & Index (thumbnails and the PDF's own outline), search with next/previous
- Nine paper themes (same as iOS, including the Sketchbook paper)
- Press and hold a word, drag to extend; four highlight colours, Add note, Save selection to notes, Copy, Translate; undo last highlight, remove a highlight by tapping it
- Notes tab: per-book highlights, saved passages and notes, filter, search, order, copy with page number, share, export as Markdown (one book or all books)
- Compare: two books side by side (landscape) or stacked (portrait), each with its own page, reading mode and controls, plus swap
- Settings and About

Highlights are stored by BookLand next to the book (not inside the PDF file).

Build: `ANDROID_HOME=<sdk> ./gradlew assembleRelease` (JDK 17). The APK is signed with the debug key so new builds install over old ones.
