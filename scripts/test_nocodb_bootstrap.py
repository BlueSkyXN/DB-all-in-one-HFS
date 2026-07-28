#!/usr/bin/env python3
"""Offline contract tests for the manifest-first NocoDB bootstrap."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "docker" / "nocodb_bootstrap.py"
spec = importlib.util.spec_from_file_location("nocodb_bootstrap", MODULE_PATH)
assert spec and spec.loader
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)

SOURCE_REF = "nocodb/nocodb:2026.07.0@sha256:" + "a" * 64
WRAPPER_REF = "b" * 40


class NocoDBBootstrapContractTest(unittest.TestCase):
    def manifest(self, artifact: dict[str, object]) -> dict[str, object]:
        return {
            "schema_version": 1,
            "project": "db-all-in-one-hfs",
            "slot": "release",
            "source_kind": "oci-image",
            "source_ref": SOURCE_REF,
            "wrapper_source_ref": WRAPPER_REF,
            "generated_at": "2026-07-26T00:00:00Z",
            "artifact": artifact,
        }

    def write_manifest(self, directory: Path, manifest: dict[str, object]) -> Path:
        path = directory / "manifest.json"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        return path

    def test_private_download_keeps_bearer_token_out_of_argv(self) -> None:
        token = "hf_" + "a" * 32
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "manifest.json"
            with mock.patch.dict(os.environ, {"NOCODB_ARTIFACT_DOWNLOAD_TOKEN": token}), mock.patch.object(
                bootstrap.subprocess, "run"
            ) as run:
                bootstrap.download("https://huggingface.co/buckets/example/manifest.json", destination)
        command = run.call_args.args[0]
        self.assertNotIn(token, " ".join(command))
        self.assertEqual(command[command.index("--config") + 1], "-")
        self.assertEqual(
            run.call_args.kwargs["input"],
            f'header = "Authorization: Bearer {token}"\n',
        )
        self.assertTrue(run.call_args.kwargs["text"])

    def test_manifest_rejects_wrong_source_or_unsafe_url(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            artifact_name = f"nocodb-runtime-2026.07.0-{WRAPPER_REF}.tar.gz"
            artifact = {
                "name": artifact_name,
                "sha256": "c" * 64,
                "size_bytes": 1,
                "url": f"https://example.invalid/{artifact_name}",
            }
            manifest = self.manifest(artifact)
            path = self.write_manifest(directory, manifest)
            self.assertEqual(
                bootstrap.load_manifest(
                    path,
                    slot="release",
                    source_ref=SOURCE_REF,
                    wrapper_source_ref=WRAPPER_REF,
                )["artifact"],
                artifact,
            )

            manifest["source_ref"] = "nocodb/nocodb:latest"
            path = self.write_manifest(directory, manifest)
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.load_manifest(
                    path,
                    slot="release",
                    source_ref=SOURCE_REF,
                    wrapper_source_ref=WRAPPER_REF,
                )

            manifest = self.manifest({**artifact, "url": f"http://example.invalid/{artifact_name}"})
            path = self.write_manifest(directory, manifest)
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.load_manifest(
                    path,
                    slot="release",
                    source_ref=SOURCE_REF,
                    wrapper_source_ref=WRAPPER_REF,
                )

            manifest = self.manifest(
                {**artifact, "url": f"https://example.invalid/{artifact_name}?token=not-allowed"}
            )
            path = self.write_manifest(directory, manifest)
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.load_manifest(
                    path,
                    slot="release",
                    source_ref=SOURCE_REF,
                    wrapper_source_ref=WRAPPER_REF,
                )

            manifest = self.manifest(artifact)
            path = self.write_manifest(directory, manifest)
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.load_manifest(
                    path,
                    slot="release",
                    source_ref=SOURCE_REF,
                    wrapper_source_ref="d" * 40,
                )

            manifest = self.manifest(
                {
                    **artifact,
                    "name": "nocodb-runtime-unversioned.tar.gz",
                    "url": "https://example.invalid/nocodb-runtime-unversioned.tar.gz",
                }
            )
            path = self.write_manifest(directory, manifest)
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.load_manifest(
                    path,
                    slot="release",
                    source_ref=SOURCE_REF,
                    wrapper_source_ref=WRAPPER_REF,
                )

    def test_archive_requires_safe_rootfs_layout(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            archive = directory / "runtime.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                payload = b"unexpected"
                member = tarfile.TarInfo("outside.txt")
                member.size = len(payload)
                tar.addfile(member, io.BytesIO(payload))
            staging = directory / "staging"
            staging.mkdir()
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.extract_artifact(archive, staging)

            directory_archive = directory / "directory-layout.tar.gz"
            with tarfile.open(directory_archive, "w:gz") as tar:
                for name in (
                    "rootfs/lib/ld-musl-x86_64.so.1",
                    "rootfs/usr/local/bin/node",
                    "rootfs/usr/src/app/docker/index.js",
                ):
                    member = tarfile.TarInfo(name)
                    member.type = tarfile.DIRTYPE
                    tar.addfile(member)
            staging = directory / "directory-staging"
            staging.mkdir()
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.extract_artifact(directory_archive, staging)

    def test_archive_extracts_and_installs_verified_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            architecture = os.uname().machine
            musl_arch = {"x86_64": "x86_64", "aarch64": "aarch64", "arm64": "aarch64"}.get(architecture)
            if musl_arch is None:
                self.skipTest(f"unsupported test architecture: {architecture}")

            source = directory / "source"
            node = source / "rootfs" / "usr" / "local" / "bin" / "node"
            index = source / "rootfs" / "usr" / "src" / "app" / "docker" / "index.js"
            loader = source / "rootfs" / "lib" / f"ld-musl-{musl_arch}.so.1"
            for path, text in ((node, "node"), (index, "index"), (loader, "loader")):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            node.chmod(0o755)

            archive = directory / "nocodb-runtime-v1.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                tar.add(source / "rootfs", arcname="rootfs")
            staging = directory / "staging"
            staging.mkdir()
            rootfs = bootstrap.extract_artifact(archive, staging)
            manifest = self.manifest(
                {
                    "name": archive.name,
                    "sha256": "d" * 64,
                    "size_bytes": archive.stat().st_size,
                    "url": f"https://example.invalid/{archive.name}",
                }
            )
            runtime = directory / "runtime"
            bootstrap.install(rootfs, runtime, manifest)
            self.assertTrue((runtime / "rootfs" / "usr" / "src" / "app" / "docker" / "index.js").is_file())
            provenance = json.loads((runtime / "provenance.json").read_text(encoding="utf-8"))
            self.assertEqual(provenance["wrapper_source_ref"], WRAPPER_REF)
            self.assertEqual(provenance["artifact"]["name"], archive.name)


if __name__ == "__main__":
    unittest.main()
