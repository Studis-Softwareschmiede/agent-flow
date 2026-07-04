#!/usr/bin/env bash
# companion-info.sh — quick health & tuning snapshot des Redis-Companions.
#
# Companion-Scope (Spec §17): Cache/Queue/Sessions, KEIN DBA. Dieses Script
# ist Diagnose, nicht Backup/Restore — Companions haben keinen Backup-Runner.
#
# Usage:
#   ./scripts/companion-info.sh              # Default-Sektionen
#   ./scripts/companion-info.sh stats        # zusätzliche INFO-Sektion
#
# Setzt voraus: `docker compose` ist im PATH, der `redis`-Service läuft.

set -euo pipefail

SERVICE="${REDIS_SERVICE:-redis}"
SECTIONS=("server" "memory" "clients")
if [ "$#" -gt 0 ]; then
  SECTIONS+=("$@")
fi

if ! docker compose ps --services --status running | grep -qx "$SERVICE"; then
  echo "ERROR: Service '$SERVICE' läuft nicht. Start mit: docker compose up -d $SERVICE" >&2
  exit 1
fi

echo "=== redis-cli PING ==="
docker compose exec -T "$SERVICE" redis-cli ping

for section in "${SECTIONS[@]}"; do
  echo
  echo "=== INFO $section ==="
  docker compose exec -T "$SERVICE" redis-cli INFO "$section"
done
