/**
 * Security-Baseline — HTTP-Security-Response-Header (Fabrik-Standard „Born-Secure").
 *
 * Vorlage: wird von `new-project` in ein Web-/HTTP-fassendes Node-Projekt kopiert
 * (z.B. nach `src/securityHeaders.js`) und dort verdrahtet. Setzt die OWASP-Standard-
 * Header (Norm-Regel `security/R17`) und kapselt den ENV-Schalter, der interaktive
 * API-Docs/Introspection in Produktion abschaltet (`security/R18`).
 *
 * Reiner Header-Aufsatz — kein messbarer Laufzeit-Overhead (Spec AC7). Konservative,
 * maximal härtende Startwerte; pro App gelockert, nicht verschärft.
 *
 * ESM-Stil (`"type": "module"` in package.json). Für CommonJS `export` → `module.exports`.
 *
 * Referenz:
 * - OWASP Secure Headers Project — https://owasp.org/www-project-secure-headers/
 * - docs/architecture/born-secure-baseline.md (Teil B)
 * - knowledge/security.md — security/R17 + security/R18
 */

// --------------------------------------------------------------------------- //
// Header-Satz (security/R17)
// --------------------------------------------------------------------------- //
// Konservative Startwerte: sie härten maximal und werden pro App gelockert
// (nicht umgekehrt). Anpass-Kandidaten sind i.d.R. CSP, COEP und Permissions-Policy.
export const SECURITY_HEADERS = {
  // Erzwingt HTTPS. `preload` bewusst weggelassen (irreversibel, erst nach Pruefung).
  // HSTS nur ueber TLS wirksam — bei reinem HTTP (lokal) ignoriert der Browser ihn.
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  // Restriktiver Startwert. MUSS pro App angepasst werden, sobald Skripte/Styles/
  // Fonts/Bilder von anderen Origins geladen werden (gezielt Quellen ergaenzen,
  // NICHT pauschal 'unsafe-inline'/'*' oeffnen).
  'Content-Security-Policy':
    "default-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
  // Unterbindet MIME-Sniffing.
  'X-Content-Type-Options': 'nosniff',
  // Clickjacking-Schutz fuer Alt-Browser; moderner Weg ist CSP `frame-ancestors` (s.o.).
  'X-Frame-Options': 'DENY',
  // Begrenzt Referrer-Leak ueber Origin-Grenzen.
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  // Schaltet nicht benoetigte Browser-Features ab; benoetigte gezielt freigeben.
  'Permissions-Policy': 'geolocation=(), camera=(), microphone=()',
  // Cross-Origin-Isolation. COOP/CORP `same-origin` sind sichere Defaults.
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Resource-Policy': 'same-origin',
  // COEP `require-corp` ist bewusst OPT-IN (auskommentiert): blockiert cross-origin
  // eingebettete Ressourcen (Bilder/Skripte/Fonts) ohne CORP/CORS — wahrscheinlichster
  // stiller App-Brecher. Nur einschalten, wenn du echte Cross-Origin-Isolation brauchst
  // (z.B. SharedArrayBuffer) UND alle Drittressourcen CORP/CORS liefern:
  // 'Cross-Origin-Embedder-Policy': 'require-corp',
};

/**
 * True, wenn die App in Produktion laeuft (ENV-Schalter, security/R18).
 *
 * Liest `APP_ENV` bzw. `ENVIRONMENT` (stack-uebergreifend) oder das Node-uebliche
 * `NODE_ENV`. Default: nicht-production → Docs an (dev/test-Komfort). Prod → Docs aus.
 */
export function isProduction() {
  const env = process.env.APP_ENV || process.env.ENVIRONMENT || process.env.NODE_ENV || 'development';
  return env.trim().toLowerCase() === 'production';
}

// ==========================================================================> //
// Express — Variante A: eigene Middleware (ohne Abhaengigkeit)
// ==========================================================================> //
/**
 * Express-Middleware, die den R17-Header-Satz an jede Antwort haengt.
 *
 * Registrierung (moeglichst frueh, vor den Routen):
 *
 *     import express from 'express';
 *     import { securityHeaders, isProduction } from './securityHeaders.js';
 *
 *     const app = express();
 *     app.use(securityHeaders);
 */
export function securityHeaders(req, res, next) {
  for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
    res.setHeader(key, value);
  }
  next();
}

// ==========================================================================> //
// Express — Variante B: helmet (idiomatisch, empfohlen wenn Dependency erlaubt)
// ==========================================================================> //
// `helmet` ist das idiomatische Mittel im Express-Oekosystem und pflegt die
// Header-Defaults gegen den OWASP-Stand nach. Wenn eine Dependency ok ist, Variante B
// gegenueber A bevorzugen. `npm i helmet`, dann:
//
//     import helmet from 'helmet';
//
//     app.use(
//       helmet({
//         // CSP explizit setzen — helmet-Default ist bereits streng, hier zur
//         // Sichtbarkeit/Anpassung ausgeschrieben (pro App Quellen ergaenzen).
//         contentSecurityPolicy: {
//           directives: {
//             defaultSrc: ["'self'"],
//             frameAncestors: ["'none'"],
//             baseUri: ["'self'"],
//             formAction: ["'self'"],
//           },
//         },
//         // Cross-Origin-Isolation aktiv (helmet setzt COOP/CORP per Default,
//         // COEP muss man bewusst einschalten):
//         crossOriginEmbedderPolicy: true,
//         hsts: { maxAge: 31536000, includeSubDomains: true }, // kein preload (irreversibel)
//         referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
//       }),
//     );
//
// `Permissions-Policy` deckt helmet nicht vollstaendig ab — bei Bedarf zusaetzlich
// die eigene `securityHeaders`-Middleware (Variante A) nur fuer diesen Header nutzen
// oder `res.setHeader('Permissions-Policy', ...)` setzen.

// ==========================================================================> //
// API-Docs / Introspection in Prod aus (security/R18)
// ==========================================================================> //
// Swagger-UI, OpenAPI-JSON und GraphQL-Introspection nur ausserhalb Prod exponieren:
//
//     if (!isProduction()) {
//       // Swagger-UI (z.B. swagger-ui-express) nur in dev/test mounten:
//       app.use('/docs', swaggerUi.serve, swaggerUi.setup(openApiSpec));
//       app.get('/openapi.json', (req, res) => res.json(openApiSpec));
//     }
//
//     // GraphQL (z.B. Apollo): Introspection an Prod koppeln
//     const server = new ApolloServer({
//       schema,
//       introspection: !isProduction(),
//     });
//
// Wer Docs auch in Prod braucht: NICHT oeffentlich lassen, sondern hinter
// Authentifizierung mounten (Auth-Middleware vor der Docs-Route), statt sie offen zu stellen.
