# test-devops 

Status: Phase 1 done (stack + hardening). 
Backup/restore and full docs still to come.

## Stack

- `db`: postgres:15, no ports exposed, healthcheck via `pg_isready`
- `odoo`: odoo:17, exposed on 8069, healthcheck via HTTP request to `/web/login`
- `nginx`: reverse proxy, exposed on 80, routes `erp.local` -> odoo

Containers are hardened: `read_only` filesystem where possible, `cap_drop: ALL` with only the specific capabilities added back that testing showed were needed, `no-new-privileges`. `depends_on` uses object form with `condition: service_healthy` so each service waits for the previous one to actually be ready, not just started.

## Run it

```bash
cd apps
cp .env.example .env      
docker compose up -d
docker compose ps         
```

Add to `/etc/hosts`:
```
127.0.0.1 erp.local
```

Then open `http://erp.local`.

