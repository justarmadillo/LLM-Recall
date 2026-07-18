## Stack
- Flutter Material 3 — Android-first local review UI; Windows runner scaffold exists but is not primary.
- sqflite + sqflite_common_ffi — SQLite persistence on mobile plus desktop/tests via FFI.
- path_provider + path — stable documents-dir DB/export paths; DB filename is `preanki.db`.
- file_picker — CSV/TSV/TXT import, save-as export, directory setting, JSON backup import/export.
- csv — strict CSV decoder/encoder; wrapped by `CsvTools` for delimiter/header/relaxed parsing.
- flutter_widget_from_html_core — renders card fields as escaped text or constrained HTML/images/tables.
- collection — `firstWhereOrNull`/`firstOrNull` for review queue selection.
- intl — UI date/title formatting only; storage uses ISO strings.
- Android Kotlin MethodChannel — external CSV/text open/share intents arrive on `llm_recall/imports`.
## Architecture
Android VIEW/SEND intent -> MainActivity.decodeText -> MethodChannel llm_recall/imports
                                     |                                |
file_picker/clipboard -> ImportScreen -> CsvTools.parse/decodeBytes -> field mapping validation
                                     |                                |
                                     v                                v
                              PreAnkiAppState.createSessionFromImport/addCard/update/review
                                     |
                                     v
                              PreAnkiRepository -> SQLite tables: sessions/cards/card_review_items/app_settings
                                     |
                 +-------------------+-------------------+
                 v                                       v
          SessionScreen Review tab                  Cards tab/settings/home
          ReviewCard queue + ClozeTools             CRUD/export/backup/folders
                 |                                       |
                 v                                       v
          HtmlCardText display                     ExportService/CsvTools.exportRows
