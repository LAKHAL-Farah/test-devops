# ERP Odoo — Stack Docker (Odoo + PostgreSQL + Nginx)

## Prérequis

- Docker Engine + Docker Compose v2
- Un shell Linux natif (WSL sur Windows, ou Linux/macOS). Éviter Git Bash
  sous Windows : il réécrit les chemins absolus (`/var/lib/...`) et casse
  silencieusement `docker exec`/`docker cp`.
- Port 80 et 8069 libres sur la machine hôte
- `sudo` pour modifier `/etc/hosts` (accès via `erp.local`)

## Démarrage (5 commandes)

```bash
git clone https://github.com/LAKHAL-Farah/test-devops.git && cd test-selection-devops/apps
cp .env.example .env        # puis éditer .env avec de vraies valeurs
docker compose up -d
sudo sh -c 'echo "127.0.0.1 erp.local" >> /etc/hosts'
```

Ouvrir `http://erp.local` (ou `http://localhost:8069`).

Vérifier que tout tourne :
```bash
docker compose ps   # les 3 services doivent être "healthy"
```

Au premier démarrage, Odoo affiche l'écran de création de base de données :
créer une base, noter son nom exact, et le renseigner dans `.env` sous
`ODOO_DB_NAME` (nécessaire pour les scripts de backup/restauration).

## Architecture

- `db` (postgres:15) — aucun port publié, accessible uniquement depuis
  `odoo` via le réseau interne `backend`.
- `odoo` (odoo:17) — exposé sur `:8069`.
- `nginx` — reverse proxy sur `:80`, route `erp.local` vers `odoo:8069`.

## Sauvegarde

```bash
cd apps
./backup.sh
```

Crée une archive `backup_YYYYMMDD_HHMMSS.tar.gz` dans `/backup/`, contenant
un dump PostgreSQL (`pg_dump`, sans arrêter les conteneurs) et une copie du
filestore Odoo. Chaque opération est journalisée dans `/var/log/backup.log`.

Une entrée cron peut être ajoutée pour l'exécuter automatiquement chaque
nuit à 02h00 :
```bash
crontab -e
# ajouter :
0 2 * * * /chemin/absolu/vers/apps/backup.sh >> /var/log/backup.log 2>&1
```

## Restauration

Procédure complète et détaillée : voir [`docs/restauration.md`](docs/restauration.md).

Résumé rapide :
```bash
docker compose down -v                          # simulate/actual crash
docker compose up -d db                          # DB seule d'abord
docker exec -i rif_db createdb -U "$POSTGRES_USER" "$ODOO_DB_NAME"
docker exec -i rif_db psql -U "$POSTGRES_USER" -d "$ODOO_DB_NAME" < db.sql
# puis restaurer le filestore — voir docs/restauration.md pour la méthode
docker compose up -d
```

## Dépannage rapide

- **`db` unhealthy** : vérifier `POSTGRES_USER`/`POSTGRES_DB` dans `.env`.
- **`odoo` unhealthy après restauration du filestore** : problème de
  permissions sur `/var/lib/odoo` (le conteneur tourne en non-root avec
  capabilities réduites). Voir la section dédiée dans `docs/restauration.md`.
- **`nginx` reste `unhealthy`** : dépend d'`odoo` étant `healthy` en premier
  (`depends_on: condition: service_healthy`) — vérifier `odoo` avant nginx.