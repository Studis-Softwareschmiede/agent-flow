# Datenmodell — <App>

> Teil des Detailkonzepts (**DB-Domäne**, nur bei `profile.domains` enthält `sql`). Geschrieben vom `dba`. Der `coder` setzt es 1:1 in Migrationen um (via `sql`-Pack) — hier KEIN SQL, nur das Modell.

## Entitäten
<Entität · Felder (Typ, NOT NULL / UNIQUE / CHECK) · Primärschlüssel.>

## Beziehungen
<Fremdschlüssel, Kardinalitäten.>

## Indizes
<Auf jede Filter-/FK-Spalte.>

## RLS / Zugriffskonzept
<Bei Mandantenfähigkeit: Tenant-Filter (`auth.uid()`), SECURITY-DEFINER-Grenzen, `search_path`.>

## Migrations-Reihenfolge
<Reihenfolge + harte Abhängigkeiten.>
