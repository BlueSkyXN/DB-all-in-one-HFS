# docker/ navigation card

`docker/` owns container runtime: entrypoint, Supervisor, Nginx, MySQL, Redis, ops-service, healthcheck, and `/data`.
Read before editing `entrypoint.sh`, `nocodb.sh`, `supervisord.conf`, `nginx.conf`, `ops_service.py`, `healthcheck.sh`, or `my.cnf`.
This card is the runtime guardrail; root `AGENTS.md` has repo-wide rules.

## Invariants

- Public entry: only Nginx `7860`; internal: NocoDB `8080`, ops-service `8081`, MySQL/Redis on `127.0.0.1`.
- `DATA_DIR=/data`; MySQL socket `/data/run/mysqld/mysqld.sock`.
- Never expose `/data/config/generated.env`, `/data/config/supervisor.env`, secrets, or full `/data/run`.
- `/_ops` stays read-only; `/config` safe keys only; logs redacted; `ops_service.py` stdlib only.
- Locale init: `NC_DEFAULT_LOCALE` -> exact `/__db_aio/nocodb-locale-init.js` -> `sub_filter`.
- `/signup` and `/signup/` exact redirect only; no wildcard `/signup/<token>`.
- NocoDB runtime stays under `/opt/nocodb-runtime`; `nocodb.sh` starts the pinned official OCI image's musl Node runtime.

## Before changes

- Port/route: check `nginx.conf`, `supervisord.conf`, `entrypoint.sh`, `healthcheck.sh`, root `Dockerfile`, `README.md`, `hfs-dev.toml`, `scripts/smoke.sh`.
- Env var: check `entrypoint.sh`, `supervisord.conf`, `ops_service.py`, `docs/configuration.md`, deployment/runbook docs.
- Nginx HTML/locale: keep proxy headers, `Accept-Encoding ""`, exact alias; verify `ngx_http_sub_module`.
- Service/log: update Supervisor, healthcheck, `SERVICE_LOGS`, Nginx, docs.
- MySQL: preserve root auth reuse, socket, bind address, log paths.
- NocoDB image: update `NOCODB_IMAGE_REF` tag and digest together; do not restore standalone executable downloads.

## Do not

- Do not bind internal services publicly, serve `/data/config`, add write ops endpoints, or add Python deps.

## Validation

- `bash -n docker/entrypoint.sh docker/healthcheck.sh docker/nocodb.sh`
- `python3 -m py_compile docker/ops_service.py`
- `scripts/static-check.sh`
- Docker-only: `scripts/build.sh`, Nginx `-V` / `-t`, `scripts/run-demo.sh`, `scripts/smoke.sh http://localhost:7860`.
