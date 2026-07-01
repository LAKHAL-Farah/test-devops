# Runbook de restauration — ERP Odoo

## Prérequis
- Docker et Docker Compose installés
- Une archive de backup dans `/backup/backup_YYYYMMDD_HHMMSS.tar.gz`
- Fichier `.env` présent dans `apps/`, avec `ODOO_DB_NAME` défini
- **Exécuter ces commandes depuis un shell Linux natif (WSL, ou Linux/macOS directement).**
  Sous Windows, Git Bash (MINGW64) réécrit automatiquement les chemins absolus
  (`/var/lib/odoo` devient `C:/Program Files/Git/var/lib/odoo`), ce qui casse
  silencieusement `docker exec` et `docker cp`. Utiliser WSL évite ce problème.

## Procédure

1. **Arrêter et supprimer la stack existante (si applicable)**
```bash
   cd apps
   docker compose down -v
```

2. **Redémarrer uniquement la base de données**
```bash
   docker compose up -d db
   docker compose ps   # attendre que db soit "healthy"
```

3. **Extraire l'archive de backup**
```bash
   LATEST=$(ls -t /backup/backup_*.tar.gz | head -1)
   mkdir -p /tmp/restore
   tar -xzf "$LATEST" -C /tmp/restore
```

4. **Recréer la base de données vide, puis restaurer le dump**

   Sur un volume neuf, la base Odoo n'existe pas encore — `pg_dump` (sans `-C`)
   ne restaure que le contenu, pas la base elle-même. Il faut donc la créer
   explicitement avant de restaurer :
```bash
   docker exec -i rif_db createdb -U "$POSTGRES_USER" "$ODOO_DB_NAME"
   docker exec -i rif_db psql -U "$POSTGRES_USER" -d "$ODOO_DB_NAME" \
     < /tmp/restore/db.sql
```

   **Vérifier avant de continuer :**
```bash
   docker exec -i rif_db psql -U "$POSTGRES_USER" -d "$ODOO_DB_NAME" \
     -c "SELECT name, state FROM ir_module_module WHERE name='sale';"
```
   Doit retourner `state = installed`. Si ce n'est pas le cas, ne pas
   continuer — le problème est dans le dump, pas dans la suite de la procédure.

5. **Restaurer le filestore Odoo**

   Méthode recommandée — monter le volume directement via un conteneur
   jetable, ce qui évite les problèmes de permissions rencontrés avec
   `docker cp` sur un conteneur odoo durci (`cap_drop: ALL`) :
```bash
   docker run --rm \
     -v apps_odoo-filestore:/data \
     -v /tmp/restore/odoo-filestore:/src:ro \
     alpine sh -c "cp -a /src/. /data/ && chown -R 101:101 /data"
```
   (`101:101` correspond à l'UID/GID de l'utilisateur `odoo` dans l'image
   officielle — à vérifier avec `docker exec -u root rif_odoo id odoo`
   si l'image change.)

   **Méthode alternative** (si le service odoo tourne déjà et qu'on préfère
   `docker cp`) : le conteneur odoo n'a aucune capability (`cap_drop: ALL`,
   pas de `cap_add`), donc même en tant que root dans le conteneur, `chown`
   échouera avec "Permission denied". Il faut temporairement ajouter
   `CHOWN`, `DAC_OVERRIDE`, `FOWNER` dans `cap_add` du service odoo,
   relancer `docker compose up -d odoo`, faire le chown, puis retirer
   ces capabilities et relancer à nouveau. À éviter si possible — la
   méthode par volume ci-dessus est plus propre.

6. **Redémarrer la stack complète**
```bash
   docker compose up -d
   docker compose ps   # tous les services doivent être "healthy"
```
   Odoo peut rester en `health: starting` jusqu'à 60s après le démarrage
   (`start_period` du healthcheck) — c'est normal, attendre avant de
   s'inquiéter.

7. **Vérification finale**
   - Accéder à `http://erp.local`
   - Se connecter à la base restaurée (nom = `$ODOO_DB_NAME`)
   - Confirmer que le module Ventes est toujours installé

## Notes
- `docker compose down -v` supprime les volumes — à utiliser uniquement en
  cas de sinistre réel ou de test contrôlé.
- Le script `apps/backup.sh` doit être exécuté avant toute opération
  destructive pour garantir une archive récente.
- `ODOO_DB_NAME` (le nom de la base créée via l'interface Odoo) est
  distinct de `POSTGRES_DB` (base de maintenance par défaut de
  PostgreSQL) — ne pas confondre les deux lors de la restauration.