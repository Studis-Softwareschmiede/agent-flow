# Knowledge Pack: flutter

Expertise für Flutter (Web/App). Geladen bei `profile.language: flutter`. Wächst via `train`/`retro` (PR+Gate). Regel-IDs: `flutter/R<NN>`.

## Coder-Guidance
- `flutter/R01` — `setState`/`BuildContext` nach einem `await` nur mit `if (!mounted) return;` (bzw. `context.mounted`) davor.
- `flutter/R02` — Controller/Subscriptions (`TextEditingController`, `StreamSubscription`, `AnimationController`) in `dispose()` freigeben.
- `flutter/R03` — Einmal-Lesen über `Future` + `FutureBuilder`, nicht über Realtime-Streams.
- `flutter/R04` — URLs/Endpoints über eine zentrale Config, nie als Literal im Widget.

## Reviewer-Checklist
- `setState`/`context` über `await` ohne mounted-Guard → **Critical**.
- Nicht freigegebene Controller/Subscriptions → **Important**.
- Hartkodierte URLs/Secrets im Dart-Code → **Critical**.
- `Image.network` ohne `errorBuilder` (Web: CORS/404) → **Important**.

## Test-Approach
- `flutter analyze` sauber; `flutter build web --release`; Smoke = Seite/Container lädt (HTTP 200).
