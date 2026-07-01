# Restore Runbook — Odoo ERP

## Prerequisites
- Docker and Docker Compose installed
- A backup archive at `/backup/backup_YYYYMMDD_HHMMSS.tar.gz`
- `.env` file present in `apps/`, with `ODOO_DB_NAME` set
- **Run these commands from a native Linux shell (WSL, or Linux/macOS directly).**
  On Windows, Git Bash (MINGW64) automatically rewrites absolute paths
  (`/var/lib/odoo` becomes `C:/Program Files/Git/var/lib/odoo`), which silently
  breaks `docker exec` and `docker cp`. Using WSL avoids this issue.

## Procedure

1. **Stop and remove the existing stack (if applicable)**
```bash
   cd apps
   docker compose down -v
```

2. **Restart only the database**
```bash
   docker compose up -d db
   docker compose ps   # wait until db is "healthy"
```

3. **Extract the backup archive**
```bash
   LATEST=$(ls -t /backup/backup_*.tar.gz | head -1)
   mkdir -p /tmp/restore
   tar -xzf "$LATEST" -C /tmp/restore
```

4. **Recreate the empty database, then restore the dump**

   On a fresh volume, the Odoo database doesn't exist yet — `pg_dump`
   (without `-C`) only restores the content, not the database itself. It
   must therefore be created explicitly before restoring:
```bash
   docker exec -i rif_db createdb -U "$POSTGRES_USER" "$ODOO_DB_NAME"
   docker exec -i rif_db psql -U "$POSTGRES_USER" -d "$ODOO_DB_NAME" \
     < /tmp/restore/db.sql
```

   **Verify before continuing:**
```bash
   docker exec -i rif_db psql -U "$POSTGRES_USER" -d "$ODOO_DB_NAME" \
     -c "SELECT name, state FROM ir_module_module WHERE name='sale';"
```
   Must return `state = installed`. If not, do not continue — the problem
   is in the dump, not in the rest of the procedure.

5. **Restore the Odoo filestore**

   Recommended method — mount the volume directly via a disposable
   container, which avoids the permission issues encountered with
   `docker cp` on a hardened odoo container (`cap_drop: ALL`):
```bash
   docker run --rm \
     -v apps_odoo-filestore:/data \
     -v /tmp/restore/odoo-filestore:/src:ro \
     alpine sh -c "cp -a /src/. /data/ && chown -R 101:101 /data"
```
   (`101:101` corresponds to the UID/GID of the `odoo` user in the
   official image — verify with `docker exec -u root rif_odoo id odoo`
   if the image changes.)

   **Alternative method** (if the odoo service is already running and
   `docker cp` is preferred): the odoo container has no capabilities
   (`cap_drop: ALL`, no `cap_add`), so even as root inside the container,
   `chown` will fail with "Permission denied". You must temporarily add
   `CHOWN`, `DAC_OVERRIDE`, `FOWNER` to the odoo service's `cap_add`,
   restart with `docker compose up -d odoo`, perform the chown, then
   remove these capabilities and restart again. Avoid this if possible —
   the volume-based method above is cleaner.

6. **Restart the full stack**
```bash
   docker compose up -d
   docker compose ps   # all services must be "healthy"
```
   Odoo may stay in `health: starting` for up to 60s after startup
   (healthcheck `start_period`) — this is normal, wait before worrying.

7. **Final verification**
   - Access `http://erp.local`
   - Log in to the restored database (name = `$ODOO_DB_NAME`)
   - Confirm that the Sales module is still installed

## Notes
- `docker compose down -v` removes volumes — use only in the case of an
  actual disaster or a controlled test.
- The `apps/backup.sh` script must be run before any destructive
  operation to guarantee a recent archive.
- `ODOO_DB_NAME` (the name of the database created via the Odoo UI) is
  distinct from `POSTGRES_DB` (PostgreSQL's default maintenance
  database) — do not confuse the two during restoration.