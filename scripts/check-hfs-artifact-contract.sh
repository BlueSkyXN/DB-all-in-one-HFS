#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${repo_root}"

python3 - <<'PY'
from pathlib import Path
import re
import tomllib

manifest = tomllib.loads(Path("hfs-dev.toml").read_text(encoding="utf-8"))
expected = {
    "standard": "2.0",
    "project": "db-all-in-one-hfs",
    "space": "BlueSkyXN/db-all-in-one-hfs",
    "sovereignty": "port",
    "lane": "artifact",
    "version_source": "tag",
    "dist_bucket": "hfs-dist",
}
for key, value in expected.items():
    if manifest.get(key) != value:
        raise SystemExit(f"hfs-dev.toml: {key} must be {value!r}")
candidate = tomllib.loads(Path("hfs-dev.candidate.toml").read_text(encoding="utf-8"))
if candidate.get("space") != "BlueSkyXN/db-all-in-one-hfs-v2-candidate":
    raise SystemExit("candidate manifest has the wrong fixed Space id")
for key in sorted(set(manifest) | set(candidate)):
    if key != "space" and manifest.get(key) != candidate.get(key):
        raise SystemExit(f"candidate manifest differs from production at {key}")
if "NOCODB_ARTIFACT_MANIFEST_URL" not in manifest.get("variables", []):
    raise SystemExit("hfs-dev.toml must register NOCODB_ARTIFACT_MANIFEST_URL")
if "NOCODB_ARTIFACT_DOWNLOAD_TOKEN" not in manifest.get("secrets", []):
    raise SystemExit("hfs-dev.toml must register NOCODB_ARTIFACT_DOWNLOAD_TOKEN")
if set(manifest.get("local_only", [])) != {"HF_TOKEN", "GH_TOKEN"}:
    raise SystemExit("hfs-dev.toml local_only must contain only deployment control keys")

dockerfile = Path("Dockerfile").read_text(encoding="utf-8")
source_ref = re.search(r"^ARG NOCODB_SOURCE_REF=(.+)$", dockerfile, re.MULTILINE)
if source_ref is None or "@sha256:" not in source_ref.group(1) or ":" not in source_ref.group(1):
    raise SystemExit("Dockerfile must pin NOCODB_SOURCE_REF with both tag and digest")
if dockerfile.count("ARG WRAPPER_SOURCE_REF=unknown") != 1:
    raise SystemExit("Dockerfile must require one exportable wrapper Git SHA build marker")
if "wrapper-source-ref" not in dockerfile or "^[0-9a-f]{40}$" not in dockerfile:
    raise SystemExit("Dockerfile must validate and persist the wrapper Git SHA")
if re.search(r"^FROM\s+.*nocodb", dockerfile, re.MULTILINE | re.IGNORECASE):
    raise SystemExit("Dockerfile must not use the NocoDB business OCI image as a build stage")
if "COPY --from=" in dockerfile:
    raise SystemExit("Dockerfile must not copy a business runtime from another image")

entrypoint = Path("docker/entrypoint.sh").read_text(encoding="utf-8")
main_body = entrypoint.split("main() {", 1)[1]
if main_body.index("bootstrap_nocodb_runtime") > main_body.index("init_mysql"):
    raise SystemExit("artifact bootstrap must run before MySQL initialization")
for required in (
    "NOCODB_ARTIFACT_MANIFEST_URL is required",
    "NOCODB_ARTIFACT_DOWNLOAD_TOKEN is required",
    "NOCODB_ARTIFACT_SLOT must be edge or release",
    "--source-ref \"${NOCODB_SOURCE_REF}\"",
    "--wrapper-source-ref \"${NOCODB_WRAPPER_SOURCE_REF}\"",
):
    if required not in entrypoint:
        raise SystemExit(f"entrypoint missing fail-closed artifact contract: {required}")

backup = Path("docker/mysql-backup.sh").read_text(encoding="utf-8")
restore = entrypoint
for required in ("BACKUP_DIR", "gzip -t", "nocodb-*.sql.gz"):
    if required not in backup + restore:
        raise SystemExit(f"backup/restore contract missing: {required}")
if 'MYSQL_DATA_DIR="${HOME}/mysql"' not in entrypoint:
    raise SystemExit("MySQL datadir must remain container-local")
if 'REDIS_DATA_DIR="${HOME}/redis"' not in entrypoint:
    raise SystemExit("Redis datadir must remain container-local")

exporter = Path("scripts/export-space-bundle.sh").read_text(encoding="utf-8")
for required in (
    "status --porcelain",
    "ARG WRAPPER_SOURCE_REF={source_ref}",
    "wrapper_source_ref",
):
    if required not in exporter:
        raise SystemExit(f"wrapper exporter missing immutable source binding: {required}")

publisher = Path(".github/workflows/publish-nocodb-artifact.yml").read_text(encoding="utf-8")
for required in (
    "workflow_dispatch",
    "PUBLISH_NOCODB_ARTIFACT",
    "python -m huggingface_hub.cli.hf buckets cp",
    "gh release download",
    "sha256sum -c -",
    "huggingface_hub==1.5.0",
    "click==8.3.1",
    "python -m huggingface_hub.cli.hf --help",
    "python -m huggingface_hub.cli.hf buckets --help",
):
    if required not in publisher:
        raise SystemExit(f"artifact publisher missing required contract gate: {required}")
for forbidden in ("--clobber", "--force", "git push", "hf upload --delete"):
    if forbidden in publisher:
        raise SystemExit(f"artifact publisher contains forbidden remote mutation: {forbidden}")

deployer = Path(".github/workflows/deploy-hf-space.yml").read_text(encoding="utf-8")
for required in (
    "workflow_dispatch", "DEPLOY_DB_AIO_HFS",
    "python -m huggingface_hub.cli.hf upload", "cmp ",
    "hfs-dev.candidate.toml", "candidate Space must be private",
    "refusing non-wrapper Space tree", "full Space tree readback",
    "huggingface_hub==1.5.0",
    "click==8.3.1",
    "python -m huggingface_hub.cli.hf --help",
    "python -m huggingface_hub.cli.hf download --help",
):
    if required not in deployer:
        raise SystemExit(f"wrapper deployer missing required contract gate: {required}")
for forbidden in ("--force", "git push", "--delete", "restart_space", "factory_reboot"):
    if forbidden in deployer:
        raise SystemExit(f"wrapper deployer contains forbidden remote mutation: {forbidden}")

for workflow_path in (
    ".github/workflows/deploy-hf-space.yml",
    ".github/workflows/publish-nocodb-artifact.yml",
):
    workflow = Path(workflow_path).read_text(encoding="utf-8")
    if re.search(r"(?m)^\s+hf (?:upload|download|spaces|buckets|repos)\b", workflow):
        raise SystemExit(f"{workflow_path} must use the Hugging Face module CLI")

for ignore_path in (".gitignore", ".dockerignore"):
    ignored = Path(ignore_path).read_text(encoding="utf-8")
    for required in (".env", "local/", ".cache/", "*.sql.gz", "*.tar.gz"):
        if required not in ignored:
            raise SystemExit(f"{ignore_path} missing boundary rule: {required}")
PY

PYTHONDONTWRITEBYTECODE=1 python3 scripts/test_nocodb_bootstrap.py
printf 'HFS artifact contract checks passed.\n'
