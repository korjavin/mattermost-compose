# mattermost-compose

Self-hosted [Mattermost](https://mattermost.com/) team messaging platform deployed via Portainer with Traefik reverse proxy and GitHub Actions git-ops automation.

## Prerequisites

- Docker + Docker Compose v1.28+
- Traefik running and accessible via the configured external network
- Portainer instance
- GitHub repository for this project

## Services

| Service | Image | Purpose |
|---------|-------|---------|
| `mattermost` | `mattermost-team-edition` (vendored) | Main application |
| `mattermost-db` | `postgres:16-alpine` (vendored) | Database |
| `mattermost-backup` | `mattermost-backup` (built) | Optional restic backups — enabled via the `backup` compose profile |

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MATTERMOST_IMAGE` | Yes | GHCR vendored | Mattermost Docker image |
| `POSTGRES_IMAGE` | Yes | GHCR vendored | PostgreSQL Docker image |
| `MATTERMOST_HOST` | Yes | — | Public hostname (e.g. `chat.example.com`) |
| `POSTGRES_PASSWORD` | Yes | — | Database password — generate with `openssl rand -hex 32` |
| `POSTGRES_DB` | No | `mattermost` | Database name |
| `POSTGRES_USER` | No | `mattermost` | Database user |
| `MATTERMOST_CONTAINER_NAME` | No | `mattermost` | Container name |
| `DB_CONTAINER_NAME` | No | `mattermost-db` | DB container name |
| `TRAEFIK_NETWORK_NAME` | No | `traefik_default` | External Traefik network name |
| `INTERNAL_NETWORK_NAME` | No | `mattermost_internal` | Internal network name |
| `DB_VOLUME_NAME` | No | `mattermost_db-data` | Named volume for postgres data |
| `TRAEFIK_CERTRESOLVER` | No | `myresolver` | Traefik cert resolver name |
| `TIMEZONE` | No | `UTC` | Container timezone |
| `MATTERMOST_CONFIG_PATH` | No | `./volumes/mattermost/config` | Config bind-mount path |
| `MATTERMOST_DATA_PATH` | No | `./volumes/mattermost/data` | Data bind-mount path |
| `MATTERMOST_LOGS_PATH` | No | `./volumes/mattermost/logs` | Logs bind-mount path |
| `MATTERMOST_PLUGINS_PATH` | No | `./volumes/mattermost/plugins` | Plugins bind-mount path |
| `MATTERMOST_CLIENT_PLUGINS_PATH` | No | `./volumes/mattermost/client/plugins` | Client plugins bind-mount path |
| `MATTERMOST_BLEVE_INDEXES_PATH` | No | `./volumes/mattermost/bleve-indexes` | Bleve search index path |

## Portainer Setup

1. **Create a new stack** in Portainer:
   - Repository URL: `https://github.com/korjavin/mattermost-compose`
   - Branch: `deploy` ← **important: not master**
   - Compose path: `docker-compose.yml`

2. **Set environment variables** from `.env.example` — at minimum:
   - `MATTERMOST_HOST`
   - `POSTGRES_PASSWORD`
   - `MATTERMOST_IMAGE` (set to your GHCR vendored image)
   - `POSTGRES_IMAGE` (set to your GHCR vendored image)

3. **Copy the webhook URL** from Portainer (Stack → Webhooks)

4. **Add GitHub secret**:
   - Go to repo Settings → Secrets → Actions → New secret
   - Name: `PORTAINER_REDEPLOY_HOOK`
   - Value: (paste Portainer webhook URL)

5. **Prepare data directories** on the Docker host (must be owned by UID/GID 2000:2000):
   ```bash
   mkdir -p ./volumes/mattermost/{config,data,logs,plugins,client/plugins,bleve-indexes}
   sudo chown -R 2000:2000 ./volumes/mattermost
   ```

6. **Trigger first deploy** — push to master or run the workflow manually in GitHub Actions

## How Updates Work

- Push to `master` → GitHub Actions syncs the `deploy` branch → Portainer reloads the stack
- **Image updates** — the `vendor-images.yml` workflow runs weekly (Monday 04:00 UTC), mirrors upstream images to GHCR, and triggers a redeploy. Update `MATTERMOST_IMAGE` in Portainer env vars to pin a specific digest.

## GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `PORTAINER_REDEPLOY_HOOK` | Portainer stack webhook URL |

## GHCR Packages

After the first vendor workflow run, set package visibility:
- `github.com/korjavin` → Packages → `mattermost-vendor` → Settings → visibility
- `github.com/korjavin` → Packages → `mattermost-postgres-vendor` → Settings → visibility

## Backups (optional)

An optional `mattermost-backup` sidecar runs [restic](https://restic.net/) on a
schedule, backing up the Postgres database (via `pg_dump`) and the file store to
any restic-supported backend (Backblaze B2, S3-compatible, SFTP). Backups are
encrypted and deduplicated.

**It is disabled by default.** To enable it:

1. Build the image once — push to `master` (the `Build Backup Image` workflow
   builds `ghcr.io/korjavin/mattermost-backup:latest`), or run that workflow
   manually.
2. In Portainer stack env vars, set:
   - `COMPOSE_PROFILES=backup`
   - `RESTIC_REPOSITORY` (e.g. `b2:my-bucket:mattermost`)
   - `RESTIC_PASSWORD` (generate with `openssl rand -hex 32` — **store it off-server**)
   - the credential pair for your backend (`B2_ACCOUNT_ID`/`B2_ACCOUNT_KEY` or `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`)
   - optionally tune `BACKUP_INTERVAL_SECONDS` (default 86400 = daily) and
     `RESTIC_KEEP_DAILY`/`WEEKLY`/`MONTHLY`
3. Redeploy the stack. The sidecar initializes the repo on first run, then backs
   up on the configured interval.

### Restore

Run commands against the running sidecar on the host:

```bash
# List snapshots / verify repo
docker exec mattermost-backup backup.sh snapshots
docker exec mattermost-backup backup.sh check

# Restore the database into the running DB container
docker exec mattermost-backup backup.sh restore-db \
  | docker exec -i mattermost-db psql -U mattermost mattermost

# Restore the file store into a directory, then copy it back into place
docker exec mattermost-backup backup.sh restore-files /tmp/restore
```

> Test a restore periodically — an untested backup is only a hope.

## Links

- [Mattermost Docker repo](https://github.com/mattermost/docker)
- [Mattermost deployment docs](https://docs.mattermost.com/deployment-guide/server/deploy-containers.html)
- [Mattermost releases](https://github.com/mattermost/mattermost/releases)
