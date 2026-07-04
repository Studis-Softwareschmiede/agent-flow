# Template — `companion-redis`

Erster Companion-Sidecar-Template-Satz (Spec [`docs/architecture/db-subsystem.md`](../../../docs/architecture/db-subsystem.md) §17). Companions sind stateful Sidecars **OHNE** Schema-Evolution — Redis ist die Referenz-Implementierung.

## Inhalt

| Datei | Zweck |
|---|---|
| `compose.fragment.yml` | Compose-Snippet (service `redis` + volume `redis_data`) — beim Scaffold ans Projekt-`docker-compose.yml` angehängt. |
| `.env.redis.example` | Vorlage für Connection-Env (`REDIS_HOST` / `REDIS_PORT`). |
| `scripts/companion-info.sh` | Quick-Health/Tuning-Check (`redis-cli INFO server|memory|clients`). |

## Wann nutzen

Typische Use-Cases (alle ohne durable Business-Schema):

- **Cache** (HTTP-Response, DB-Query-Memoization, Rendered-Templates).
- **Session-Store** (`connect-redis`, Flask-Session, Spring-Session).
- **Rate-Limit** (Token-Bucket via `INCR` + `EXPIRE`).
- **Job-Queue** (BullMQ, Celery-Broker, RQ, Sidekiq).
- **Pub-Sub / Real-Time-Fanout** (`PUBLISH`/`SUBSCRIBE`, Socket.IO-Adapter).

## Wie aktivieren

In `.claude/profile.md` die Companion-Liste erweitern:

```yaml
companions: [redis]
```

Dann (analog DB-Subsystem) das Fragment ans Projekt-Compose anhängen:

```bash
echo "" >> docker-compose.yml
echo "# --- companion-redis (source: templates/_shared/companion-redis/compose.fragment.yml) ---" >> docker-compose.yml
cat ${CLAUDE_PLUGIN_ROOT}/templates/_shared/companion-redis/compose.fragment.yml >> docker-compose.yml
cp ${CLAUDE_PLUGIN_ROOT}/templates/_shared/companion-redis/.env.redis.example .
```

`/agent-flow:adopt` und `/agent-flow:new-project` erledigen das automatisch, wenn `redis` in `profile.companions` steht (Detection bzw. `--companions redis`-Flag).

## Connect-Pattern für die App

Connection via Service-DNS, Pool im App-Code (kein neuer Client pro Request):

```js
// Node — ioredis
import Redis from "ioredis";
export const redis = new Redis({
  host: process.env.REDIS_HOST ?? "redis",
  port: Number(process.env.REDIS_PORT ?? 6379),
  // production: password: process.env.REDIS_PASSWORD
});
```

```python
# Python — redis-py mit Connection-Pool
import os, redis
pool = redis.ConnectionPool(
    host=os.environ.get("REDIS_HOST", "redis"),
    port=int(os.environ.get("REDIS_PORT", 6379)),
    decode_responses=True,
)
r = redis.Redis(connection_pool=pool)
```

`REDIS_HOST` / `REDIS_PORT` kommen aus `.env.redis` (in `.gitignore`); die `.example` ist die committete Vorlage.

## Production-Setup (Passwort)

Default-Container ist passwortlos — im SMB-Single-VPS-Setup reicht das (Companion ist intern-only, kein Port-Mapping). Bei Multi-Tenant-VPS, Cross-Network-Zugriff oder externem Audit-Druck:

1. `REDIS_PASSWORD=<random-32-chars>` in `.env.redis` (über `.env.gpg` versioniert verschlüsseln).
2. Im `compose.fragment.yml`-Service ergänzen: `command: ["redis-server", "--requirepass", "${REDIS_PASSWORD}"]` und `env_file: [.env.redis]`.
3. App-Client um `password: process.env.REDIS_PASSWORD` erweitern.

Passwort NIE als Default in der `.env.redis.example` — dort bleibt es leer, der Mensch entscheidet beim Production-Roll-Out.

## Klare Abgrenzung — was hier NICHT lebt

**Companion ≠ DB-Subsystem.** Wer Schema-Evolution, Migrations-Runner oder Backup braucht, gehört in `templates/_shared/db-<dialect>/` (Spec §4–§7), nicht hier.

| Aspekt | DB-Subsystem (§5/§6/§7) | Companion-Redis (§17) |
|---|---|---|
| Schema-Evolution | `db_scripts/<NNN>_*.sql` + Marker | **keine** — Redis ist schemalos / RAM-first |
| Migrations-Runner | `run-migrations.sh` + `_schema_migrations` | **keiner** — Daten sind ephemer/regenerierbar |
| Backup | `pg_dump` / `mongodump` Skripte | **keiner im Default** — AOF/RDB ist Container-internes Persistence-Feature, nicht ein Backup-Workflow |
| Knowledge-Pack | `knowledge/sql*.md` / `mongodb.md` | **keines** — Companion hat keinen eigenen Pack |
| DBA-Agent-Audit | dispatcht bei `db_dialect != none` | **kein Dispatch** — Companion ist Infra, nicht DB |
| `profile`-Slot | `db_dialect: <enum>` (Single-Value) | `companions: [redis, ...]` (Array, additiv) |

Wer Redis als **primären** Datenstore (z.B. Event-Sourcing-Backbone, einziges System-of-Record) nutzen möchte, ist im DB-Subsystem falsch UND im Companion-Pfad falsch — das ist explizit out-of-scope für P1 und braucht einen eigenen Spec-PR.

## Quick-Check

```bash
docker compose up -d redis
docker compose exec redis redis-cli ping              # → PONG
bash scripts/companion-info.sh                        # server + memory + clients
```
