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

ARG UBUNTU_VERSION=24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90
ARG MYSQL_VERSION=9.7
ARG MYSQL_SERVER_PACKAGE=mysql-server=9.7.1-1ubuntu24.04
ARG MYSQL_CLIENT_PACKAGE=mysql-client=9.7.1-1ubuntu24.04
ARG NOCODB_IMAGE_REF=nocodb/nocodb:2026.07.0@sha256:fb359673c42fb69058e880710e446f8039afeb64632ca8d8dfcfdcc407ebb058

FROM ${NOCODB_IMAGE_REF} AS nocodb-runtime
FROM ubuntu:${UBUNTU_VERSION}

ARG UBUNTU_VERSION
ARG MYSQL_VERSION
ARG MYSQL_SERVER_PACKAGE
ARG MYSQL_CLIENT_PACKAGE
ARG NOCODB_IMAGE_REF

ENV DEBIAN_FRONTEND=noninteractive
ENV UBUNTU_VERSION=${UBUNTU_VERSION}
ENV MYSQL_VERSION=${MYSQL_VERSION}
ENV MYSQL_SERVER_PACKAGE=${MYSQL_SERVER_PACKAGE}
ENV MYSQL_CLIENT_PACKAGE=${MYSQL_CLIENT_PACKAGE}
ENV NODE_ENV=production
ENV NC_DOCKER=0.6
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
        "${MYSQL_SERVER_PACKAGE}" \
        "${MYSQL_CLIENT_PACKAGE}"; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

# ─── NocoDB official OCI runtime ─────────────────────────────────────────────
# NocoDB stopped publishing standalone executables after 2026.06.1. Keep the
# upstream image rootfs intact under /opt and run its musl-linked Node runtime
# from the Ubuntu/MySQL container instead of rebuilding upstream node_modules.
COPY --from=nocodb-runtime / /opt/nocodb-runtime

RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) musl_arch="x86_64" ;; \
      arm64) musl_arch="aarch64" ;; \
      *) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    musl_loader="ld-musl-${musl_arch}.so.1"; \
    test -x "/opt/nocodb-runtime/lib/${musl_loader}"; \
    test -x /opt/nocodb-runtime/usr/local/bin/node; \
    test -r /opt/nocodb-runtime/usr/src/app/docker/index.js; \
    ln -s "/opt/nocodb-runtime/lib/${musl_loader}" "/lib/${musl_loader}"; \
    printf '%s\n' \
      /opt/nocodb-runtime/lib \
      /opt/nocodb-runtime/usr/lib \
      > "/etc/ld-musl-${musl_arch}.path"; \
    mkdir -p /usr/src; \
    ln -s /opt/nocodb-runtime/usr/src/app /usr/src/app; \
    ln -s /opt/nocodb-runtime/usr/src/appEntry /usr/src/appEntry; \
    ln -s /opt/nocodb-runtime/usr/local/bin/node /usr/local/bin/node; \
    ln -s /opt/nocodb-runtime/usr/local/bin/node /usr/local/bin/nodejs; \
    mkdir -p /usr/local/share/db-aio-hfs; \
    printf '%s\n' "${NOCODB_IMAGE_REF}" \
      > /usr/local/share/db-aio-hfs/nocodb-image-ref

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
COPY docker/nocodb.sh /usr/local/bin/db-aio-nocodb
COPY docker/ops_service.py /usr/local/bin/db-ops-service

RUN chmod +x \
      /usr/local/bin/db-aio-entrypoint \
      /usr/local/bin/db-aio-healthcheck \
      /usr/local/bin/db-aio-nocodb \
      /usr/local/bin/db-ops-service

USER 1000
WORKDIR /home/user

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD /usr/local/bin/db-aio-healthcheck

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/db-aio-entrypoint"]
