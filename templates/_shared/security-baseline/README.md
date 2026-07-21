# Template — `security-baseline`

Scaffold-Fragment für den Fabrik-Standard „Born-Secure" (Architektur [`docs/architecture/born-secure-baseline.md`](../../../docs/architecture/born-secure-baseline.md) Teil B, Spec [`docs/specs/security-baseline-scaffold.md`](../../../docs/specs/security-baseline-scaffold.md)).

Ein **Web-/HTTP-fassendes** Projekt der Fabrik wird damit **sicher geboren**: das Gerüst bringt die Standard-Härtung von Anfang an mit, statt sie reaktiv pro Story nachzuziehen. Der `reviewer` (Norm-Lane, `security/R17` + `security/R18`) stellt danach sicher, dass sie nicht wieder herausfällt.

Sprach-**neutral** — dieses README beschreibt den Standard; die eigentliche Middleware liegt pro Stack unter `templates/<lang>/` (siehe [Pro-Stack-Dateien](#pro-stack-dateien)).

## Der Standard

### 1. HTTP-Security-Response-Header (`security/R17`)

Jede Antwort eines web-fassenden Origins setzt die OWASP-Standard-Header:

| Header | Konservativer Startwert | Zweck |
|---|---|---|
| `Strict-Transport-Security` (HSTS) | `max-age=31536000; includeSubDomains` | Erzwingt HTTPS; nur über TLS senden. `preload` bewusst weggelassen (irreversibel). |
| `Content-Security-Policy` (CSP) | `default-src 'self'` (restriktiver Start) | Verhindert XSS/Injection. **Muss pro App angepasst werden** (siehe Kommentar in der Middleware). |
| `X-Content-Type-Options` | `nosniff` | Unterbindet MIME-Sniffing. |
| `X-Frame-Options` | `DENY` | Clickjacking-Schutz (Alt-Browser). Moderner Weg: CSP `frame-ancestors 'none'`. |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Begrenzt Referrer-Leak über Origin-Grenzen. |
| `Permissions-Policy` | `geolocation=(), camera=(), microphone=()` | Schaltet nicht benötigte Browser-Features ab. |
| `Cross-Origin-Opener-Policy` (COOP) | `same-origin` | Prozess-Isolation vom Opener. |
| `Cross-Origin-Embedder-Policy` (COEP) | **OPT-IN (Default aus)** | In den Middleware-Vorlagen **auskommentiert** — `require-corp` blockiert cross-origin eingebettete Ressourcen ohne CORP/CORS (wahrscheinlichster stiller App-Brecher). Nur einschalten, wenn du echte Cross-Origin-Isolation brauchst (z.B. `SharedArrayBuffer`). |
| `Cross-Origin-Resource-Policy` (CORP) | `same-origin` | Schützt Ressourcen vor Cross-Origin-Einbettung. |

Startwerte sind **konservativ**: sie härten maximal und werden pro App gelockert (dokumentiert im Kommentar der jeweiligen Middleware), nicht umgekehrt. CSP, COEP und `Permissions-Policy` sind die üblichen Anpass-Kandidaten.

### 2. API-Docs/Schema in Prod aus/geschützt (`security/R18`)

Interaktive API-Docs + Schema (Swagger-UI, `/docs`, `/redoc`, `/openapi.json`, GraphQL-Introspection) sind in **Produktion** deaktiviert oder authentifiziert — Schutz vor Information Disclosure.

### 3. Der ENV-Schalter

Ein einziger Umgebungs-Schalter entscheidet, ob Docs an sind:

- Variable: `APP_ENV` bzw. `ENVIRONMENT` (Stack-üblicher Name; JS/Node liest zusätzlich `NODE_ENV`).
- Wert `production` → **API-Docs aus** (Default-Verhalten in Prod).
- Jeder andere Wert / Variable ungesetzt → Docs an (Entwickler-Komfort in dev/test).

Kurz: **Default in Prod = Docs aus.** Wer Docs auch in Prod braucht, exponiert sie bewusst hinter Authentifizierung, nicht öffentlich.

## Pro-Stack-Dateien

Die Header-Middleware ist eine **Vorlage**, die `new-project` beim Aufsetzen ins Zielprojekt kopiert:

| Stack | Vorlage | Ziel im App-Repo | Framework |
|---|---|---|---|
| Python | [`templates/python/security_headers.py`](../../python/security_headers.py) | z.B. `app/security_headers.py` | FastAPI (ASGI-Middleware) + Flask-Hinweis (`after_request`) |
| JS/Node | [`templates/js/securityHeaders.js`](../../js/securityHeaders.js) | z.B. `src/securityHeaders.js` | Express (Middleware / `helmet`-Snippet) |

Weitere Stacks folgen; dieses README ist die sprach-neutrale Vorlage dafür.

## Scaffolding (`new-project`)

`new-project` (bzw. `/adopt` via `/init`) scaffoldet die Baseline **nur für Web-/HTTP-fassende Projekte** und **idempotent** — ein erneuter Lauf überschreibt vorhandene, ggf. angepasste Dateien **nicht** (Muster wie DB-Fragment- / Admin-Bereich-Scaffold). Nicht-Web-Projekte (DB-/CLI-only) bleiben unberührt.

Konkret kopiert das Scaffold für den erkannten Stack:
1. dieses `README.md` → `docs/security-baseline.md` (bzw. an eine stack-übliche Doku-Stelle),
2. die passende Middleware-Vorlage aus `templates/<lang>/` ins App-Quellverzeichnis,
3. verdrahtet sie in die App (Middleware registrieren, Docs-ENV-Schalter setzen) — dieser App-seitige Anschluss ist bewusst als kommentierter TODO in der Vorlage markiert, den `coder` beim ersten Build gegen den konkreten App-Entry-Point zieht.

## Kein Laufzeit-Overhead / kein Zwang

Die Baseline ist eine reine Header-Middleware (Mikrosekunden pro Antwort) plus weniger Prod-Endpunkte — **kein** messbarer Overhead (`security/R17`/`R18`, Spec AC7). Sie greift **nur** bei Web-Projekten; kein Zwang für DB-/CLI-only.

## Verweis

- Architektur: [`docs/architecture/born-secure-baseline.md`](../../../docs/architecture/born-secure-baseline.md) (Teil B).
- Spec: [`docs/specs/security-baseline-scaffold.md`](../../../docs/specs/security-baseline-scaffold.md) (AC3–AC7).
- Norm-Regeln + Reviewer-Checklist: [`knowledge/security.md`](../../../knowledge/security.md) — `security/R17` (Header) + `security/R18` (Docs-Exposition).
- OWASP: [Secure Headers Project](https://owasp.org/www-project-secure-headers/) · [API Security Top 10](https://owasp.org/API-Security/).
