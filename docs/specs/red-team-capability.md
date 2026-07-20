---
spec_format: use-case-2.0
status: active
---

# Spec: Red-Team-Fabrik-Fähigkeit (Skill + Agent)

> Die Fabrik-Seite der Red-Team-Fähigkeit: ein sprach-neutraler Skill + Agent, der autorisierte eigene Apps testet
> und den Sicherheits-Lernkreis schließt. Bindender Rahmen: `docs/architecture/red-team-subsystem.md`. Feature: F-031.
> **Sicherheits-Grenze:** definiert die *Fähigkeit* (Werkzeug + Verträge), NICHT ein Auto-Feuern gegen Live-Infra.

## Kontext & Motivation

Der `security`-Pack lernt heute nur aus Netz-Recherche (`train`) und Code-Review (`reviewer`→`retro`). Niemand
greift die **laufende** App an. Diese Fähigkeit ist der fehlende Produzent: sie erzeugt echte Angriffs-Funde als
Protokoll + Board-Items + Lessons und dockt so an `retro` an (Einsatz-Lane `security/E<NN>`).

## Akzeptanzkriterien

- **AC1 — Agent-Definition.** `agents/red-team.md` existiert und definiert die Rolle sprach-neutral: liest
  `knowledge/security.md`, steuert einen etablierten Scanner (Nuclei/OWASP ZAP), triagiert die Funde agentisch,
  liefert die drei Ausgänge (Protokoll, Board-Items, Lessons). Tools-Umfang begrenzt (kein destruktives Ausnutzen).
- **AC2 — Skill-Definition.** `skills/red-team/SKILL.md` existiert, dispatcht den Agenten, ist **headless-konsumierbar**
  (`claude -p /agent-flow:red-team …`) und hat einen **verbindlichen Ausgabevertrag** (maschinenlesbares End-JSON
  bei nicht-interaktivem Lauf — Muster wie `from-notes` §Headless-Ausgabevertrag).
- **AC3 — Ziel-Allowlist konstruktiv erzwungen.** Der Skill/Agent akzeptiert **kein** Freitext-Ziel. Zulässig ist
  nur die Schnittmenge „läuft auf dem eigenen VPS" ∩ „eigenes Org-Repo" (`red-team-subsystem.md` §3). Ziel außerhalb
  → sofort STOPP (Default deny).
- **AC4 — Koordination statt Tarnung.** Der Vertrag hält fest: keine Detection-Evasion; Cloudflare-Koordination
  (Freischalten vor Lauf, Scharfstellen danach) ist ein **menschlich bestätigter** Schritt. Optional zwei Messpunkte
  (durch Cloudflare + direkt am Origin) mit Differenz-Ausweis.
- **AC5 — Protokoll-Logbuch.** Jeder Lauf schreibt genau **einen** Block in `docs/red-team-audit.md` (ein Dokument pro
  Projekt, analog `spec-audit.md`): „was versucht / hat gegriffen / wurde abgewehrt" (+ Cloudflare-Differenz). Auch
  ein No-Op-Lauf (keine Funde) wird protokolliert.
- **AC6 — Board-Items + Lessons (Lernkreis).** Bestätigte Lücken werden als To-Do-Board-Items angelegt (für `/flow`);
  generalisierbare Muster werden als projekt-lokale Lesson im `retro`-lesbaren Format abgelegt, die `retro` in die
  Einsatz-Lane `security/E<NN>` heben kann (`red-team-subsystem.md` §5).
- **AC7 — Freigabe immer als PR.** Kein Self-Merge, kein Auto-Feuern; Protokoll + Board-Items landen als **ein** PR
  zur Freigabe (Muster `reconcile`). Ohne Remote/Auth: committeter lokaler Branch als Fallback.
- **AC8 — Verdrahtung.** `AGENTS.md` und `docs/architecture/red-team-subsystem.md` §8 nennen den Agenten/Skill als
  Touchpoint; der Skill ist im Plugin registriert (auffindbar wie die anderen `/agent-flow:*`-Skills).

## Bewusst NICHT (Sicherheits-Grenze)

- **Kein autonomer Live-Angriff.** Diese Spec baut die Fähigkeit; das *Feuern* gegen eine laufende App bleibt eine
  per-Lauf menschlich autorisierte Aktion (in agent-flow scaffolded, ausgelöst über die dev-gui-Kachel / bewusst).
- **Keine Detection-Evasion / Tarnung** — nur Koordination (§AC4).
- **Keine fremden Ziele** — konstruktiv ausgeschlossen (§AC3).
- **Kein destruktives Ausnutzen** — Ausnutzbarkeit wird belegt, nicht ausgenutzt.
- **Kein Scanner-Wiring gegen echte Ziele in dieser Feature-Iteration** — die Live-Integration (echter Nuclei/ZAP-Lauf
  gegen den VPS + Cloudflare-Koordination) ist die dev-gui-Kachel-Folge (`red-team-subsystem.md` §6); hier entsteht
  der Vertrag + das Gerüst, gegen das die Kachel läuft.
