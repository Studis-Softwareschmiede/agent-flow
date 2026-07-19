# Knowledge Pack: security  (Domäne — querschnittlich)

> **last_trained:** 2026-06-15 — Frische-Signal für durable Sicherheits-Prinzipien. `train` setzt das Datum bei jedem `/train security` auf heute; `/flow` nudged, wenn es > 90 Tage her ist. (Tagesaktuelle CVEs/Exploits gehören NICHT hierher → Dependabot + geplanter Scan.)

Sprach-agnostische Sicherheits-Expertise. Geladen als Domäne (`profile.domains: [security]`) für die *Tiefe*; die mit **⚑** markierten Punkte sind der **Security-Floor**, den der `reviewer` **IMMER** anwendet (auch ohne `domains:[security]`) und der `coder` immer befolgt. Regel-IDs: `security/R<NN>`. Orientierung: OWASP Top 10.

## Coder-Guidance
- `security/R01` ⚑ — **Keine Klartext-Secrets im Code/Repo** (Keys, Tokens, Passwörter, Connection-Strings — hartkodiert oder als unverschlüsselte Datei committed) → aus Env/Secret-Store laden; Secrets **nie loggen**. **Erlaubt (GE6):** eine committete `.env.gpg`-Datei (GPG-symmetrisch AES256, geteilte Fabrik-Passphrase) ist der **vorgesehene** Weg, App-Secrets versioniert mitzuführen — sie ist **kein** Befund. Klartext-`.env` oder hartkodierte Werte bleiben Critical.
- `security/R02` ⚑ — **Jeden untrusted Input** (User, Netzwerk, Datei, URL-Param) validieren/normalisieren; **Output kontext-gerecht encoden** (HTML / Attribut / URL / SQL) → gegen XSS/Injection.
- `security/R03` ⚑ — Datenzugriff **parametrisiert** (Prepared Statements / sicheres ORM); Befehle/Pfade/`eval` **nie** aus Roh-Input bauen (SQL-/Command-/Path-Injection).
- `security/R04` ⚑ — **Authentifizierung + Autorisierung serverseitig auf JEDER geschützten Aktion** prüfen (nicht nur UI ausblenden); **Default deny**, Objekt-Ebene mitdenken (IDOR). *(Für die Admin-Bereich-Setup-Seite gilt die verschärfte Fassung `security/R16` — localhost-only Default-deny.)*
- `security/R05` — Server-seitige URL-Fetches gegen **SSRF** absichern (Allowlist; keine internen IPs / Cloud-Metadaten-Endpunkte).
- `security/R06` — **Krypto-Hygiene:** etablierte Libs statt Eigenbau; Passwort-Hashing mit bcrypt/argon2 (nicht MD5/SHA1); TLS für Transport; sichere Zufallsquelle. *(Für den Admin-Bereich-Login gilt die verschärfte Fassung `security/R13` — argon2id verpflichtend, kein bcrypt-Wahlrecht.)*
- `security/R07` — Dependencies aktuell + minimal, **Lockfile committen**; keine bekannten High/Critical-CVEs.
- `security/R08` — **OWASP Top 10:2025** ist die aktuelle Referenz (ersetzt 2021): Neu hinzugekommen ist `A10:2025 — Mishandling of Exceptional Conditions` (fehlerhafte Fehlerbehandlung, fail-open, logische Fehler); `A03:2025 — Software Supply Chain Failures` ersetzt das frühere "Vulnerable Components" und schließt auch unbekannte Drittanbieter-Schwachstellen ein; SSRF wurde in `A01:2025 — Broken Access Control` konsolidiert. → [OWASP Top 10:2025](https://owasp.org/Top10/2025/) · [Introduction/Changes](https://owasp.org/Top10/2025/0x00_2025-Introduction/)
- `security/R09` — **SHA-1 für digitale Signaturen ist bereits disallowed** (NIST SP 800-131A Rev.2, seit 2013 für neue Signaturen verboten). Vollständige Abkündigung aller SHA-1-Krypto-Anwendungen: 2030-12-31 (NIST SP 800-131A Rev.3 draft). `security/R06`-Ergänzung: SHA-1 auch für HMACs und allgemeine Hash-Anwendungen bis 2030 auslaufen lassen; SHA-2 (≥ 256 bit) oder SHA-3 verwenden. → [NIST: Transitioning Away from SHA-1](https://csrc.nist.gov/news/2022/nist-transitioning-away-from-sha-1-for-all-apps) · [NIST SP 800-131A Rev.3 ipd](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-131Ar3.ipd.pdf)
- `security/R10` — **JWT-Implementierungen** müssen per `draft-ietf-oauth-rfc8725bis` (Update zu RFC 8725): (a) `alg`-Header case-sensitiv prüfen — Varianten wie `"noNE"` müssen abgelehnt werden; (b) PBES2-Iterationszähler (`p2c`) auf einen vernünftigen Maximalwert begrenzen (DoS-Schutz); (c) JWE-Dekomprimierungsgröße auf ≤ 250 KB begrenzen (Decompression-Bomb). → [draft-ietf-oauth-rfc8725bis](https://datatracker.ietf.org/doc/draft-ietf-oauth-rfc8725bis/) · [RFC 8725](https://datatracker.ietf.org/doc/html/rfc8725)
- `security/R11` — **Passwort-Policy (NIST SP 800-63B-4, final Juli 2025):** (a) Mindestlänge **15 Zeichen** bei Single-Factor-Auth (nur Passwort), **8 Zeichen** bei MFA; (b) **Keine** Komplexitätsregeln (keine Zeichentyp-Mischpflicht); (c) **Keine** periodische Rotation erzwingen — nur bei nachgewiesener Kompromittierung; (d) Passwörter gegen eine Blocklist bekannter/geleakter Credentials prüfen (gesamtes Passwort, nicht nur Substring). Gilt für Verifier-Implementierungen und CSPs. → [NIST SP 800-63B-4 §3.1.1.2 (final)](https://csrc.nist.gov/pubs/sp/800/63/b/4/final) · [Volltext SP 800-63B-4](https://pages.nist.gov/800-63-4/sp800-63b.html)
- `security/R12` — **Post-Quantum-Kryptografie (PQC) einplanen:** NIST hat im August 2024 die ersten drei PQC-Standards finalisiert: FIPS 203 (ML-KEM, Schlüsselaustausch, Nachfolger RSA/ECDH), FIPS 204 (ML-DSA, Signaturen, Nachfolger ECDSA/RSA-Sign), FIPS 205 (SLH-DSA, hash-basierte Signaturen). Neue Systeme sollen **Crypto-Agility** einplanen (Algorithmus austauschbar ohne Architektur-Umbau); langlebige Schlüssel/Zertifikate (TLS, Code-Signing, Archiv) **jetzt** auf Migrierbarkeit prüfen. RSA/ECDH/ECDSA bleiben vorerst sicher — aber PQC-Pfad muss planbar sein. → [NIST News: PQC FIPS Approved (Aug 2024)](https://csrc.nist.gov/news/2024/postquantum-cryptography-fips-approved) · [FIPS 203](https://csrc.nist.gov/pubs/fips/203/final) · [FIPS 204](https://csrc.nist.gov/pubs/fips/204/final) · [FIPS 205](https://csrc.nist.gov/pubs/fips/205/final)
- `security/R13` ⚑ — **Admin-Bereich-Login-Härtung:** das Admin-Passwort wird ausschließlich als **argon2id**-Hash gespeichert (nie Klartext, nie umkehrbar verschlüsselt — verschärft `security/R06` für den Admin-Login-Fall); der Login trägt eine **Fehlversuch-Sperre / Rate-Limit** gegen Brute-Force. → `docs/architecture/admin-bereich-subsystem.md` BR-002, BR-009.
- `security/R14` ⚑ — **Admin-Bereich-Session + CSRF:** die Admin-Sitzung läuft über ein **signiertes HttpOnly+SameSite-Cookie**; jeder state-ändernde Admin-Request (POST/PUT/PATCH/DELETE) ist **CSRF-geschützt** (Token oder Double-Submit-Cookie). → `docs/architecture/admin-bereich-subsystem.md` BR-010.
- `security/R15` ⚑ — **Admin-Bereich-Secret-Maskierung:** als `secret`/`maskiert` deklarierte Manifest-Parameter (`config/admin-manifest.yaml`) werden im Admin-UI **immer maskiert** ausgeliefert — nie Klartext an den Browser, auch nicht als Vorbelegung eines Eingabefelds. → `docs/architecture/admin-bereich-subsystem.md` BR-008 (siehe auch `ui/R03`).
- `security/R16` ⚑ — **Admin-Bereich-Setup nur von localhost:** ist beim Start kein `ADMIN_PASSWORD_HASH` gesetzt, ist die Erst-Setup-Seite **ausschließlich von localhost** erreichbar; jeder nicht-localhost-Request (insbesondere auf dem VPS) wird **immer** abgewiesen (Default deny, verschärft `security/R04` für den Setup-Fall). → `docs/architecture/admin-bereich-subsystem.md` BR-004.

## Reviewer-Checklist
- ⚑ Hartkodiertes Secret (Key/Token/Passwort/Connection-String) im Diff → **Critical** (`security/R01`).
- ⚑ Klartext-`.env` oder `.env.*` (ohne `!`-Negation) im Index/Commit committed → **Critical** (`security/R01`). Committed `.env.gpg` (verschlüsselt, GPG AES256) → **erlaubt** (GE6, Spec `docs/architecture/secrets-subsystem.md` §6).
- ⚑ Diff führt neue App-env-Variable ein (z.B. `process.env.X` / `os.environ["X"]`), aber `.env.example` listet `X` nicht → **Important** „Secret-Sync: `.env.example` referenziert `X` nicht — Re-Encrypt-Konvention §9 verletzt" (`secrets-subsystem.md` §9).
- ⚑ Diff ändert `.env.example` (neue Variable), aber `.env.gpg` ist im selben Diff **unverändert** → **Important** „`.env.gpg` nicht re-encrypted nach `.env.example`-Änderung — bitte verify" (Heuristik, §9).
- Diff committet `.env.gpg` ohne zugehörige `.env.example`-/Code-Änderung → **Suggestion** (kann legitim sein — Wert-Rotation).
- gitleaks-Allowlist erlaubt `.env` oder `.env.*` (Klartext) → **Critical** (hebelt `security/R01` aus; nur `^\.env\.gpg$` ist erlaubt — Spec §6).
- ⚑ Untrusted Input ohne Validierung in einen Sink (DB / HTML / Shell / Pfad / `eval`) → **Critical** (`security/R02`).
- ⚑ String-Interpolation in Query/Command/Pfad statt Parametrisierung → **Critical** (`security/R03`).
- ⚑ Geschützte Aktion ohne serverseitige Authz-Prüfung (oder Authz nur im UI) → **Critical** (`security/R04`).
- URL-Fetch aus User-Input ohne Allowlist → **Important** (SSRF, `security/R05`).
- Selbstgebaute/schwache Krypto, MD5/SHA1 oder Klartext für Passwörter → **Critical** (`security/R06`).
- Bekannte High/Critical-CVE in einer Dependency → **Important** (`security/R07`).
- Supply-Chain-Risiko: Drittanbieter-Skripte/Pakete ohne Integrity-Check oder unbekannte Herkunft → **Important** (`security/R08`, A03:2025).
- Fehlerbehandlung, die sicherheitskritische Aktionen bei Exception still durchlässt (fail-open) → **Important** (`security/R08`, A10:2025).
- SHA-1 für neue Signaturen, HMACs oder Zertifikate → **Critical** (`security/R09`).
- JWT-Verarbeitung ohne case-sensitiven `alg`-Check, ohne PBES2-Limit, ohne Dekomprimierungs-Limit → **Important** (`security/R10`).
- Passwort-Policy erzwingt Komplexitätsregeln (Zeichentyp-Mix) oder Periodic-Rotation statt Breach-Blocklist-Check → **Suggestion** (kontra NIST SP 800-63B-4, `security/R11`).
- Single-Factor-Passwort-Minlänge < 15 Zeichen im Code/Config → **Important** (`security/R11`).
- Sensible Daten (Token/PII) geloggt oder in URL/Fehlermeldung exponiert → **Important**.
- ⚑ Klartext-/schwaches Passwort-Hashing (kein argon2id) für den Admin-Login → **Critical** (`security/R13`, BR-002).
- ⚑ Admin-Login ohne Fehlversuch-Sperre/Rate-Limit → **Important** (`security/R13`, BR-009).
- ⚑ Admin-Bereich ohne CSRF-Schutz auf state-ändernden Requests oder ohne HttpOnly+SameSite-Session-Cookie → **Important** (`security/R14`, BR-010).
- ⚑ Admin-Setup-Seite ohne localhost-Beschränkung (auf dem VPS erreichbar) → **Critical** (`security/R16`, BR-004).
- ⚑ Als `secret`/`maskiert` deklarierter Manifest-Parameter unmaskiert an den Browser ausgeliefert (auch als Vorbelegung eines Eingabefelds) → **Important** (`security/R15`, BR-008).

## Test-Approach
- **Secret-Scan** (gitleaks o. ä.) über Diff/Repo — Treffer = **Fail** (deckt `security/R01`).
- **Dependency-Audit** gemäß Sprache (`npm audit --omit=dev`, `pip-audit`, `osv-scanner`, …), falls das Projekt Dependencies hat; High/Critical → Befund (`security/R07`).
- Authz-Probe (falls zutreffend): geschützte Route ohne / mit falschem Token aufrufen → **401/403** erwartet (`security/R04`).
