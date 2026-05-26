# syntax=docker/dockerfile:1.7
#
# DB-all-in-one-HFS: MySQL 9.7 LTS + NocoDB single-container image
# Target: Hugging Face Docker Space demo / PoC, not production.
# Runtime is rootless (UID 1000) to match HF Spaces expectations.
#
# Build example:
#   docker build -t db-all-in-one-hfs .
#
# Run example:
#   docker run --rm -it \
#     -p 7860:7860 \
#     -v db-hfs-persist:/data \
#     db-all-in-one-hfs

ARG UBUNTU_VERSION=24.04
ARG MYSQL_VERSION=9.7
ARG NOCODB_RELEASE=2026.05.1

FROM ubuntu:${UBUNTU_VERSION}

ARG MYSQL_VERSION
ARG NOCODB_RELEASE
ARG TARGETARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive
ENV MYSQL_VERSION=${MYSQL_VERSION}
ENV NOCODB_RELEASE=${NOCODB_RELEASE}
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# ─── System packages + Nginx + Supervisor + Redis ─────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        openssl \
        tini \
        procps \
        netcat-openbsd \
        nginx \
        supervisor \
        redis-server \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# ─── MySQL 9.7 LTS from Oracle APT repo ──────────────────────────────────────
RUN set -eux; \
    curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2025 \
        | gpg --dearmor -o /usr/share/keyrings/mysql.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/mysql.gpg] http://repo.mysql.com/apt/ubuntu/ $(lsb_release -cs) mysql-${MYSQL_VERSION}-lts" \
        > /etc/apt/sources.list.d/mysql.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        mysql-server \
        mysql-client; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

# ─── NocoDB ──────────────────────────────────────────────────────────────────
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) noco_arch="linux-x64" ;; \
      arm64) noco_arch="linux-arm64" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/nocodb/nocodb/releases/download/${NOCODB_RELEASE}/Noco-${noco_arch}" \
      -o /usr/local/bin/nocodb; \
    chmod +x /usr/local/bin/nocodb

# ─── Non-root runtime user (UID 1000 for HF Spaces) ─────────────────────────
RUN set -eux; \
    if ! getent group 1000 >/dev/null; then \
      groupadd --gid 1000 user; \
    fi; \
    if ! getent passwd 1000 >/dev/null; then \
      useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash user; \
    fi; \
    mkdir -p /home/user; \
    chown -R 1000:1000 /home/user

ENV HOME=/home/user

# ─── Runtime directories ─────────────────────────────────────────────────────
RUN mkdir -p \
      /data/mysql /data/nocodb /data/redis /data/config /data/logs \
      /data/run/mysqld /data/run/nginx/client_body /data/run/nginx/proxy \
      /data/run/nginx/fastcgi /data/run/nginx/uwsgi /data/run/nginx/scgi \
    && chown -R 1000:1000 /data \
    && chmod -R 755 /data \
    && rm -f /etc/nginx/sites-enabled/default

# ─── Copy runtime configs and scripts ────────────────────────────────────────
COPY docker/my.cnf /etc/mysql/conf.d/hfs.cnf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/entrypoint.sh /usr/local/bin/db-aio-entrypoint
COPY docker/healthcheck.sh /usr/local/bin/db-aio-healthcheck
COPY docker/ops_service.py /usr/local/bin/db-ops-service

RUN chmod +x \
      /usr/local/bin/db-aio-entrypoint \
      /usr/local/bin/db-aio-healthcheck \
      /usr/local/bin/db-ops-service

USER 1000
WORKDIR /home/user

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD /usr/local/bin/db-aio-healthcheck

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/db-aio-entrypoint"]
