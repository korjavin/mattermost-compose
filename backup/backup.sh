#!/bin/sh
# Restic backup sidecar for the Mattermost compose stack.
#
# Backs up:
#   1. The Postgres database  -> streamed via pg_dump into restic (tag: db)
#   2. The Mattermost file store (/data, read-only mount) -> restic (tag: files)
#
# Everything is encrypted + deduplicated by restic and shipped to any
# restic-supported backend (Backblaze B2, S3-compatible, SFTP, ...).
#
# Subcommands:
#   backup           run a backup now (default). If BACKUP_INTERVAL_SECONDS is
#                    set, loops forever sleeping that long between runs.
#   snapshots        list snapshots
#   check            verify repository integrity
#   prune            apply the retention policy now
#   restore-db       stream the latest DB dump to stdout (pipe into psql)
#   restore-files D  restore the latest file store snapshot into directory D
#   <anything else>  passed straight through to restic
set -eu

HOSTTAG="mattermost"

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

: "${RESTIC_REPOSITORY:?set RESTIC_REPOSITORY (e.g. b2:bucket:path or s3:host/bucket/path)}"
: "${RESTIC_PASSWORD:?set RESTIC_PASSWORD (repository encryption key)}"

POSTGRES_DB="${POSTGRES_DB:-mattermost}"
POSTGRES_USER="${POSTGRES_USER:-mattermost}"
PGHOST="${PGHOST:-mattermost-db}"
PGPORT="${PGPORT:-5432}"
DATA_PATH="${BACKUP_DATA_PATH:-/data}"
KEEP_DAILY="${RESTIC_KEEP_DAILY:-7}"
KEEP_WEEKLY="${RESTIC_KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${RESTIC_KEEP_MONTHLY:-6}"

ensure_repo() {
  if ! restic cat config >/dev/null 2>&1; then
    log "Repository not initialized; running 'restic init'"
    restic init
  fi
}

do_backup() {
  ensure_repo
  log "Dumping database '${POSTGRES_DB}' from ${PGHOST}:${PGPORT}"
  pg_dump --clean --if-exists --no-owner --no-privileges \
      -h "${PGHOST}" -p "${PGPORT}" -U "${POSTGRES_USER}" "${POSTGRES_DB}" \
    | restic backup --stdin --stdin-filename mattermost-db.sql \
        --host "${HOSTTAG}" --tag db

  if [ -d "${DATA_PATH}" ]; then
    log "Backing up file store ${DATA_PATH}"
    restic backup "${DATA_PATH}" --host "${HOSTTAG}" --tag files
  else
    log "WARN: ${DATA_PATH} not found; skipping file store backup"
  fi

  log "Applying retention: daily=${KEEP_DAILY} weekly=${KEEP_WEEKLY} monthly=${KEEP_MONTHLY}"
  restic forget --prune \
    --keep-daily "${KEEP_DAILY}" \
    --keep-weekly "${KEEP_WEEKLY}" \
    --keep-monthly "${KEEP_MONTHLY}"

  log "Backup finished"
}

cmd="${1:-backup}"
case "${cmd}" in
  backup)
    if [ -n "${BACKUP_INTERVAL_SECONDS:-}" ]; then
      log "Scheduled mode: backup every ${BACKUP_INTERVAL_SECONDS}s"
      while :; do
        do_backup || log "Backup run failed; will retry next interval"
        sleep "${BACKUP_INTERVAL_SECONDS}"
      done
    else
      do_backup
    fi
    ;;
  snapshots) ensure_repo; exec restic snapshots ;;
  check)     ensure_repo; exec restic check ;;
  prune)
    ensure_repo
    exec restic forget --prune \
      --keep-daily "${KEEP_DAILY}" --keep-weekly "${KEEP_WEEKLY}" --keep-monthly "${KEEP_MONTHLY}"
    ;;
  restore-db)
    ensure_repo
    exec restic dump --host "${HOSTTAG}" --tag db latest mattermost-db.sql
    ;;
  restore-files)
    ensure_repo
    target="${2:?usage: restore-files <target-dir>}"
    exec restic restore --host "${HOSTTAG}" --tag files latest --target "${target}"
    ;;
  *)
    exec restic "$@"
    ;;
esac
