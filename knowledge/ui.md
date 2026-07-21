# Knowledge Pack: ui  (Domäne — sprach-/framework-unabhängig)

Generische UI-Rendering-Prinzipien, die über Stack-Grenzen hinweg gelten (ergänzt die stack-spezifischen Packs `html`/`css`/`angular`/`js`/`flutter`/… um Muster, die nicht an eine Sprache gebunden sind). Geladen als Domäne bei UI-Projekten (`profile.domains: [..., ui]`, gesetzt in `templates/{angular,html,flutter}/profile.md`), die deklaratives Konfig-Rendering einsetzen (aktuell: Fabrik-Standard Admin-Bereich, `docs/architecture/admin-bereich-subsystem.md`). Regel-IDs: `ui/R<NN>`.

## Coder-Guidance
- `ui/R01` — **Generisches Manifest-Rendering statt Parameter-Handbau:** eine Konfigurations-UI (z. B. der Admin-Bereich) rendert **generisch aus einem deklarativen Manifest** (`config/admin-manifest.yaml`, Fabrik-Standard) statt jeden Parameter einzeln im UI-Code zu verdrahten. Ein neuer Parameter ist eine neue Manifest-Zeile, kein neuer UI-Code. → `docs/architecture/admin-bereich-subsystem.md` GE3/BR-011.
- `ui/R02` — **Boot-kritische (`editierbar: false`)-Parameter nur maskiert anzeigen:** als `editierbar: false` deklarierte Manifest-Parameter sind read-only und werden im UI **nur maskiert dargestellt** (kein editierbares Eingabefeld) — sie wirken erst nach Neustart, ein UI-Edit wäre irreführend. → `docs/architecture/admin-bereich-subsystem.md` BR-007.
- `ui/R03` — **`secret`-Parameter im UI maskiert:** als `secret` deklarierte Manifest-Parameter werden **immer maskiert** angezeigt (z. B. `••••••••`), nie als Klartext-Vorbelegung eines Eingabefelds. → `docs/architecture/admin-bereich-subsystem.md` BR-008 (siehe auch `security/R15`, Floor).
- `ui/R04` — **`editierbar: false`-Parameter als `readonly`, nicht als `disabled`/entfernt exponieren:** WAI-ARIA unterscheidet normativ zwischen `readonly` („nicht editierbar, aber weiterhin **operable**" — fokussierbar, für Tastatur/Screenreader navigierbar, Wert kopierbar; explizites Beispiel: „a form element which represents a constant") und `disabled` („perceivable but disabled, so it is not editable or otherwise operable"; Autoren SOLLEN Fokus-Navigation zu Nachfahren bei `disabled` ggf. einschränken, bei `readonly` explizit NICHT). Ein boot-kritischer `editierbar: false`-Parameter ist der `readonly`-Fall, nicht `disabled` — die maskierte Anzeige (`ui/R02`) MUSS daher per Tastatur erreichbar, für Screenreader wahrnehmbar und der maskierte Wert kopierbar bleiben (natives `readonly`-Attribut bzw. `aria-readonly="true"`), NICHT als `aria-disabled`/aus der Tab-Reihenfolge bzw. dem Accessibility-Tree entferntes Element umgesetzt werden. Schärft `ui/R02`. — [W3C WAI-ARIA 1.2 §aria-readonly](https://www.w3.org/TR/wai-aria-1.2/#aria-readonly) · [W3C WAI-ARIA 1.2 §aria-disabled](https://www.w3.org/TR/wai-aria-1.2/#aria-disabled)

## Reviewer-Checklist
- Konfigurations-UI verdrahtet Parameter einzeln im UI-Code statt generisch aus dem Manifest zu rendern → **Important** (`ui/R01`, GE3/BR-011 verletzt).
- `editierbar: false`-Parameter im UI editierbar (Eingabefeld statt maskierter Anzeige) → **Important** (`ui/R02`, BR-007).
- `secret`-Parameter unmaskiert oder als Klartext-Vorbelegung im UI → **Important** (`ui/R03`, BR-008 — Security-Floor, siehe `security/R15`).
- `editierbar: false`-Parameter per `aria-disabled`/aus der Tab-Reihenfolge oder dem Accessibility-Tree entfernt statt als `readonly` (weiterhin fokussierbar/kopierbar) exponiert → **Important** (`ui/R04`, WAI-ARIA-Spec-Widerspruch — `readonly` bleibt operable, `disabled` nicht).

## Test-Approach
- Neuer Manifest-Eintrag rendert ohne UI-Code-Änderung (nur Manifest-Zeile hinzugefügt) → Smoke-Probe.
- `editierbar: false`-Parameter: UI zeigt Wert maskiert/read-only, kein Eingabefeld nimmt Änderungen an.
- `secret`-Parameter: gerenderte Response/DOM enthält nie den Klartextwert (auch nicht im `value`-Attribut eines Inputs).
- `editierbar: false`-Parameter: per Tab erreichbar (nicht aus der Tab-Reihenfolge entfernt) und der maskierte Wert per Copy-Aktion auslesbar (`readonly`-Semantik, keine `disabled`-Semantik).
