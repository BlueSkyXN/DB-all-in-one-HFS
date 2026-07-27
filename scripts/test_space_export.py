#!/usr/bin/env python3
"""Dynamic checks for the clean-commit Space wrapper exporter."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class SpaceExportTests(unittest.TestCase):
    def clone_repo(self, temporary: Path) -> Path:
        clone = temporary / "repo"
        subprocess.run(["git", "clone", "--quiet", "--local", str(REPO_ROOT), str(clone)], check=True)
        return clone

    def export(self, repo: Path, output: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", "scripts/export-space-bundle.sh", str(output)],
            cwd=repo,
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_dirty_export_is_rejected(self, repo: Path, output: Path, kind: str) -> None:
        result = self.export(repo, output)
        self.assertNotEqual(result.returncode, 0, kind)
        self.assertIn("dirty Git working tree", result.stderr, kind)

    def test_clean_commit_export_binds_actual_head(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            repo = self.clone_repo(temporary_path)
            result = self.export(repo, temporary_path / "bundle")
            self.assertEqual(result.returncode, 0, result.stderr)
            expected_head = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=repo, text=True
            ).strip()
            provenance = json.loads((temporary_path / "bundle" / "BUILD_SOURCE.json").read_text())
            self.assertEqual(provenance["wrapper_source_ref"], expected_head)

    def test_export_rejects_tracked_staged_and_untracked_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            repo = self.clone_repo(temporary_path)
            readme = repo / "README.md"

            readme.write_text(readme.read_text(encoding="utf-8") + "\n", encoding="utf-8")
            self.assert_dirty_export_is_rejected(repo, temporary_path / "tracked", "tracked")

            subprocess.run(["git", "add", "README.md"], cwd=repo, check=True)
            self.assert_dirty_export_is_rejected(repo, temporary_path / "staged", "staged")

            subprocess.run(["git", "reset", "--hard", "HEAD"], cwd=repo, check=True, capture_output=True)
            (repo / "untracked-sentinel").write_text("not part of a release\n", encoding="utf-8")
            self.assert_dirty_export_is_rejected(repo, temporary_path / "untracked", "untracked")
