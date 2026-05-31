// 000_init_meta.js — Erste Migration jedes neuen MongoDB-Projekts
//
// Legt die Marker-Collection `_schema_migrations` an. Der Runner
// (`run-migrations.sh`) ruft diesen Guard beim Bootstrap zwar selber
// schon auf — aber wir tracken sie auch hier als reguläre Migration,
// damit `db_scripts/` allein (z.B. via mongosh --file) eine vollständige,
// idempotente Schema-Definition ist.
//
// WICHTIG (Smoke-Hotfix): Diese Datei geht davon aus, dass `db` bereits
// auf die App-DB zeigt. Der Runner (`run-migrations.sh`) garantiert das
// via `db = db.getSiblingDB(MONGO_DB); load(this-file)`. Bei manuellem
// Aufruf MUSS der Aufrufer den DB-Kontext selbst setzen (`use <db>` oder
// `mongosh --eval "db = db.getSiblingDB('<db>'); load('000_init_meta.js')"`).
// Hintergrund: mongosh's default-`db` ist in non-interaktiven --eval-
// Sessions NICHT der URI-Path, sondern `test`/`admin`.
//
// Spec §4 (Marker-Collection) + §16-R5 (optionales checksum-Feld).
// Document-Struktur:
//   { _id: "<version>", applied_at: ISODate, checksum: "<sha256>" }
//
// Idempotenz (knowledge/mongodb.md mongo/R01):
// - `createCollection` wirft, wenn die Collection bereits existiert mit
//   anderen Optionen ("Collection already exists" — MongoServerError im
//   Node-Driver). Daher Existenz-Check via `getCollectionNames()` als
//   Guard. Alternative wäre try/catch, aber der Name-Check ist
//   expliziter (klarer Intent statt Exception-Suppression).
//
// Accessor-Hinweis: `db._schema_migrations` (Dot-Notation) ist in
// mongosh UNDEFINIERT für Collection-Namen mit `_`-Präfix. Der Runner
// nutzt deshalb `db.getCollection('_schema_migrations')` zum Lesen/
// Schreiben. Hier irrelevant (`getCollectionNames()` + `createCollection`
// arbeiten auf String-Namen).

if (!db.getCollectionNames().includes('_schema_migrations')) {
  db.createCollection('_schema_migrations');
  print('[000_init_meta] Created collection _schema_migrations');
} else {
  print('[000_init_meta] Collection _schema_migrations already exists — skip');
}

// Hinweis: KEIN $jsonSchema-Validator auf dieser Tooling-Collection.
// Migration-Marker sind ein internes Schema und sollen jederzeit
// erweiterbar sein (z.B. spätere Welle: rolled_back_at, applied_by).
// $jsonSchema gilt für App-Collections (mongo/R01) — nicht für
// Tooling-Tabellen wie diese.
