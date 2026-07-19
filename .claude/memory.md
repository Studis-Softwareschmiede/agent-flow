> Orientierung, nie Wahrheit: bei Widerspruch gelten Board + docs/specs/.
> Kuratiert von /flow am Ende jeder Session. Max. 60 Zeilen.

## Aktueller Stand
Board leer — 11 Stories am 19.07.2026 gelandet (PRs #376–#387), zwei neue
Fabrik-Standards: (1) **Admin-Bereich** für UI-Projekte: passwortgeschützter
Konfig-Editor (nur Passwort, argon2id-Hash in .env via set-admin-password.sh,
wandert über .env.gpg mit), deklaratives config/admin-manifest.yaml, Settings-
Ablage auf Daten-Volume (/data) mit Vorrang über .env/config.yaml-Defaults;
Scaffold in new-project 4g / adopt 2i, Floor security/R13–R16 + knowledge/ui.md
(domains:[ui] in UI-Templates). (2) **Build-Versionierung** (flashrescue-
Vorfall 19.07.): EINE Quelle APP_VERSION+GIT_SHA als build-args, Version ins
Image gebrannt (/app/VERSION bzw. version.json), OCI-Labels, nginx no-cache
auf index.html+version.json, cicd liest/vergleicht datei-/label-first statt
ENV (cicd/P08), Version-Endpunkt-Scaffold in new-project 4h / adopt 2j.

## Letzte Arbeiten
- S-084/S-085/S-086/S-087/S-088 (admin-bereich-*): Scaffold-Fragment +
  Wiring + Knowledge-Floor + Settings-Volume (cicd/preview) + requirement-
  Manifest-Frage. Befunde: $-Quoting argon2-Hash in .env (eval zerstört),
  knowledge/ui.md ohne domains:[ui] unerreichbar — beide gefixt.
- S-089/S-090/S-091/S-092/S-093/S-094 (build-version-*): build.yml eine
  Quelle, Service-/Frontend-Dockerfiles brennen Version, nginx.conf neu
  (inkl. Scaffold-Wiring-Nachzug), Version-Endpunkt-Vorlage, cicd-Abgleich,
  cicd-Pack F02-Amendment + P08.
- S-083: .retro-last-run vom lessons-gitignore ausgenommen.

## Offene Fäden
- dev-gui: (a) VPS-Rollout muss Settings-Daten-Volume mounten (Hinweis in
  agents/cicd.md A3 + admin-bereich-settings-rollout AC2), (b) Wellen-Plan-
  Konsum-Story (Nachtwächter) weiterhin anzulegen.
- Der konsumierende Admin-Bereich + /version-Endpunkt entstehen erst
  projekt-lokal beim nächsten new-project/adopt-Lauf (Board-Story-Automatik).
- board-ship.sh: `gh pr merge` scheitert lokal weiter (main im Hauptordner
  ausgecheckt, heute 12× — PRs remote sauber gemerged, Restschritte manuell).
- knowledge/cicd.md F05 nennt noch env.BUILD_VERSION (Tag-Beispiel) und F02
  das Format „yyMMddHHmmss ZZZ" (real: ohne Zeitzone) — kleine Doku-Nachzüge.
- AGENTS.md §1c (designer) beschreibt noch den alten Ablauf ohne Freigabe-
  Modus — Doku-Nachzug offen (aus Vorsession).
