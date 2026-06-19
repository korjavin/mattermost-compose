# Backup sidecar: postgres-client (matching the DB major version) + restic.
# Basing on postgres:16-alpine guarantees pg_dump matches the server version.
FROM postgres:16-alpine

# Pin restic via release binary (independent of distro repos). Bump as needed.
ARG RESTIC_VERSION=0.17.3
ARG TARGETARCH=amd64

RUN set -eux; \
    apk add --no-cache ca-certificates bzip2 tzdata wget; \
    wget -O /tmp/restic.bz2 \
      "https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_${TARGETARCH}.bz2"; \
    bunzip2 /tmp/restic.bz2; \
    install -m 0755 /tmp/restic /usr/local/bin/restic; \
    rm -f /tmp/restic; \
    restic version

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

ENTRYPOINT ["/usr/local/bin/backup.sh"]
CMD ["backup"]
