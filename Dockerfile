# syntax=docker/dockerfile:1.7
#
# DB-all-in-one-HFS: MySQL 9.7 LTS + NocoDB single-container image
# Target: Hugging Face Docker Space demo / PoC, not production.
# Runtime is rootless (UID 1000) to match HF Spaces expectations.
#
# NocoDB is a manifest-selected runtime artifact. The image deliberately
# contains only operating-system infrastructure and the fail-closed bootstrap.

ARG UBUNTU_VERSION=24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90
ARG MYSQL_VERSION=9.7
ARG MYSQL_SERVER_PACKAGE=mysql-server=9.7.1-1ubuntu24.04
ARG MYSQL_CLIENT_PACKAGE=mysql-client=9.7.1-1ubuntu24.04
ARG NOCODB_SOURCE_REF=nocodb/nocodb:2026.07.0@sha256:fb359673c42fb69058e880710e446f8039afeb64632ca8d8dfcfdcc407ebb058
# scripts/build.sh supplies and export-space-bundle.sh embeds a full Git SHA here.
ARG WRAPPER_SOURCE_REF=unknown

FROM ubuntu:${UBUNTU_VERSION}

ARG UBUNTU_VERSION
ARG MYSQL_VERSION
ARG MYSQL_SERVER_PACKAGE
ARG MYSQL_CLIENT_PACKAGE
ARG NOCODB_SOURCE_REF
ARG WRAPPER_SOURCE_REF

ENV DEBIAN_FRONTEND=noninteractive
ENV UBUNTU_VERSION=${UBUNTU_VERSION}
ENV MYSQL_VERSION=${MYSQL_VERSION}
ENV MYSQL_SERVER_PACKAGE=${MYSQL_SERVER_PACKAGE}
ENV MYSQL_CLIENT_PACKAGE=${MYSQL_CLIENT_PACKAGE}
ENV NOCODB_SOURCE_REF=${NOCODB_SOURCE_REF}
ENV WRAPPER_SOURCE_REF=${WRAPPER_SOURCE_REF}
ENV NODE_ENV=production
ENV NC_DOCKER=0.6
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# System packages + Nginx + Supervisor + Redis.
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

# MySQL 9.7 LTS from Oracle APT repo.
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

# The bootstrapped NocoDB rootfs has a musl Node interpreter. Point its dynamic
# loader at the fixed, container-local runtime location; the entrypoint creates
# that location only after manifest/hash/layout verification succeeds.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) musl_arch="x86_64" ;; \
      arm64) musl_arch="aarch64" ;; \
      *) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    ln -s "/home/user/run/nocodb-runtime/rootfs/lib/ld-musl-${musl_arch}.so.1" "/lib/ld-musl-${musl_arch}.so.1"; \
    printf '%s\n' \
      /home/user/run/nocodb-runtime/rootfs/lib \
      /home/user/run/nocodb-runtime/rootfs/usr/lib \
      > "/etc/ld-musl-${musl_arch}.path"; \
    mkdir -p /usr/local/share/db-aio-hfs; \
    printf '%s\n' "${NOCODB_SOURCE_REF}" \
      > /usr/local/share/db-aio-hfs/nocodb-source-ref; \
    printf '%s\n' "${WRAPPER_SOURCE_REF}" | grep -Eq '^[0-9a-f]{40}$'; \
    printf '%s\n' "${WRAPPER_SOURCE_REF}" \
      > /usr/local/share/db-aio-hfs/wrapper-source-ref

# Non-root runtime user (UID 1000 for HF Spaces).
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

# /data holds persistent plain-file state (volume-safe: app data, config, logs,
# logical backups). /home/user holds state object-storage volumes cannot host:
# MySQL/Redis live data, socket/PID files, and the downloaded runtime artifact.
RUN mkdir -p \
      /data/nocodb /data/config /data/logs /data/backups \
      /home/user/mysql /home/user/redis \
      /home/user/run/mysqld /home/user/run/db-aio-public \
      /home/user/run/nginx/client_body /home/user/run/nginx/proxy \
      /home/user/run/nginx/fastcgi /home/user/run/nginx/uwsgi \
      /home/user/run/nginx/scgi /home/user/run/nocodb-runtime \
    && chown -R 1000:1000 /data \
    && chmod -R 755 /data \
    && chown -R 1000:1000 /home/user \
    && rm -f /etc/nginx/sites-enabled/default

# Copy only the wrapper runtime contract; the NocoDB product rootfs is never in
# the image build context and is fetched once at startup from the manifest.
COPY docker/my.cnf /etc/mysql/conf.d/hfs.cnf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/entrypoint.sh /usr/local/bin/db-aio-entrypoint
COPY docker/healthcheck.sh /usr/local/bin/db-aio-healthcheck
COPY docker/nocodb.sh /usr/local/bin/db-aio-nocodb
COPY docker/nocodb_bootstrap.py /usr/local/bin/db-aio-nocodb-bootstrap
COPY docker/mysql-backup.sh /usr/local/bin/db-aio-mysql-backup
COPY docker/ops_service.py /usr/local/bin/db-ops-service

RUN chmod +x \
      /usr/local/bin/db-aio-entrypoint \
      /usr/local/bin/db-aio-healthcheck \
      /usr/local/bin/db-aio-nocodb \
      /usr/local/bin/db-aio-nocodb-bootstrap \
      /usr/local/bin/db-aio-mysql-backup \
      /usr/local/bin/db-ops-service

USER 1000
WORKDIR /home/user

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD /usr/local/bin/db-aio-healthcheck

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/db-aio-entrypoint"]
