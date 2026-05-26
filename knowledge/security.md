# Knowledge Pack: security  (Domäne — querschnittlich)

> **last_trained:** 2026-05-26 — Frische-Signal für durable Sicherheits-Prinzipien. `train` setzt das Datum bei jedem `/train security` auf heute; `/flow` nudged, wenn es > 90 Tage her ist. (Tagesaktuelle CVEs/Exploits gehören NICHT hierher → Dependabot + geplanter Scan.)

Sprach-agnostische Sicherheits-Expertise. Geladen als Domäne (`profile.domains: [security]`) für die *Tiefe*; die mit **⚑** markierten Punkte sind der **Security-Floor**, den der `reviewer` **IMMER** anwendet (auch ohne `domains:[security]`) und der `coder` immer befolgt. Regel-IDs: `security/R<NN>`. Orientierung: OWASP Top 10.

## Coder-Guidance
- `security/R01` ⚑ — **Keine Secrets im Code/Repo** (Keys, Tokens, Passwörter, Connection-Strings) → aus Env/Secret-Store laden; Secrets **nie loggen**.
- `security/R02` ⚑ — **Jeden untrusted Input** (User, Netzwerk, Datei, URL-Param) validieren/normalisieren; **Output kontext-gerecht encoden** (HTML / Attribut / URL / SQL) → gegen XSS/Injection.
- `security/R03` ⚑ — Datenzugriff **parametrisiert** (Prepared Statements / sicheres ORM); Befehle/Pfade/`eval` **nie** aus Roh-Input bauen (SQL-/Command-/Path-Injection).
- `security/R04` ⚑ — **Authentifizierung + Autorisierung serverseitig auf JEDER geschützten Aktion** prüfen (nicht nur UI ausblenden); **Default deny**, Objekt-Ebene mitdenken (IDOR).
- `security/R05` — Server-seitige URL-Fetches gegen **SSRF** absichern (Allowlist; keine internen IPs / Cloud-Metadaten-Endpunkte).
- `security/R06` — **Krypto-Hygiene:** etablierte Libs statt Eigenbau; Passwort-Hashing mit bcrypt/argon2 (nicht MD5/SHA1); TLS für Transport; sichere Zufallsquelle.
- `security/R07` — Dependencies aktuell + minimal, **Lockfile committen**; keine bekannten High/Critical-CVEs.

## Reviewer-Checklist
- ⚑ Hartkodiertes Secret (Key/Token/Passwort/Connection-String) im Diff → **Critical** (`security/R01`).
- ⚑ Untrusted Input ohne Validierung in einen Sink (DB / HTML / Shell / Pfad / `eval`) → **Critical** (`security/R02`).
- ⚑ String-Interpolation in Query/Command/Pfad statt Parametrisierung → **Critical** (`security/R03`).
- ⚑ Geschützte Aktion ohne serverseitige Authz-Prüfung (oder Authz nur im UI) → **Critical** (`security/R04`).
- URL-Fetch aus User-Input ohne Allowlist → **Important** (SSRF, `security/R05`).
- Selbstgebaute/schwache Krypto, MD5/SHA1 oder Klartext für Passwörter → **Critical** (`security/R06`).
- Bekannte High/Critical-CVE in einer Dependency → **Important** (`security/R07`).
- Sensible Daten (Token/PII) geloggt oder in URL/Fehlermeldung exponiert → **Important**.

## Test-Approach
- **Secret-Scan** (gitleaks o. ä.) über Diff/Repo — Treffer = **Fail** (deckt `security/R01`).
- **Dependency-Audit** gemäß Sprache (`npm audit --omit=dev`, `pip-audit`, `osv-scanner`, …), falls das Projekt Dependencies hat; High/Critical → Befund (`security/R07`).
- Authz-Probe (falls zutreffend): geschützte Route ohne / mit falschem Token aufrufen → **401/403** erwartet (`security/R04`).
