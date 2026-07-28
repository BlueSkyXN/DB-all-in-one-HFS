#!/usr/bin/env python3
"""Fetch and install the one NocoDB runtime selected by an artifact manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlparse

PROJECT = "db-all-in-one-hfs"
MANIFEST_SCHEMA_VERSION = 1
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ARTIFACT_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*\.tar\.gz$")
GIT_SHA = re.compile(r"^[0-9a-f]{40}$")
DOWNLOAD_TOKEN = re.compile(r"^[A-Za-z0-9._-]{20,}$")


class BootstrapError(RuntimeError):
    """A validation or installation failure that must stop startup."""


def fail(message: str) -> None:
    raise BootstrapError(message)


def require_https_url(value: object, field: str) -> str:
    if not isinstance(value, str) or not value:
        fail(f"manifest {field} must be a non-empty HTTPS URL")
    parsed = urlparse(value)
    if (
        parsed.scheme != "https"
        or not parsed.netloc
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
    ):
        fail(f"manifest {field} must be a credential-free HTTPS URL without query or fragment")
    return value


def download(url: str, destination: Path) -> None:
    token = os.environ.get("NOCODB_ARTIFACT_DOWNLOAD_TOKEN", "").strip()
    if not DOWNLOAD_TOKEN.fullmatch(token):
        fail("NOCODB_ARTIFACT_DOWNLOAD_TOKEN is required and has an invalid format")
    command = [
        "curl",
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--proto",
        "=https",
        "--proto-redir",
        "=https",
        "--tlsv1.2",
        "--config",
        "-",
        "--output",
        str(destination),
        url,
    ]
    try:
        # Keep the bearer token out of argv and let curl drop the sensitive
        # header automatically when Hugging Face redirects to object storage.
        subprocess.run(
            command,
            check=True,
            input=f'header = "Authorization: Bearer {token}"\n',
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        fail(f"download failed for {url}: exit {exc.returncode}")


def load_manifest(
    path: Path, *, slot: str, source_ref: str, wrapper_source_ref: str
) -> dict[str, object]:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"invalid artifact manifest: {exc}")
    if not isinstance(manifest, dict):
        fail("artifact manifest must be a JSON object")

    if manifest.get("schema_version") != MANIFEST_SCHEMA_VERSION:
        fail("artifact manifest has an unsupported schema_version")
    if manifest.get("project") != PROJECT:
        fail("artifact manifest project does not match this wrapper")
    if manifest.get("slot") != slot:
        fail("artifact manifest slot does not match NOCODB_ARTIFACT_SLOT")
    if manifest.get("source_kind") != "oci-image":
        fail("artifact manifest source_kind must be oci-image")
    if manifest.get("source_ref") != source_ref:
        fail("artifact manifest source_ref does not match the wrapper pin")
    if not isinstance(manifest.get("wrapper_source_ref"), str) or not GIT_SHA.fullmatch(
        manifest["wrapper_source_ref"]
    ):
        fail("artifact manifest wrapper_source_ref must be a full immutable Git SHA")
    if not GIT_SHA.fullmatch(wrapper_source_ref):
        fail("wrapper image is missing a full immutable Git SHA")
    if manifest["wrapper_source_ref"] != wrapper_source_ref:
        fail("artifact manifest wrapper_source_ref does not match the wrapper image")
    if not isinstance(manifest.get("generated_at"), str) or not manifest["generated_at"]:
        fail("artifact manifest generated_at must be present")

    artifact = manifest.get("artifact")
    if not isinstance(artifact, dict):
        fail("artifact manifest artifact must be an object")
    name = artifact.get("name")
    if not isinstance(name, str) or not ARTIFACT_NAME.fullmatch(name):
        fail("artifact name must be a safe .tar.gz file name")
    source_leaf = source_ref.rsplit("/", 1)[-1].split("@", 1)[0]
    if ":" not in source_leaf:
        fail("wrapper source ref must include a release tag")
    source_tag = source_leaf.rsplit(":", 1)[1]
    expected_name = f"nocodb-runtime-{source_tag}-{wrapper_source_ref}.tar.gz"
    if name != expected_name:
        fail("artifact name must exactly bind its source tag and wrapper Git SHA")
    digest = artifact.get("sha256")
    if not isinstance(digest, str) or not SHA256.fullmatch(digest):
        fail("artifact sha256 must be a lowercase SHA-256 digest")
    url = require_https_url(artifact.get("url"), "artifact.url")
    url_name = PurePosixPath(unquote(urlparse(url).path)).name
    if url_name != name:
        fail("artifact URL file name does not match artifact.name")
    size = artifact.get("size_bytes")
    if not isinstance(size, int) or size <= 0:
        fail("artifact size_bytes must be a positive integer")
    return manifest


def verify_hash(path: Path, expected: str, expected_size: int) -> None:
    if path.stat().st_size != expected_size:
        fail("downloaded artifact size does not match manifest")
    digest = hashlib.sha256()
    with path.open("rb") as artifact:
        for block in iter(lambda: artifact.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != expected:
        fail("downloaded artifact SHA-256 does not match manifest")


def normalized_rootfs_path(path: PurePosixPath, *, member_name: str) -> tuple[str, ...]:
    """Reject archive paths and links that resolve outside rootfs."""
    if path.is_absolute():
        fail(f"artifact contains an absolute path or link: {member_name!r}")
    parts: list[str] = []
    for part in path.parts:
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                fail(f"artifact path escapes rootfs: {member_name!r}")
            parts.pop()
            continue
        parts.append(part)
    if not parts or parts[0] != "rootfs":
        fail(f"artifact path is outside rootfs: {member_name!r}")
    return tuple(parts)


def safe_member(member: tarfile.TarInfo) -> None:
    path = PurePosixPath(member.name)
    normalized_rootfs_path(path, member_name=member.name)
    if member.ischr() or member.isblk() or member.isfifo() or member.isdev():
        fail(f"artifact contains a disallowed special file: {member.name!r}")
    if member.islnk():
        # Tar hard-link names are archive-root relative, unlike symbolic links.
        normalized_rootfs_path(PurePosixPath(member.linkname), member_name=member.name)
    if member.issym():
        # Relative links with ../ are legitimate in a Linux rootfs. Resolve them
        # from the member's parent and reject only links that leave rootfs.
        target = PurePosixPath(member.linkname)
        normalized_rootfs_path(path.parent / target, member_name=member.name)


def extract_artifact(archive: Path, staging: Path) -> Path:
    try:
        with tarfile.open(archive, mode="r:gz") as tar:
            members = tar.getmembers()
            if not members:
                fail("artifact archive is empty")
            for member in members:
                safe_member(member)
            tar.extractall(staging, members=members, filter="data")
    except (OSError, tarfile.TarError) as exc:
        fail(f"artifact extraction failed: {exc}")

    rootfs = staging / "rootfs"
    architecture = os.uname().machine
    musl_arch = {"x86_64": "x86_64", "aarch64": "aarch64", "arm64": "aarch64"}.get(architecture)
    if musl_arch is None:
        fail(f"unsupported architecture: {architecture}")
    loader = rootfs / "lib" / f"ld-musl-{musl_arch}.so.1"
    node = rootfs / "usr" / "local" / "bin" / "node"
    entrypoint = rootfs / "usr" / "src" / "app" / "docker" / "index.js"
    if (
        not rootfs.is_dir()
        or not loader.is_file()
        or not node.is_file()
        or not os.access(node, os.X_OK)
        or not entrypoint.is_file()
        or not os.access(entrypoint, os.R_OK)
    ):
        fail("artifact rootfs layout is incomplete or incompatible")
    return rootfs


def install(rootfs: Path, runtime_dir: Path, manifest: dict[str, object]) -> None:
    """Install a fully verified rootfs and receipt before services can start."""
    runtime_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    provenance = {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "project": PROJECT,
        "slot": manifest["slot"],
        "source_ref": manifest["source_ref"],
        "wrapper_source_ref": manifest["wrapper_source_ref"],
        "artifact": manifest["artifact"],
        "generated_at": manifest["generated_at"],
    }
    # Prepare and fsync the receipt before replacing the previous runtime. A
    # failed receipt write leaves the prior runtime untouched; a later failure
    # is fail-closed because nocodb.sh requires this receipt before exec.
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=runtime_dir, prefix=".provenance-", delete=False
    ) as receipt:
        receipt.write(json.dumps(provenance, sort_keys=True, separators=(",", ":")) + "\n")
        receipt.flush()
        os.fsync(receipt.fileno())
        receipt_path = Path(receipt.name)

    try:
        target = runtime_dir / "rootfs"
        if target.is_symlink():
            target.unlink()
        elif target.exists():
            shutil.rmtree(target)
        # This happens before Supervisor starts any service. If replacement
        # fails, bootstrap returns non-zero and no old runtime is selected.
        os.replace(rootfs, target)
        os.replace(receipt_path, runtime_dir / "provenance.json")
    finally:
        receipt_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest-url", required=True)
    parser.add_argument("--slot", required=True, choices=("edge", "release"))
    parser.add_argument("--source-ref", required=True)
    parser.add_argument("--wrapper-source-ref", required=True)
    parser.add_argument("--runtime-dir", required=True, type=Path)
    args = parser.parse_args()

    try:
        manifest_url = require_https_url(args.manifest_url, "URL")
        with tempfile.TemporaryDirectory(prefix="nocodb-bootstrap-", dir=args.runtime_dir.parent) as temporary:
            temporary_path = Path(temporary)
            manifest_path = temporary_path / "manifest.json"
            download(manifest_url, manifest_path)
            manifest = load_manifest(
                manifest_path,
                slot=args.slot,
                source_ref=args.source_ref,
                wrapper_source_ref=args.wrapper_source_ref,
            )
            artifact = manifest["artifact"]
            assert isinstance(artifact, dict)
            archive_path = temporary_path / str(artifact["name"])
            download(str(artifact["url"]), archive_path)
            verify_hash(archive_path, str(artifact["sha256"]), int(artifact["size_bytes"]))
            staging = temporary_path / "staging"
            staging.mkdir(mode=0o700)
            rootfs = extract_artifact(archive_path, staging)
            install(rootfs, args.runtime_dir, manifest)
    except BootstrapError as exc:
        print(f"[db-aio-hfs] ERROR: NocoDB artifact bootstrap failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
