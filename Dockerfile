# syntax=docker/dockerfile:1.6

ARG UBUNTU_VERSION=24.04
ARG MYSQL_VERSION=9.7
ARG NODE_VERSION=20
ARG NOCODB_VERSION=latest

FROM ubuntu:${UBUNTU_VERSION}

ARG MYSQL_VERSION
ARG NODE_VERSION
ARG NOCODB_VERSION
ARG TARGETARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive
ENV MYSQL_VERSION=${MYSQL_VERSION}
ENV NOCODB_VERSION=${NOCODB_VERSION}

# ─── System deps ──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        tini \
    && rm -rf /var/lib/apt/lists/*

# ─── MySQL 9.7 LTS ───────────────────────────────────────────────────────────
RUN set -eux; \
    curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 | gpg --dearmor -o /usr/share/keyrings/mysql.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/mysql.gpg] http://repo.mysql.com/apt/ubuntu/ $(lsb_release -cs) mysql-${MYSQL_VERSION}-lts" \
        > /etc/apt/sources.list.d/mysql.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        mysql-server \
        mysql-client; \
    rm -rf /var/lib/apt/lists/*; \
    mysqld --initialize-insecure --user=mysql; \
    mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

# ─── Node.js (for NocoDB) ────────────────────────────────────────────────────
RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -; \
    apt-get install -y --no-install-recommends nodejs; \
    rm -rf /var/lib/apt/lists/*; \
    node --version && npm --version

# ─── NocoDB ──────────────────────────────────────────────────────────────────
RUN npm install -g nocodb

# ─── Data & runtime dirs ─────────────────────────────────────────────────────
RUN mkdir -p /data/mysql /data/nocodb /var/run/mysqld \
    && chown -R mysql:mysql /data/mysql /var/run/mysqld

# ─── Scripts ─────────────────────────────────────────────────────────────────
COPY --chmod=0755 start.sh /start.sh
COPY --chmod=0644 my.cnf /etc/mysql/conf.d/hfs.cnf

ENV MYSQL_ROOT_PASSWORD=nocodb_root_pwd
ENV MYSQL_DATABASE=nocodb
ENV MYSQL_USER=nocodb
ENV MYSQL_PASSWORD=nocodb_pwd
ENV NC_AUTH_JWT_SECRET=change_me_to_a_random_string
ENV NC_PORT=7860
ENV NC_DB_JSON_FILE=""
ENV NC_PUBLIC_URL=""
ENV NC_DISABLE_TELE=true

EXPOSE 7860

VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS http://127.0.0.1:7860/api/v1/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/start.sh"]
