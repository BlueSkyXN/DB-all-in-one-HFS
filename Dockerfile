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
ARG NODE_VERSION=20

FROM ubuntu:${UBUNTU_VERSION}

ARG MYSQL_VERSION
ARG NODE_VERSION
ARG TARGETARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive
ENV MYSQL_VERSION=${MYSQL_VERSION}
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
    curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 \
        | gpg --dearmor -o /usr/share/keyrings/mysql.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/mysql.gpg] http://repo.mysql.com/apt/ubuntu/ $(lsb_release -cs) mysql-${MYSQL_VERSION}-lts" \
        > /etc/apt/sources.list.d/mysql.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        mysql-server \
        mysql-client; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

# ─── Node.js (for NocoDB) ────────────────────────────────────────────────────
RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/nodesource.gpg; \
    gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg /tmp/nodesource.gpg; \
    rm -f /tmp/nodesource.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends nodejs; \
    rm -rf /var/lib/apt/lists/*; \
    node --version && npm --version

# ─── NocoDB ──────────────────────────────────────────────────────────────────
RUN npm install -g nocodb

# ─── Non-root runtime user (UID 1000 for HF Spaces) ─────────────────────────
RUN groupadd --gid 1000 user \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash user

ENV HOME=/home/user

# ─── Runtime directories ─────────────────────────────────────────────────────
RUN mkdir -p \
      /data/mysql /data/nocodb /data/redis /data/config /data/logs \
      /data/run/mysqld /data/run/nginx/client_body /data/run/nginx/proxy \
      /data/run/nginx/fastcgi /data/run/nginx/uwsgi /data/run/nginx/scgi \
    && chown -R user:user /data \
    && chown -R mysql:mysql /data/mysql /data/run/mysqld \
    && chmod -R 777 /data \
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

USER user
WORKDIR /home/user

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD /usr/local/bin/db-aio-healthcheck

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/db-aio-entrypoint"]
