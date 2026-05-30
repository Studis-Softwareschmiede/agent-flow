// 000_init_meta.js — Erste Migration jedes neuen MongoDB-Projekts
//
// Legt die Marker-Collection `_schema_migrations` an. Der Runner
// (`run-migrations.sh`) ruft diesen Guard beim Bootstrap zwar selber
// schon auf — aber wir tracken sie auch hier als reguläre Migration,
// damit `db_scripts/` allein (z.B. via mongosh --file) eine vollständige,
// idempotente Schema-Definition ist.
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
