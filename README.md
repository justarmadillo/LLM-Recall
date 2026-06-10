# LLM Recall

LLM Recall is a Flutter app for reviewing LLM-generated CSV flashcards locally, with optional CSV export for Anki.

## Features

- Import CSV from a picked file or pasted text.
- Auto-detect comma, semicolon, or tab delimiters.
- Auto-detect and confirm header rows.
- Choose Question/Answer or Cloze import mode per CSV.
- Mark one question or cloze field; all other fields become back-side extra content.
- Store multiple local review sessions in SQLite.
- Review cards with tap-to-flip, swipe left for Again, swipe right for Good, edit/delete, and undo.
- Render Anki cloze deletions such as `{{c1::answer}}` as hidden prompts, then reveal the answer in bold green text.
- Render HTML card fields.
- Rename and restart sessions.
- Open CSV files from Android file managers or share sheets directly into import preview.
- Save exports to a default CSV folder when configured.
- Export and import full app backups for reinstall, deletion, or phone changes.
- Browse full card contents in a quick-review Cards tab with all/kept/learning/learned/deleted filters.
- Export only kept cards in the mapped Anki CSV order.

## Development

Install Flutter, then run:

```powershell
flutter pub get
flutter analyze
flutter test
```

If this shell does not see Flutter on `PATH`, use the explicit SDK path:

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
C:\flutter\bin\flutter.bat build apk --release
```

For a full architecture and maintenance handoff, see [docs/HANDOFF.md](docs/HANDOFF.md).

## Android

Android is the primary target.

```powershell
flutter run -d android
flutter build apk --release
```

`flutter doctor` should show the Android toolchain as healthy. If Gradle needs to download its wrapper distribution on a slow connection, the project uses the smaller `gradle-9.1.0-bin.zip` distribution.

## Windows Later

The Windows runner is scaffolded, but desktop builds require Visual Studio with the "Desktop development with C++" workload, CMake tools, MSVC build tools, and the Windows SDK.
