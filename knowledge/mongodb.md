# mongodb — Knowledge Pack — pluggable DB-Subsystem (Spec §3)

> **Dialekt-Auswahl:** Dieses Pack wird geladen wenn `profile.db_dialect: mongodb`. Für **relationale Workloads** (strukturierte, tabellarisch verknüpfte Daten) sind PostgreSQL/MySQL die richtige Wahl. MongoDB hier **nur** für **explizit dokumenten-orientierte Modelle**: Event-Logs, CMS-Content, polymorphe Inhalte, hierarchische Dokumente mit tiefer Einbettung.
>
> **Anti-Pattern (Critical):** Relationale Daten in Collections quetschen — normalisierte Entitäten mit häufigen "JOINs" über mehrere Collections sind ein Schema-Design-Fehler, kein MongoDB-Feature. Erkennungszeichen: `$lookup` in jedem Query-Pfad, statt eingebetteter Dokumente.

Regel-IDs: `mongo/R<NN>`. (Modell-DESIGN macht `dba`, Migrationen schreibt `coder`.)

---

## Coder-Guidance

- `mongo/R01` — **Schema-Validation per `$jsonSchema`** auf jeder Collection. `validationLevel: "strict"` (alle Inserts + Updates validieren — bereits Default, explizit setzen schützt vor zukünftigen Default-Änderungen) + `validationAction: "error"` (Operation abweisen, nicht nur loggen — bereits Default, ebenfalls explizit setzen). Validation beim `db.createCollection()`-Call setzen; nachträglich per `collMod` ergänzbar. Regel: ohne `$jsonSchema` ist eine Collection ungeprüft — das ist kein Feature, sondern ein Risiko. Quelle: [MongoDB Manual — Schema Validation](https://www.mongodb.com/docs/manual/core/schema-validation/) · [Specify JSON Schema](https://www.mongodb.com/docs/manual/core/schema-validation/specify-json-schema/)

- `mongo/R02` — **Indexes als Code**: alle Indexes via Migration (Datei in `db_scripts/`) definieren, **nicht** ad-hoc in der Shell oder per App-Startup-Hook. Mindestens ein Index auf jede Property, die in einer Query-`filter`-Achse vorkommt. Compound-Index-Reihenfolge nach der **ESR-Regel** (Equality → Sort → Range): Equality-Felder zuerst, dann Sort-Felder, dann Range-Felder (`$gt`, `$lt`, `$in` mit ≥201 Elementen, `$regex`). `createIndex()` ist idempotent wenn Name + Optionen identisch sind; Umbenennung eines bestehenden Index erfordert `dropIndex` + `createIndex`. Quelle: [MongoDB Manual — ESR Guideline](https://www.mongodb.com/docs/manual/tutorial/equality-sort-range-rule/) · [createIndex](https://www.mongodb.com/docs/manual/reference/method/db.collection.createIndex/)

- `mongo/R03` — **Aggregation Pipeline statt application-side Joins**: Transformationen, Filtern, Gruppieren und seltene cross-collection-Operationen gehören in die Pipeline (`$match`, `$group`, `$project`, `$lookup`). `$lookup` ist das letzte Mittel für Cross-Collection-Referenzen — wenn `$lookup` auf einem Query-Hauptpfad nötig ist, ist das Schema falsch denormalisiert (relationale Daten in MongoDB). Quelle: [MongoDB Manual — Aggregation](https://www.mongodb.com/docs/manual/aggregation/) · [Data Modeling — Embedded vs References](https://www.mongodb.com/docs/manual/data-modeling/concepts/embedding-vs-references/)

- `mongo/R04` — **Connection-Pool des Drivers verwenden**: `MongoClient`-Instanz einmal erstellen und applikationsweit wiederverwenden (Default-Pool: 100 Verbindungen). Kein `new MongoClient()` pro Request, kein `client.startSession()` als Long-lived-Cache. Sessions für Multi-Document-Transaktionen per `session.withTransaction()` (Callback-API — handled Retry automatisch), nicht manuell `session.startTransaction()` / `session.commitTransaction()`. Quelle: [MongoDB Node.js Driver — Connection Options](https://www.mongodb.com/docs/drivers/node/current/fundamentals/connection/connection-options/)

- `mongo/R05` — **Transaktionen nur für echte Multi-Document-Atomizität**: Single-Document-Operationen in MongoDB sind atomar — kein Multi-Document-Overhead nötig, wenn das Datenmodell korrekt eingebettet ist. Multi-Document-Transaktionen seit MongoDB 4.0 (Replica Sets) / 4.2 (Sharded Clusters) verfügbar; sie erzeugen signifikant höheren Performance-Overhead als Einzeldokument-Writes. Offiziell: *"the availability of distributed transactions should not be a replacement for effective schema design."* Quelle: [MongoDB Manual — Transactions](https://www.mongodb.com/docs/manual/core/transactions/)

---

## Migrations-Konvention (Spec §4)

**Verzeichnis:** `db_scripts/<NNN>_<name>.js` — JavaScript (mongosh-Syntax), 3-stellig nullgepaddet, lückenlos, **forward-only**. Eine committete Migration wird **nie editiert** — Korrekturen als neue höhere Nummer anhängen.

**Marker-Collection `_schema_migrations`:**
```js
// Document-Struktur (Spec §4 inkl. optionalem checksum aus §16-R5):
{ _id: "<version>", applied_at: new Date(), checksum: "<sha256>" }
// Hinweis: checksum ist optional — fehlt das Feld, wenn der Migration-Runner es nicht setzt.
// JSON/BSON erlaubt fehlende optionale Felder; kein default-Wert nötig.
```

**Idempotenz-Regeln für MongoDB (Spec §4 — mongo):**

- `db.createCollection(name, options)` — idempotent wenn Name + Options identisch; gibt `{ ok: 1 }` zurück wenn Collection bereits existiert mit gleichen Einstellungen. Achtung: andere `options` (z.B. anderer `validator`) → Serverfehler ("Collection already exists" — driver-spezifische Fehlerklasse, z.B. `MongoServerError` im Node-Driver: *"An error coming from the mongo server"*, [Node Driver API](https://mongodb.github.io/node-mongodb-native/6.0/classes/MongoServerError.html)). Migrations müssen daher Schema-Änderungen an bestehenden Collections via `collMod` durchführen, nicht via erneutes `createCollection`.
- `db.collection.createIndex(keys, {name: 'idx_x'})` — idempotent (silent no-op wenn Index mit gleichem Namen + Spec existiert).
- `updateMany` mit `{upsert: true}` — idempotent.
- `insertOne`/`insertMany` — **nicht** idempotent; bei Seed-Daten `replaceOne({_id: ...}, doc, {upsert: true})` verwenden.
- Mongo-Migrationen sind **nicht atomar über Statements hinweg** (kein DDL-Rollback wie SQL). Idempotenz ist die Mitigation: ein erneuter Lauf nach Teilfehler muss sauber durchgehen.

**Separates `migrations`-Image (Spec §16-R4):** DB-Client nicht ins App-Image backen. Stattdessen schlankes `mongo:7`-Image als one-shot-Service mit `mongosh --file run-migrations.js` zwischen DB-Healthy und App-Start.

---

## Beispiel-Migration (`db_scripts/001_init.js`)

```js
// 001_init.js — mongosh script
// Idempotent: createCollection + createIndex sind safe bei Mehrfach-Lauf

// 1. Marker-Collection sicherstellen
if (!db.getCollectionNames().includes('_schema_migrations')) {
  db.createCollection('_schema_migrations');
}

// 2. Version bereits angewandt?
const VERSION = '001';
if (db._schema_migrations.findOne({ _id: VERSION })) {
  print('Migration ' + VERSION + ' already applied — skip');
  quit(0);
}

// 3. Collection mit $jsonSchema-Validator anlegen
db.createCollection('events', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      title: 'Event Validation',
      required: ['type', 'occurredAt', 'payload'],
      properties: {
        type:       { bsonType: 'string', description: 'Event type — required' },
        occurredAt: { bsonType: 'date',   description: 'Timestamp — required' },
        payload:    { bsonType: 'object', description: 'Event payload — required' }
      }
    }
  },
  validationLevel:  'strict',
  validationAction: 'error'
});

// 4. Indexes (ESR-Beispiel: Equality=type, Sort=occurredAt)
db.events.createIndex({ type: 1, occurredAt: -1 }, { name: 'idx_events_type_date' });

// 5. Migration als angewandt markieren
db._schema_migrations.insertOne({ _id: VERSION, applied_at: new Date() });
print('Migration ' + VERSION + ' applied.');
```

---

## Reviewer-Checklist

- Collection ohne `$jsonSchema`-Validator erstellt → **Critical** (`mongo/R01`).
- `validationAction: "warn"` statt `"error"` in Production-Collections → **Important** (Fehler werden stillschweigend geloggt, nicht abgewiesen).
- Index ad-hoc (in App-Code oder Shell) statt in Migration definiert → **Important** (`mongo/R02`).
- Compound-Index-Reihenfolge verletzt ESR (Range-Feld vor Sort-Feld) → **Important** (`mongo/R02`).
- `$lookup` auf Query-Hauptpfad — prüfen ob Schema falsch denormalisiert → **Important** (`mongo/R03`).
- `new MongoClient()` pro Request oder pro Handler → **Critical** (Connection-Pool-Erschöpfung unter Last) (`mongo/R04`).
- Multi-Document-Transaktion für Single-Document-Operationen → **Important** (`mongo/R05`).
- Bereits angewandte Migration editiert / umnummeriert → **Critical**.
- `insertOne` in Migration ohne Idempotenz-Guard (kein `upsert`, kein `findOne`-Check) → **Important**.
- Relationale Daten in MongoDB-Collections modelliert (normalisierte Entitäten, häufige `$lookup`) — Header-Anti-Pattern verletzt → **Critical** (falscher Dialekt gewählt).

## Test-Approach

- Migration läuft sauber **und** idempotent: `mongosh --file 001_init.js` zweimal ausführen → beide Läufe `exit 0`; Marker `_schema_migrations.findOne({_id: '001'})` existiert genau einmal.
- Schema-Validation-Probe: Insert eines invaliden Dokuments (fehlendes Pflichtfeld) → Serverfehler mit Validation-Failure erwartet (im Node-Driver: `MongoServerError`).
- Connection-Pool-Probe: MongoClient-Singleton nachweisen (keine mehrfache Instanziierung im App-Code).