## File Map
pubspec.yaml — app identity `preanki`/visible LLM Recall; direct deps show local SQLite/CSV/HTML/file workflows — imports none.
lib/main.dart — initializes repository before `runApp`; global `AppScope`; listens for Android import bridge — imports `app_state`, `repository`, `import_bridge`, screens.
lib/app_state.dart — UI-facing state machine; busy/error wrapper; review queue/undo/export/backup orchestration — imports `csv_tools`, `export_service`, `repository`, `models`.
lib/repository.dart — SQLite schema v7, migrations, review-item expansion, backup import/export, settings — imports `sqflite`, `sqflite_common_ffi`, `path_provider`, `cloze_tools`, `models`.
lib/models.dart — persisted session/card/review model; JSON DB mapping; expanded review key math — imports `dart:convert`.
lib/csv_tools.dart — CSV decoding/parsing/export; delimiter scoring; relaxed malformed-quote fallback; header inference — imports `csv`.
lib/cloze_tools.dart — Anki cloze regex/rendering/wrap/number helpers; answer HTML escaping — imports `dart:convert`.
lib/export_service.dart — kept-card CSV save flow; default folder direct-write then picker fallback — imports `file_picker`, `path`, `csv_tools`, `models`.
lib/import_bridge.dart — Dart side of `llm_recall/imports`; initial import consumption and live import callback — imports `flutter/services`.
lib/design_system.dart — Notion-like warm Material theme, reusable surfaces/badges/icon tiles — imports Flutter Material.
lib/screens/home_screen.dart — session list, progress badges, session actions, import/settings navigation — imports `app_state`, `models`, `intl`, `import_screen`, `session_screen`, `settings_screen`.
lib/screens/import_screen.dart — CSV file/clipboard/text preview, header toggle, QA/cloze mapping, session creation route — imports `file_picker`, `services`, `intl`, `csv_tools`, `cloze_tools`, `models`.
lib/screens/session_screen.dart — review tab with flip/swipe/undo/navigation; cards tab with add/edit/delete/restore filters — imports `app_state`, `cloze_tools`, `models`, `card_editor_dialog`, `html_card_text`.
lib/screens/settings_screen.dart — export folder setting and full app backup replace/export UI — imports `file_picker`, `main`, `design_system`.
lib/widgets/card_editor_dialog.dart — add/edit dialog; cloze selection toolbar/button; add-mode cloze validation — imports `cloze_tools`, `models`, `design_system`.
lib/widgets/html_card_text.dart — plain text escaping/newline conversion plus HTML/table/img constraints — imports `flutter_widget_from_html_core`, `design_system`.
android/app/src/main/kotlin/com/preanki/preanki/MainActivity.kt — Android intent reader; UTF-8/UTF-16 decode; MethodChannel payload queueing — imports Flutter engine/channel APIs.
android/app/src/main/AndroidManifest.xml — launcher plus CSV/TSV/text VIEW/SEND filters; `exported=true`; `singleTop` — imports none.
android/app/build.gradle.kts — stable `com.preanki.preanki` id; Java/Kotlin 17; release uses debug signing locally — imports Flutter Gradle plugin.
DESIGN.md — external Notion-style visual reference, not product architecture — imports none.
docs/HANDOFF.md — verbose human handoff; do not load instead of this index unless deep context needed — imports none.
test/repository_test.dart — verifies schema behavior: backup strictness, cloze review item expansion, aggregate states — imports `repository`, `models`, `sqflite_common_ffi`.
test/csv_tools_test.dart — specifies whitespace preservation, malformed quotes, UTF-16/Windows-1252, conservative headers — imports `csv_tools`.
test/app_state_test.dart — specifies neutral navigation and distinct cloze-number review queue behavior — imports `app_state`, `repository`, `models`.
test/cloze_tools_test.dart — specifies cloze hints, escaping, per-number rendering, next-number wrapping — imports `cloze_tools`.
test/widget_test.dart — specifies editor field mapping and add-dialog cloze wrapping — imports `card_editor_dialog`, `models`.
## Key Symbols
main(): Future<void> — initializes SQLite and app state.
PreAnkiApp(appState: PreAnkiAppState): StatefulWidget — owns MaterialApp/import navigation.
AppScope.of(context: BuildContext): PreAnkiAppState — returns global app state.
PreAnkiAppState.nextReviewItem: ReviewCard? — selects next unlearned queue item.
PreAnkiAppState.reviewQueueCount: int — counts kept unlearned review items.
PreAnkiAppState.reviewQueuePosition: int — 1-based queue cursor.
PreAnkiAppState.load(): Future<void> — loads sessions and export setting.
PreAnkiAppState.openSession(sessionId: int): Future<void> — loads session/cards/review items.
PreAnkiAppState.createSessionFromImport(...): Future<int?> — persists mapped CSV rows.
PreAnkiAppState.addCard(sessionId: int, fields: Map<String,String>): Future<void> — appends manual card.
PreAnkiAppState.deleteSession(sessionId: int): Future<void> — removes session and open state.
PreAnkiAppState.renameSession(sessionId: int, title: String): Future<void> — trims and updates title.
PreAnkiAppState.restartSession(sessionId: int): Future<void> — resets kept review states.
PreAnkiAppState.learnedAndAdvance(item: ReviewCard): Future<void> — marks item learned.
PreAnkiAppState.againAndAdvance(item: ReviewCard): Future<void> — marks item again.
PreAnkiAppState.deleteAndAdvance(item: ReviewCard): Future<void> — deletes whole stored note.
PreAnkiAppState.undoReviewAction(): Future<void> — restores last review mutation.
PreAnkiAppState.moveReviewPointer(delta: int): Future<void> — moves cursor without grading.
PreAnkiAppState.updateCard(card: Flashcard, fields: Map<String,String>): Future<void> — replaces field JSON.
PreAnkiAppState.setCardStatus(card: Flashcard, status: CardStatus): Future<void> — delete/restore stored card.
PreAnkiAppState.exportSession(sessionId: int): Future<String?> — saves kept-card CSV.
PreAnkiAppState.setDefaultExportFolder(folder: String?): Future<void> — persists export folder setting.
PreAnkiAppState.exportAppBackup(): Future<String?> — writes JSON backup.
PreAnkiAppState.importAppBackup(): Future<bool> — replaces all local data.
ReviewUndo(...): ReviewUndo — stores one reversible review action.
PreAnkiRepository.initialize(): Future<void> — opens SQLite database.
PreAnkiRepository.close(): Future<void> — closes database handle.
PreAnkiRepository.listSessions(): Future<List<PreAnkiSession>> — returns sessions with counts.
PreAnkiRepository.getSession(id: int): Future<PreAnkiSession?> — loads counted session.
PreAnkiRepository.createSession(...): Future<int> — inserts session/cards/review items.
PreAnkiRepository.addCard(sessionId: int, fields: Map<String,String>): Future<int> — inserts next original index.
PreAnkiRepository.deleteSession(id: int): Future<void> — deletes review items/cards/session.
PreAnkiRepository.updateSessionTitle(sessionId: int, title: String): Future<void> — updates title timestamp.
PreAnkiRepository.restartSessionReview(sessionId: int): Future<void> — resets kept item states.
PreAnkiRepository.listCards(sessionId: int, filter: CardFilter): Future<List<Flashcard>> — queries stored cards.
PreAnkiRepository.getCard(id: int): Future<Flashcard?> — loads single card.
PreAnkiRepository.listReviewCards(sessionId: int): Future<List<ReviewCard>> — joins expanded review items.
PreAnkiRepository.updateCardFields(cardId: int, fields: Map<String,String>): Future<void> — resyncs cloze review items.
PreAnkiRepository.setCardStatus(cardId: int, status: CardStatus): Future<void> — toggles kept/deleted.
PreAnkiRepository.setCardReviewState(cardId: int, reviewState: ReviewState): Future<void> — updates all card items.
PreAnkiRepository.setReviewItemState(cardId: int, clozeNumber: int, reviewState: ReviewState): Future<void> — updates one review item.
PreAnkiRepository.updateReviewIndex(sessionId: int, reviewIndex: int): Future<void> — persists queue pointer.
PreAnkiRepository.exportBackup(): Future<Map<String,Object?>> — serializes DB/settings backup.
PreAnkiRepository.importBackup(backup: Map<String,Object?>): Future<void> — validates then replaces DB.
PreAnkiRepository.getSetting(key: String): Future<String?> — reads app setting.
PreAnkiRepository.setSetting(key: String, value: String?): Future<void> — upserts/deletes app setting.
CardStatus.fromStorage(value: String): CardStatus — maps unknown to kept.
ReviewState.storageValue: String — maps newCard to `new`.
ReviewState.label: String — UI badge label.
ReviewState.fromStorage(value: String): ReviewState — maps unknown to newCard.
SessionCardType.storageValue: String — maps enum to DB value.
SessionCardType.fromStorage(value: String?): SessionCardType — maps unknown to QA.
PreAnkiSession.keptCount: int — total minus deleted floor zero.
PreAnkiSession.reviewCount: int — review items else kept cards.
PreAnkiSession.learningCount: int — reviewCount minus learned floor zero.
PreAnkiSession.progress: double — learned/reviewCount ratio.
PreAnkiSession.copyWith(...): PreAnkiSession — copies session value.
PreAnkiSession.toDb(): Map<String,Object?> — encodes JSON DB row.
PreAnkiSession.fromDb(row: Map<String,Object?>): PreAnkiSession — decodes counted DB row.
ReviewCard.isCloze: bool — clozeNumber greater than zero.
ReviewCard.reviewKey: int — originalIndex*1000000+clozeNumber.
Flashcard.isDeleted: bool — status is deleted.
Flashcard.isLearned: bool — aggregate state learned.
Flashcard.isLearning: bool — kept and not learned.
Flashcard.copyWith(...): Flashcard — copies card value.
Flashcard.toDb(): Map<String,Object?> — encodes card DB row.
Flashcard.fromDb(row: Map<String,Object?>): Flashcard — decodes JSON fields/date/status.
CsvImportResult.inferredHeaders: List<String> — headers or Column N.
CsvImportResult.dataRows(headerOverride: bool?): List<List<String>> — skips header when active.
CsvTools.decodeBytes(bytes: List<int>): String — detects UTF/BOM/Windows-1252.
CsvTools.parse(input: String): CsvImportResult — detects delimiter/header/rows.
CsvTools.exportRows(...): String — encodes selected fields to CSV.
CsvTools.rowsToCards(rows: List<List<String>>, fieldNames: List<String>): List<Map<String,String>> — maps rows to fields.
ClozeTools.hasCloze(value: String): bool — detects Anki cloze syntax.
ClozeTools.fieldsContainCloze(fields: Map<String,String>): bool — scans field values.
ClozeTools.questionText(value: String): String — hides all clozes.
ClozeTools.questionTextForNumber(value: String, clozeNumber: int): String — hides one cloze number.
ClozeTools.answerText(value: String): String — strips cloze markup.
ClozeTools.answerHtml(value: String): String — reveals all answers emphasized.
ClozeTools.answerHtmlForNumber(value: String, clozeNumber: int): String — emphasizes requested answer.
ClozeTools.wrapRange(value: String, start: int, end: int, number?: int): String — wraps selection as cloze.
ClozeTools.nextClozeNumber(value: String): int — max cloze number plus one.
ClozeTools.clozeNumbers(value: String): List<int> — sorted distinct cloze numbers.
ExportService.buildSessionCsv(session: PreAnkiSession, cards: List<Flashcard>): String — builds ordered CSV.
ExportService.saveSessionCsv(session: PreAnkiSession, cards: List<Flashcard>, initialDirectory?: String): Future<String?> — saves CSV cross-platform.
IncomingCsvImport.fromPlatform(payload: Object?): IncomingCsvImport? — validates channel payload.
ImportBridge.listen(onImport: Function): void — handles live incomingCsv calls.
ImportBridge.consumeInitialImport(): Future<IncomingCsvImport?> — fetches queued startup import.
ImportFormat.label: String — maps import mode to UI text.
HomeScreen.build(context: BuildContext): Widget — renders sessions/actions/import FAB.
ImportScreen(initialCsvText?: String, initialSourceName?: String): StatefulWidget — CSV import/mapping route.
SessionScreen(sessionId: int): StatefulWidget — review/cards tab route.
SettingsScreen.build(context: BuildContext): Widget — renders export/backup settings.
showCardEditorDialog(context: BuildContext, card: Flashcard, fieldOrder: List<String>, isClozeSession?: bool, clozeField?: String): Future<Map<String,String>?> — edits mapped fields.
showAddCardDialog(context: BuildContext, fieldOrder: List<String>, primaryField: String, isClozeSession: bool): Future<Map<String,String>?> — creates validated fields.
HtmlCardText(value: String, textStyle: TextStyle?, emptyText?: String): StatelessWidget — renders escaped/HTML card content.
AppTheme.light(): ThemeData — builds warm Material theme.
AppSurface(child: Widget, padding?: EdgeInsetsGeometry, onTap?: VoidCallback, radius?: double, shadow?: bool): StatelessWidget — bordered reusable panel.
AppBadge(label: String, icon?: IconData, color?: Color): StatelessWidget — status pill.
AppIconTile(icon: IconData, color?: Color): StatelessWidget — square icon chip.
AppErrorBanner(message: String): StatelessWidget — shared error-container banner used by all screens.
softShadow: List<BoxShadow> — shared subtle elevation.
MainActivity.configureFlutterEngine(flutterEngine: FlutterEngine): Unit — initializes import channel.
MainActivity.onNewIntent(intent: Intent): Unit — forwards later import intents.
## Conventions
Error handling — UI mutations go through `PreAnkiAppState._run`, which sets `isBusy`, clears/stores `errorMessage`, catches exceptions, and `debugPrint`s error + stack for logcat diagnosis.
Error handling — `errorMessage` is surfaced via shared `AppErrorBanner` on home, settings, session, and import screens; import's create-session failure also sets its `_formError`.
Error handling — `Repository.importBackup` validates `format`/`formatVersion`/`sessions` before transaction deletes data.
Error handling — export direct-write catches `FileSystemException` and falls back to picker.
Auth — none; no accounts/sync/cloud; all user data stays in local SQLite/files.
Data access — screens call `AppScope.of(context)` -> `PreAnkiAppState`; only `PreAnkiRepository` uses SQL.
Data access — multi-table writes use `_db.transaction`, e.g. `createSession`, `addCard`, `updateCardFields`, `importBackup`.
Data access — list/map fields are JSON text columns: `field_names`, `reveal_fields`, `export_fields`, `fields_json`.
Naming — visible product is `LLM Recall`; internal package/classes/DB retain `preanki`/`PreAnki*` for continuity.
Naming — storage enums use explicit values: `question_answer`, `cloze`, `new`, `again`, `learned`.
Async — startup awaits `repository.initialize()` and `appState.load()` before `runApp`.
Async — route-safe work uses `Future.microtask` in `SessionScreen.didChangeDependencies`.
Async — Android import navigation uses `addPostFrameCallback` after bridge events.
CSV — use `CsvTools`, not raw `CsvDecoder`, so encoding/delimiter/header/fallback rules stay centralized.
CSV — export uses `QuoteMode.always` so unquoted `#`-leading rows can never be dropped as comments by Anki's importer.
Review — review cursor is `sessions.review_index` over expanded `ReviewCard.reviewKey`, not card array index.
Review — neutral arrows call `moveReviewPointer`; Good/Again/Delete call `_reviewAdvance` and populate `ReviewUndo`.
Rendering — card field display goes through `HtmlCardText`; plain text is escaped and newlines become `<br>`.
Platform IO — Android/iOS `FilePicker.saveFile` receives bytes; desktop save path is written with `File.writeAsBytes`.
UI state — screen rebuilds use `AnimatedBuilder(animation: appState)` rather than provider package.
Manual cloze editing — text-selection menu is limited to Cut/Copy/Paste/Cloze in cloze field.
## State & Gotchas
- Current WIP — `dist/` holds local release zips and is gitignored.
- Current WIP — Windows runner exists but desktop builds still require Visual Studio/CMake/MSVC/SDK.
- Current WIP — release APK uses debug signing in `android/app/build.gradle.kts`.
- Current WIP — no true spaced-repetition scheduler; Good/Again are lightweight review states.
- Current WIP — no accounts, sync, cloud storage, or in-app LLM cleanup.
- Footgun — keep `applicationId = com.preanki.preanki`; changing it loses Android upgrade/data continuity.
- Footgun — keep DB filename `preanki.db`; renaming needs migration/copy strategy.
- Footgun — schema version is `preAnkiSchemaVersion` (7) in `repository.dart`; bump it and add migrations in `_openDatabase` for any DB shape change.
- Footgun — `review_index` stores expanded review keys; v7 multiplied legacy card indexes by `reviewKeyMultiplier`.
- Footgun — cloze note with c1+c2 is one stored/exported row but two review items.
- Footgun — multiple deletions with same cloze number produce one review item for that number.
- Footgun — cloze-session row with no valid cloze creates `cloze_number = 0` review item.
- Footgun — add-dialog requires cloze markup for cloze sessions; edit-dialog allows malformed/non-cloze text for repair.
- Footgun — deleting during review sets stored card/note deleted, not only the current cloze item.
- Footgun — `setCardReviewState` changes all review items for a card; normal review should use `setReviewItemState`.
- Footgun — aggregate card `review_state` is learned only when all review items learned; again if any item again.
- Footgun — export filters kept cards in `AppState.exportSession`; `ExportService.buildSessionCsv` exports whatever cards it receives.
- Footgun — backup import replaces all local sessions/cards/settings; newer backup formats are rejected.
- Footgun — legacy `preset_id` is stripped during backup import/export; do not reintroduce presets casually.
- Footgun — `CsvTools.parse` preserves cell whitespace; only field names are trimmed in mapping/editor.
- Footgun — malformed quoted CSV falls back to relaxed parsing instead of surfacing parser failure.
- Footgun — header detection intentionally does not treat `Cell,Mitochondria` as a header.
- Footgun — Dart and Android Kotlin decode both fall back to Windows-1252 for malformed-UTF-8 single-byte text; keep the two heuristics in sync.
- Footgun — `HtmlCardText._containsHtml` treats entities as HTML; plain text with `<tag>`-like content renders as HTML.
- Intentional — internal `PreAnki*` names remain despite visible app label `LLM Recall`.
- Intentional — no saved import presets; mapping is per CSV import.
- Intentional — `android:exported=true` is required because activity has launcher/external intent filters.
- Intentional — `android:launchMode=singleTop` allows `onNewIntent` imports into the running app.
- Intentional — card text stays regular weight; cloze answer span is the bold green emphasis.
- Intentional — review card face has fixed viewport-relative height with internal scrolling to avoid flip resize.
