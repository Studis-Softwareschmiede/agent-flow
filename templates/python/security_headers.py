"""Security-Baseline — HTTP-Security-Response-Header (Fabrik-Standard „Born-Secure").

Vorlage: wird von `new-project` in ein Web-/HTTP-fassendes Python-Projekt kopiert
(z.B. nach ``app/security_headers.py``) und dort verdrahtet. Setzt die OWASP-Standard-
Header (Norm-Regel ``security/R17``) und kapselt den ENV-Schalter, der interaktive
API-Docs in Produktion abschaltet (``security/R18``).

Reiner Header-Aufsatz — kein messbarer Laufzeit-Overhead (Spec AC7). Konservative,
maximal härtende Startwerte; pro App gelockert, nicht verschärft.

Referenz:
- OWASP Secure Headers Project — https://owasp.org/www-project-secure-headers/
- docs/architecture/born-secure-baseline.md (Teil B)
- knowledge/security.md — security/R17 + security/R18
"""

from __future__ import annotations

import os

# --------------------------------------------------------------------------- #
# Header-Satz (security/R17)
# --------------------------------------------------------------------------- #
# Konservative Startwerte: sie härten maximal und werden pro App gelockert
# (nicht umgekehrt). Anpass-Kandidaten sind i.d.R. CSP, COEP und Permissions-Policy.
SECURITY_HEADERS: dict[str, str] = {
    # Erzwingt HTTPS. `preload` bewusst weggelassen (irreversibel, erst nach Prüfung).
    # HSTS nur über TLS senden — bei reinem HTTP (lokal) wird der Header ignoriert.
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
    # Restriktiver Startwert. MUSS pro App angepasst werden, sobald Skripte/Styles/
    # Fonts/Bilder von anderen Origins geladen werden (dann gezielt Quellen ergänzen,
    # NICHT pauschal 'unsafe-inline'/'*' öffnen).
    "Content-Security-Policy": "default-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
    # Unterbindet MIME-Sniffing.
    "X-Content-Type-Options": "nosniff",
    # Clickjacking-Schutz für Alt-Browser; moderner Weg ist CSP `frame-ancestors` (s.o.).
    "X-Frame-Options": "DENY",
    # Begrenzt Referrer-Leak über Origin-Grenzen.
    "Referrer-Policy": "strict-origin-when-cross-origin",
    # Schaltet nicht benötigte Browser-Features ab; benötigte gezielt freigeben.
    "Permissions-Policy": "geolocation=(), camera=(), microphone=()",
    # Cross-Origin-Isolation. COEP `require-corp` ggf. lockern, wenn Drittressourcen
    # eingebettet werden, die kein CORP/CORS mitliefern.
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    "Cross-Origin-Resource-Policy": "same-origin",
}


def is_production() -> bool:
    """True, wenn die App in Produktion läuft (ENV-Schalter, security/R18).

    Liest ``APP_ENV`` bzw. ``ENVIRONMENT`` (stack-üblicher Name). Default:
    nicht-production → Docs an (dev/test-Komfort). Prod → Docs aus.
    """
    env = os.getenv("APP_ENV") or os.getenv("ENVIRONMENT") or "development"
    return env.strip().lower() == "production"


# ==========================================================================> #
# FastAPI (empfohlen: ASGI-Middleware)
# ==========================================================================> #
try:
    from starlette.types import ASGIApp, Message, Receive, Scope, Send

    class SecurityHeadersMiddleware:
        """ASGI-Middleware, die den R17-Header-Satz an jede HTTP-Antwort hängt.

        Registrierung (im App-Entry-Point, z.B. ``main.py``):

            from fastapi import FastAPI
            from app.security_headers import SecurityHeadersMiddleware, is_production

            app = FastAPI(
                # security/R18 — API-Docs in Prod aus (Default). In dev/test an.
                docs_url=None if is_production() else "/docs",
                redoc_url=None if is_production() else "/redoc",
                openapi_url=None if is_production() else "/openapi.json",
            )
            app.add_middleware(SecurityHeadersMiddleware)

        Wer die Docs auch in Prod braucht: NICHT öffentlich lassen, sondern hinter
        Authentifizierung stellen (eigene Router mit Dependency), statt die URLs zu setzen.
        """

        def __init__(self, app: "ASGIApp") -> None:
            self.app = app

        async def __call__(self, scope: "Scope", receive: "Receive", send: "Send") -> None:
            if scope["type"] != "http":  # WebSocket/Lifespan unberührt lassen
                await self.app(scope, receive, send)
                return

            async def send_with_headers(message: "Message") -> None:
                if message["type"] == "http.response.start":
                    headers = message.setdefault("headers", [])
                    for key, value in SECURITY_HEADERS.items():
                        headers.append((key.encode("latin-1"), value.encode("latin-1")))
                await send(message)

            await self.app(scope, receive, send_with_headers)

except ImportError:
    # starlette/FastAPI nicht installiert — Vorlage bleibt importierbar (nur Flask/Plain).
    SecurityHeadersMiddleware = None  # type: ignore[assignment,misc]


# --------------------------------------------------------------------------- #
# FastAPI (Alternative: Decorator-Middleware statt ASGI-Klasse)
# --------------------------------------------------------------------------- #
# Wer keine ASGI-Klasse registrieren will, kann denselben Effekt per Decorator erreichen:
#
#     @app.middleware("http")
#     async def add_security_headers(request, call_next):
#         response = await call_next(request)
#         for key, value in SECURITY_HEADERS.items():
#             response.headers[key] = value
#         return response
#
# Die ASGI-Klasse oben ist minimal schneller (kein Response-Objekt-Umweg) und daher Default.


# ==========================================================================> #
# Flask (Hinweis: after_request)
# ==========================================================================> #
# Für Flask denselben Header-Satz per `after_request`-Hook anhängen:
#
#     from flask import Flask
#     from app.security_headers import SECURITY_HEADERS, is_production
#
#     app = Flask(__name__)
#
#     @app.after_request
#     def set_security_headers(response):
#         for key, value in SECURITY_HEADERS.items():
#             response.headers.setdefault(key, value)
#         return response
#
# security/R18 in Flask: interaktive API-Docs/Schema (z.B. flask-smorest, flasgger)
# nur registrieren/exponieren, wenn `not is_production()` — sonst weglassen oder
# hinter `@login_required` stellen.
