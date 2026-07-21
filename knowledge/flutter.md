# Knowledge Pack: flutter

Expertise für Flutter (Web/App). Geladen bei `profile.language: flutter`. Wächst via `train`/`retro` (PR+Gate). Regel-IDs: `flutter/R<NN>`.

## Coder-Guidance
- `flutter/R01` — `setState`/`BuildContext` nach einem `await` nur mit `if (!mounted) return;` (bzw. `context.mounted`) davor.
- `flutter/R02` — Controller/Subscriptions (`TextEditingController`, `StreamSubscription`, `AnimationController`) in `dispose()` freigeben.
- `flutter/R03` — Einmal-Lesen über `Future` + `FutureBuilder`, nicht über Realtime-Streams.
- `flutter/R04` — URLs/Endpoints über eine zentrale Config, nie als Literal im Widget.
- `flutter/R05` — **Breaking (Flutter 3.22+):** `MaterialState*`-Klassen sind auf `WidgetState*` umbenannt (z.B. `MaterialStateProperty` → `WidgetStateProperty`, `MaterialStatesController` → `WidgetStatesController`); Migration per `dart fix --apply`. Quelle: [flutter.dev/release/breaking-changes/material-state](https://docs.flutter.dev/release/breaking-changes/material-state)
- `flutter/R06` — **Breaking (Flutter 3.27+):** Android-Apps, die SDK 15+ targeten, laufen standardmäßig edge-to-edge (UI reicht hinter Status-/Navigationsbar); UI-Overlaps mit `SafeArea`/`MediaQuery` abfangen. Opt-out via `android:windowOptOutEdgeToEdgeEnforcement` in `styles.xml` gilt nur bis Android 15 — ab Android 16 nicht mehr möglich. Quelle: [flutter.dev/release/breaking-changes/default-systemuimode-edge-to-edge](https://docs.flutter.dev/release/breaking-changes/default-systemuimode-edge-to-edge)
- `flutter/R07` — **Breaking (Flutter 3.38+):** Android-Standard-Seitenübergang ist jetzt `PredictiveBackPageTransitionsBuilder` (Dauer 450 ms statt 300 ms); Tests, die eine feste Transition-Dauer annehmen, brechen — `TransitionDurationObserver.pumpPastTransition()` nutzen. Quelle: [flutter.dev/release/breaking-changes/default-android-page-transition](https://docs.flutter.dev/release/breaking-changes/default-android-page-transition)
- `flutter/R08` — **Breaking (Flutter 3.38+):** `SnackBar` mit `action` dismissed nicht mehr automatisch nach Ablauf der Dauer; Standard ist jetzt persistent bis zur Nutzerinteraktion. Für altes Verhalten `persist: false` explizit setzen. Quelle: [flutter.dev/release/breaking-changes/snackbar-with-action-behavior-update](https://docs.flutter.dev/release/breaking-changes/snackbar-with-action-behavior-update)
- `flutter/R09` — **Deprecation + Migration (Flutter 3.44+):** AGP 9 kündigt das `kotlin-android`-Plugin (KGP) ab — built-in Kotlin ist der neue Standard. Ein temporärer Compat-Shim hält bestehende Builds noch am Laufen (Issue #183909), wird aber entfernt (Issue #184837). Migration jetzt: `id("kotlin-android")` + `kotlinOptions {}`-Block entfernen, stattdessen `kotlin { compilerOptions { jvmTarget = … } }` einsetzen. Quelle: [flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin)
- `flutter/R10` — **Breaking (Flutter 3.44+):** `ListTile` löst jetzt im Debug-Modus einen Assertion-Error aus, wenn ein Widget mit undurchsichtiger Hintergrundfarbe (z.B. `Container(color: …)`, `ColoredBox`) zwischen `ListTile` und dem nächsten `Material`-Ancestor liegt (`ListTile` malt Hintergrund/Ink-Splashes auf diesen Ancestor — der Zwischen-Container würde das verdecken). Fix: Hintergrundfarbe direkt auf ein umschliessendes `Material` legen (`Material(color: …)`) statt auf den `Container`, ODER `ListTile` in ein eigenes `Material(type: MaterialType.transparency)` wrappen. Quelle: [flutter.dev/release/breaking-changes/list-tile-color-warning](https://docs.flutter.dev/release/breaking-changes/list-tile-color-warning)
- `flutter/R11` — **Deprecation + Migration (Flutter 3.44+):** `cacheExtent`/`cacheExtentStyle` (ScrollView/Viewport/RenderViewportBase) sind deprecated zugunsten von `scrollCacheExtent` mit einem `ScrollCacheExtent`-Objekt (`ScrollCacheExtent.pixels(500.0)` statt `cacheExtent: 500.0`; `ScrollCacheExtent.viewport(0.5)` statt `cacheExtent: 0.5, cacheExtentStyle: CacheExtentStyle.viewport`). Quelle: [flutter.dev/release/breaking-changes/scroll-cache-extent](https://docs.flutter.dev/release/breaking-changes/scroll-cache-extent)
- `flutter/R12` — **Deprecation + Migration (Flutter 3.44+):** `onReorder`-Callback von `ReorderableListView`/`ReorderableListView.builder`/`ReorderableList`/`SliverReorderableList` ist deprecated zugunsten von `onReorderItem` — `onReorderItem` korrigiert `newIndex` bereits automatisch (die alte manuelle `if (oldIndex < newIndex) newIndex -= 1;`-Korrektur in `onReorder`-Handlern entfällt und darf beim Umstieg nicht mitkopiert werden, sonst doppelte Korrektur/Off-by-one). Quelle: [flutter.dev/release/breaking-changes/deprecate-onreorder-callback](https://docs.flutter.dev/release/breaking-changes/deprecate-onreorder-callback)

## Reviewer-Checklist
- `setState`/`context` über `await` ohne mounted-Guard → **Critical**.
- Nicht freigegebene Controller/Subscriptions → **Important**.
- Hartkodierte URLs/Secrets im Dart-Code → **Critical**.
- `Image.network` ohne `errorBuilder` (Web: CORS/404) → **Important**.
- `MaterialState*` statt `WidgetState*` (veraltet seit Flutter 3.22) → **Important**.
- Android-App ohne `SafeArea` bei edge-to-edge (Flutter 3.27+) → **Important**.
- `SnackBar` mit `action` ohne explizites `persist: false` (Flutter 3.38+: persistent bis Nutzerinteraktion) → **Important**.
- `build.gradle` mit `kotlin-android`-Plugin (AGP 9 / Flutter 3.44+: temporärer Compat-Shim läuft; Migration jetzt empfohlen, Shim wird entfernt) → **Important** (Migration jetzt empfohlen; temporärer Compat-Shim läuft ab).
- `ListTile` in einem farbigen `Container`/`ColoredBox` ohne eigenes `Material` dazwischen (Flutter 3.44+: Debug-Assertion, Hintergrund/Ink-Splash unsichtbar) → **Important**.
- `cacheExtent`/`cacheExtentStyle` statt `scrollCacheExtent` (deprecated seit Flutter 3.44) → **Minor**.
- `ReorderableListView`/`ReorderableList` mit `onReorder` statt `onReorderItem` (deprecated seit Flutter 3.44) — insb. mit noch vorhandener manueller `newIndex`-Korrektur nach Umstieg (Off-by-one) → **Important**.

## Test-Approach
- `flutter analyze` sauber; `flutter build web --release`; Smoke = Seite/Container lädt (HTTP 200).

## Spec-Tagging
Trace-Tag je gedecktem Kriterium gemäss `docs/architecture/traceability-subsystem.md`.
- **Idiom (`flutter_test`/`package:test`):** der `tags:`-Parameter von `test()`/`testWidgets()` (nativ via `dart test --tags` filterbar), ein Tag-String je Kriterium: `testWidgets('rejects empty password', tags: ['trace:user-login#AC1', 'trace:user-login#BR-002'], (tester) async { … });`.
- **Extraktions-Rezept (Regex):** `'trace:([a-z0-9][a-z0-9-]*)#(AC\d+|BR-\d+)'` über die `tags:`-Argumente.
- **Fallback:** kanonisches Token in der Test-Description; Core-Regex.
