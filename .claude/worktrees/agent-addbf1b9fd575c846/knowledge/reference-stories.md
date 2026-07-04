# Knowledge Pack: reference-stories (Anker für die Dispo-Schätzung)

> **last_curated:** 2026-06-14 — Frische-Signal. Pflege erfolgt durch den `retro`-Agenten **über PR+Gate** (nie Direkt-Edit), wenn er aus realen, gut kalibrierten Done-Stories bessere Anker destilliert. Bindende Spec: `docs/specs/estimator.md` (V2, V9).
>
> **Zweck.** Kanonische **Referenz-Stories** als Few-shot-Anker für den `estimator`-Agenten. Er schätzt L/XL-Stories **relativ** gegen diese Anker (Analogy-Based Estimation + Few-shot). Der Katalog ist **scale-aware**: je Grössenklasse mindestens ein Anker, damit die volle Spannweite abgedeckt ist.
>
> **non_anchors:** Stories ohne stabiles `ep_act`, Ausreißer (einmalige Sondersituationen), unfertige/abgebrochene Items — nie als Anker aufnehmen.

## Wie der estimator diesen Katalog nutzt

1. Lädt die scale-aware Anker (S/M/L/XL) — Stack-spezifische (`lang` gesetzt) bevorzugt, sonst die generischen.
2. Ergänzt sie um die K ähnlichsten **realen** Done-Stories aus `.claude/metrics/items.jsonl` (Ähnlichkeitsfunktion S1).
3. Schätzt `dispo_est` relativ gegen die so entstandene Beispiel-Menge.

Mit wachsender Historie verschiebt sich das Gewicht von den kuratierten Ankern hin zu retrievten realen Stories; dieser Katalog bleibt der **Cold-Start-Boden** und die Skala-Referenz.

## Feldbedeutung

| Feld | Bedeutung |
|---|---|
| `id` | stabile Anker-ID (kebab-case) |
| `size` | `S` \| `M` \| `L` \| `XL` |
| `lang` | Stack; `generic` = stack-unabhängiger Anker |
| `title` | kanonische Story-Beschreibung |
| `n_ac` / `n_comp` / `labels` | Fingerprint (Basis für den Ähnlichkeitsbezug) |
| `ep_anchor` | Anker-Aufwand in EP |
| `note` | warum dieser Anker repräsentativ ist |

## Generische Anker (scale-aware Boden)

| id | size | lang | title | n_ac | n_comp | labels | ep_anchor | note |
|---|---|---|---|---|---|---|---|---|
| `ref-S-form-field` | S | generic | Ein Feld + Validierung zu bestehendem Formular hinzufügen | 2 | 1 | — | 2 | Kleinste sinnvolle Einheit: lokale Änderung, kein neuer Datenfluss, triviale Tests. |
| `ref-M-crud-endpoint` | M | generic | Neuer CRUD-Endpunkt inkl. Unit-Tests | 4 | 2 | — | 4 | Standard-Arbeitspaket: ein klar umrissener Endpunkt gegen bestehende Strukturen. |
| `ref-L-subsystem-slice` | L | generic | Neuer Subsystem-Slice mit DB-Migration + Tests + UI | 10 | 3 | db | 8 | Mehrere Komponenten, Migration, durchgängiger Pfad — typische L-Story. |
| `ref-XL-external-integration` | XL | generic | Externe API-Integration: Auth + Retry + Fehlerpfade + e2e | 14 | 5 | security | 13 | Hohe Unsicherheit (externe Abhängigkeit, viele Fehlerpfade) — meist **Split-Kandidat**. |

## Stack-spezifische Anker

> Noch keine. Sobald je Stack (`lang`) genug kalibrierte Historie vorliegt, destilliert `retro` hier stack-spezifische Anker (mit gesetztem `lang`), die den generischen vorgezogen werden. Bis dahin tragen die generischen Anker den Cold-Start.

## Pflege-Hinweise (für `retro`)

- **Scale-aware halten:** jede Grössenklasse braucht mindestens einen aktuellen Anker.
- **Aus realen Done-Stories destillieren:** bevorzugt Stories mit stabilem `ep_act` nahe dem Klassen-Median.
- **Veraltete/abweichende Anker ersetzen**, nicht stapeln — der Katalog bleibt schlank und repräsentativ.
- **Immer als PR** (Autonomie-Grenze: numerische `estimator_bias`-Faktoren ändert `retro` automatisch, diesen Katalog nur über PR+Gate).
