# Versions-Strategie für Framework-Packs

> Bindend für `train` und `retro` und beim Anlegen neuer Framework-Packs.
> Referenz aus `docs/architecture/framework-build-subsystem.md` §5.

## Faustregel

- **Cut** (neuer Pack pro Major): wenn die Migration alte Code-Patterns **kaputt macht oder verbietet**.
- **Tag** (`[since: x.y]` im selben Pack): wenn die Migration alte Patterns nur **anbietet** und alter Code weiterläuft.

## Beispiele

| Übergang | Cut oder Tag | Grund |
|---|---|---|
| Spring-Boot 2 → 3 | Cut | Java 17 Pflicht + `javax` → `jakarta`. Alter Code MUSS angepasst werden. |
| Spring-Boot 3.3 → 3.4 | Tag | Additive Releases, kein Code-Bruch. |
| React 17 → 18 | Cut | Concurrent-Render, Hook-Regeln, Suspense-Semantik. |
| React 18 → 19 | (entscheiden bei Release) | Stand 2026-05: noch keine Cut-Empfehlung. |
| Java 17 → 21 | Tag | Records/Pattern-Matching additive. |
| Java 8 → 17 | (historisch Cut) | (außerhalb aktiver Pflege) |
| Maven 3 → 4 | (Cut bei Release) | Major-Versionswechsel, Pflicht-Anpassungen erwartet. |

## Profil-Form

`frameworks: ["spring-boot@3"]` — `@<major>` ist Pflicht ab Frameworks, die einen Cut hatten.

## Loader-Verhalten

Der Pack-Loader (gilt für `coder`/`reviewer`/`tester`) matcht den im Profil genannten Major gegen den `framework_version_range`-Header der Pack-Datei. Kein Match → Fehler („Pack `<id>@<major>` fehlt; lege ihn an oder korrigiere das Profil").

## Pack-Anlage-Pflicht

Beim Cut wird der NEUE Pack durch Kopie + Anpassung des alten erzeugt. Der ALTE Pack wird NICHT gelöscht (Bestandsprojekte verlassen sich darauf), bekommt aber im Header `eol: <datum>` oder `superseded_by: <neuer-pack>`.
