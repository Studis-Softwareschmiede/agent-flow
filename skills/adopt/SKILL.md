---
name: adopt
description: Adoptiert ein BESTEHENDES GitHub-Repo in die Fabrik — klont es (fremde Repos werden in die Org geforkt), übernimmt es per init (Stack erkennen, .claude/+docs/ scaffolden, Spec aus Code ableiten, CI/Security ergänzen), auditiert den Bestand gegen den Fabrik-Standard und legt die Funde als priorisiertes Backlog aufs Board. Behebt NICHTS automatisch — /flow arbeitet das Backlog ab. Aufruf: /agent-flow:adopt <owner/repo>.
---

# /adopt <owner/repo>

Bringt ein bestehendes Repo auf Fabrik-Standard: **clone/fork → adopt → audit → Backlog → (du wählst) → `/flow`**. Es wird **nichts automatisch behoben** — der Audit erzeugt Items, gefixt wird inkrementell per `/flow` + PR durchs Gate.

## 0. Auth
`bash "$CLAUDE_PLUGIN_ROOT/scripts/ensure-gh-auth.sh"`.

## 1. Beschaffen (clone / fork)
- **Org-eigen** (`<owner>` = `studis-softwareschmiede`): `gh repo clone studis-softwareschmiede/<repo>` → cwd = Klon. App hat Schreibrecht → Branch/PR direkt.
- **Fremd** (anderer Owner → kein Schreibrecht): **in die Org forken + klonen** — `gh repo fork <owner>/<repo> --org studis-softwareschmiede --clone --remote` (Original bleibt als `upstream`). Gearbeitet wird am **Org-Fork** (App-schreibbar); PRs gehen an den Fork; ein Upstream-PR ist optional und braucht deinen Approve.
  - **Issues am Fork einschalten** (Pflicht): GitHub liefert Forks mit **deaktivierten Issues** → direkt `gh repo edit studis-softwareschmiede/<repo> --enable-issues`. **Ohne das scheitert das Backlog** (Schritt 4, `gh issue create`). Issues/Board entstehen am **Fork**, nie am Upstream.

## 2. Adoptieren (= `init`-Pfad des `new-project`-Skills, idempotent)
Im Klon den **`/init`-Ablauf** ausführen — bestehende Dateien NICHT überschreiben:
- **Stack erkennen** (pubspec→flutter · pom/gradle→java · package.json→js/angular · `*.html`→html · `*.sql`→sql-Domäne) → bestätigen → `.claude/profile.md` (+ leere `lessons/`).
- **`docs/` scaffolden + Spec aus Code ableiten:** concept/architecture/specs als **Entwurf** — dem User zur Durchsicht vorlegen, **verbindlich erst nach OK**.
- Fehlende `Dockerfile` / `.github/workflows/build.yml` / `security.yml` / `.github/dependabot.yml` aus `${CLAUDE_PLUGIN_ROOT}/templates/` ergänzen (Sprach-Ökosystem im dependabot.yml setzen).
- **Board** anlegen (`gh project create`) → Nummer ins Profil.

## 3. Auditieren (gegen den Fabrik-Standard)
- **Automatik zuerst (objektiv, billig):** `gitleaks detect --source=. --no-git` (Secrets) + Dependency-Audit gemäß Sprache (`npm audit --omit=dev` / `pip-audit` / …) → Funde notieren.
- **`reviewer` im Audit-Modus** (Task — s. `reviewer.md` „Audit-Modus"): prüft den **Bestand** (kein Diff) gegen **Security-Floor** (immer), die Sprach-/Domänen-**Pack-Checklists**, Projekt-Konventionen und die **abgeleitete Spec** → priorisierte Funde (Critical/Important/Suggestions). Bei großen Repos **priorisiert** (Security-Floor überall; Pack-Checks auf repräsentative/heikle Dateien — Auth, Daten-/Netz-Zugriff, Eingänge; Architektur-Auffälligkeiten), NICHT zeilenweise.

## 4. Backlog anlegen
Aus den Funden **Board-Items** (Status To Do), **Critical zuerst**: pro Item ein GitHub-Issue mit **Acceptance** („<Fund> auf Standard `<Regel-ID>`/Prinzip beheben") + Priority; verwandte Funde **clustern** (kein 1-Item-pro-Zeile-Dump). Security-Floor-Verstöße → höchste Priority. Wo sinnvoll auf die abgeleitete Spec/AC verweisen.

## 5. Übergabe (KEIN Auto-Fix)
Report an den User: Repo-/Fork-URL · Board-URL · Funde nach Schwere (#Critical / #Important / #Suggestions) · die abgeleiteten Specs. → „Wähle die Items, die behoben werden sollen, und starte `/agent-flow:flow`." **Stop.**

## Grenzen
- **Behebt nichts automatisch** — erzeugt nur das Backlog; Fix = `/flow` (PR-gated).
- Pusht NUR auf das Org-Repo bzw. den Org-Fork — **nie** ungefragt auf ein fremdes Upstream (Upstream-PR nur auf deinen Wunsch + Approve).
- Idempotent: bestehende `.claude/`-/`docs/`-Dateien nicht überschreiben (mergen/fragen).
- Die **abgeleitete Spec ist Entwurf**, bis du sie bestätigst (sie ist danach die Drift-Gate-Referenz für `/flow`).
