#!/usr/bin/env bash
sed -i 's/\r$//' .env
set -euo pipefail
set -a
source .env
set +a

# --- Config ---
BACKUP_DIR="/backup/"
LOG_FILE="/var/log/backup.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WORKDIR=$(mktemp -d)
ARCHIVE_NAME="backup_${TIMESTAMP}.tar.gz"

DB_CONTAINER="rif_db"
ODOO_CONTAINER="rif_odoo"
DB_NAME="${POSTGRES_DB}"
DB_USER="${POSTGRES_USER}"
ODOO_FILESTORE_PATH="/var/lib/odoo"  

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT


if [ "$EUID" -ne 0 ] && [ ! -w "$BACKUP_DIR" ]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

mkdir -p "$BACKUP_DIR"

log "=== Backup started ==="

# export from postgres
log "Dumping PostgreSQL database '$DB_NAME' from container '$DB_CONTAINER'..."
if docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" > "$WORKDIR/db.sql"; then
    log "pg_dump OK ($(du -h "$WORKDIR/db.sql" | cut -f1))"
else
    log "ERROR: pg_dump failed"
    exit 1
fi

# export from odoo filestore
log "Copying Odoo filestore from container '$ODOO_CONTAINER'..."
if docker cp "${ODOO_CONTAINER}:${ODOO_FILESTORE_PATH}" "$WORKDIR/odoo-filestore"; then
    log "Filestore copy OK"
else
    log "ERROR: filestore copy failed"
    exit 1
fi

# archiving
log "Creating archive $ARCHIVE_NAME..."
tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$WORKDIR" db.sql odoo-filestore

if [ -f "$BACKUP_DIR/$ARCHIVE_NAME" ]; then
    log "Archive created: $BACKUP_DIR/$ARCHIVE_NAME ($(du -h "$BACKUP_DIR/$ARCHIVE_NAME" | cut -f1))"
else
    log "ERROR: archive creation failed"
    exit 1
fi

log "=== Backup finished successfully ==="