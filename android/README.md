# BookLand for Android

Native Kotlin + Jetpack Compose reader. Version 0.1 (core reader).

- Library with PDF import (Add PDF, "Open with", or share a PDF to BookLand), covers, reading progress
- Page turn and vertical scroll, page slider, go to page, zoom
- Paper themes (same as iOS)
- Search in book with results list and next/previous
- Press and hold a word, drag to extend; copy, translate, highlight (4 colours) or add a note
- Highlights & notes list; highlights are stored by BookLand next to the book (not inside the PDF)

Build: `ANDROID_HOME=<sdk> ./gradlew assembleRelease` (JDK 17). The APK is signed with the debug key so new builds install over old ones.
