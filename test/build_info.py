#!/usr/bin/env python3
"""Isolated build metadata regressions; no Theos, device, or network needed."""

import ast
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "Scripts/build-info.sh"


class BuildInfoTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lc32-build-info-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.output = self.root / "generated/build-info.h"
        self.bundle_id = "org.liveexec32.test.shared"
        self.control_version("0.0.1")
        self.framework_plist = (
            self.root / "HostFrameworks/LC32/Resources/Info.plist"
        )
        self.framework_plist.parent.mkdir(parents=True)
        self.framework_plist.write_bytes(plistlib.dumps({
            "CFBundleIdentifier": self.bundle_id,
            "CFBundleShortVersionString": "99.0",
        }))
        # The caller's CI environment must not leak into source-archive and
        # detached-HEAD assertions. Individual tests opt into CI values.
        self.environment = mock.patch.dict(os.environ, {
            "GITHUB_HEAD_REF": "", "GITHUB_REF_NAME": "",
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def control_version(self, version):
        (self.root / "control").write_text(
            f"Package: org.liveexec32.test\nVersion: {version}\n",
            encoding="utf-8",
        )

    def git(self, *arguments):
        if not shutil.which("git"):
            self.skipTest("git is not installed")
        return subprocess.run([
            "git", "-c", "core.hooksPath=/dev/null",
            "-c", "commit.gpgsign=false", "-c", "user.name=LC32 Test",
            "-c", "user.email=lc32-test@example.invalid", "-C", str(self.root),
            *arguments,
        ], capture_output=True, text=True, check=True).stdout.strip()

    def initialize_git(self):
        self.git("init", "--quiet", "--initial-branch=main")
        self.git("add", "control", "HostFrameworks")
        self.git("commit", "--quiet", "-m", "Fixture metadata")
        return self.git("rev-parse", "--short=7", "HEAD")

    def generate(self, *, root=None, output=None, env=None, check=True):
        return subprocess.run([
            "/bin/bash", str(SCRIPT), "--root", str(root or self.root),
            "--output", str(output or self.output),
        ], capture_output=True, text=True, env=env, check=check)

    def build_info(self, **kwargs):
        self.generate(**kwargs)
        output = kwargs.get("output") or self.output
        definitions = {}
        for line in output.read_text(encoding="utf-8").splitlines():
            if line.startswith("#define "):
                _, name, literal = line.split(" ", 2)
                # Three-digit octal escapes are valid in both C and Python.
                # The compiler round-trip test below also checks real C bytes.
                definitions[name] = ast.literal_eval(literal)
        return definitions

    def assert_invalid_metadata(self, message):
        result = self.generate(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)
        self.assertFalse(self.output.exists())

    def utility_path(self, *, missing=(), overrides=None):
        restricted_path = self.root / "restricted-utilities"
        restricted_path.mkdir()
        overrides = overrides or {}
        for utility in ("awk", "plutil", "git", "mkdir", "dirname", "mktemp",
                        "cmp", "mv", "rm"):
            if utility in missing:
                continue
            executable = overrides.get(utility) or shutil.which(utility)
            self.assertIsNotNone(executable, f"{utility} is required")
            (restricted_path / utility).symlink_to(executable)
        return str(restricted_path)

    def test_control_and_shared_bundle_are_canonical(self):
        info = self.build_info()
        self.assertEqual(info, {
            "CONFIG_VERSION": "0.0.1",
            "CONFIG_SHARED_FRAMEWORK_BUNDLE_ID": self.bundle_id,
            "CONFIG_COMMIT": "unknown",
            "CONFIG_BRANCH": "unknown",
        })

    def test_numeric_version_components(self):
        for version in ("1", "1.2", "1.2.3", "0.0.1", "123.45.6"):
            with self.subTest(version=version):
                self.control_version(version)
                self.assertEqual(
                    self.build_info()["CONFIG_VERSION"], version
                )

    def test_rejects_non_numeric_release_versions(self):
        for version in ("", "1.2.3.4", "1.2-beta", "1.2+nightly", "-1.2",
                        "1.2x", "release", "1.2 trailing-text"):
            with self.subTest(version=version):
                self.control_version(version)
                self.assert_invalid_metadata("numeric Version")

    def test_rejects_missing_version(self):
        (self.root / "control").write_text("Package: test\n", encoding="utf-8")
        self.assert_invalid_metadata("numeric Version")

    def test_missing_git_executable(self):
        self.initialize_git()
        environment = dict(os.environ, PATH=self.utility_path(missing=("git",)))
        self.assertIsNone(shutil.which("git", path=environment["PATH"]))
        info = self.build_info(env=environment)
        self.assertEqual(info["CONFIG_COMMIT"], "unknown")
        self.assertEqual(info["CONFIG_BRANCH"], "unknown")

    def test_source_archive_can_use_ci_branch(self):
        with mock.patch.dict(os.environ, {"GITHUB_REF_NAME": "release/archive"}):
            info = self.build_info()
        self.assertEqual(info["CONFIG_COMMIT"], "unknown")
        self.assertEqual(info["CONFIG_BRANCH"], "release/archive")

    def test_clean_git_and_local_branch_precede_ci(self):
        commit = self.initialize_git()
        with mock.patch.dict(os.environ, {
            "GITHUB_HEAD_REF": "pr-branch", "GITHUB_REF_NAME": "ci-branch",
        }):
            info = self.build_info()
        self.assertEqual(info["CONFIG_COMMIT"], commit)
        self.assertRegex(info["CONFIG_COMMIT"], r"^[0-9a-f]{7}$")
        self.assertEqual(info["CONFIG_BRANCH"], "main")

    def test_dirty_tracked_files_but_not_untracked_build_products(self):
        commit = self.initialize_git()
        (self.root / "untracked-build-output").write_text("artifact\n")
        self.assertEqual(
            self.build_info()["CONFIG_COMMIT"], commit
        )
        self.control_version("0.0.2")
        info = self.build_info()
        self.assertEqual(info["CONFIG_COMMIT"], commit + "-dirty")
        self.assertEqual(info["CONFIG_VERSION"], "0.0.2")
        self.git("add", "control")
        self.assertEqual(
            self.build_info()["CONFIG_COMMIT"], commit + "-dirty"
        )

    def test_detached_head_and_ci_fallback_order(self):
        commit = self.initialize_git()
        self.git("checkout", "--quiet", "--detach", "HEAD")
        info = self.build_info()
        self.assertEqual(info["CONFIG_COMMIT"], commit)
        self.assertEqual(info["CONFIG_BRANCH"], "detached")
        with mock.patch.dict(os.environ, {
            "GITHUB_HEAD_REF": "feature/pr", "GITHUB_REF_NAME": "17/merge",
        }):
            self.assertEqual(
                self.build_info()["CONFIG_BRANCH"], "feature/pr"
            )
        with mock.patch.dict(os.environ, {"GITHUB_REF_NAME": "nightly"}):
            self.assertEqual(
                self.build_info()["CONFIG_BRANCH"], "nightly"
            )

    def test_quoted_unicode_git_branch(self):
        self.initialize_git()
        branch = 'topic/"quoted"-tiếng-Việt'
        self.git("checkout", "--quiet", "-b", branch)
        self.assertEqual(
            self.build_info()["CONFIG_BRANCH"], branch
        )
        self.generate()
        self.assertIn(
            '#define CONFIG_BRANCH ' + json.dumps(branch, ensure_ascii=False),
            self.output.read_text(encoding="utf-8"),
        )

    def test_header_is_not_rewritten_when_unchanged(self):
        self.generate()
        original = self.output.read_bytes()
        os.utime(self.output, ns=(1_000_000_000, 2_000_000_000))
        before = self.output.stat()
        self.generate()
        after = self.output.stat()
        self.assertEqual(self.output.read_bytes(), original)
        self.assertEqual(after.st_mtime_ns, before.st_mtime_ns)
        self.assertEqual(after.st_ino, before.st_ino)

    def test_changed_metadata_replaces_header_without_temporary_files(self):
        self.generate()
        before = self.output.read_bytes()
        self.control_version("0.0.2")
        self.generate()
        self.assertNotEqual(self.output.read_bytes(), before)
        self.assertIn(b'#define CONFIG_VERSION "0.0.2"', self.output.read_bytes())
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_c_string_escaping_roundtrips_through_compiler(self):
        compiler = shutil.which("clang") or shutil.which("cc")
        if not compiler:
            self.skipTest("a native C compiler is not installed")
        # CI metadata can contain shell metacharacters or escaped whitespace.
        # Exercise actual C preprocessing, not just a JSON round-trip.
        branch = 'ci/"quoted"\\path\n\tđặc-biệt-$()-;??/n??=x\x017\x1ff\x7f\r\n'
        with mock.patch.dict(os.environ, {"GITHUB_HEAD_REF": branch}):
            self.generate()
        source = self.root / "print-build-info.c"
        source.write_text(
            '#include <stdio.h>\n#include "generated/build-info.h"\n'
            'int main(void) {\n'
            '    const char value[] = CONFIG_BRANCH;\n'
            '    return fwrite(value, 1, sizeof(value) - 1, stdout) != '
            'sizeof(value) - 1;\n}\n', encoding="utf-8",
        )
        executable = self.root / "print-build-info"
        subprocess.run([compiler, "-std=c11", "-Wall", "-Wextra", "-Werror",
                        str(source), "-o", str(executable)],
                       capture_output=True, text=True, check=True)
        result = subprocess.run([str(executable)], capture_output=True, check=True)
        self.assertEqual(result.stdout, branch.encode("utf-8"))

    def test_command_line_creates_header(self):
        self.generate()
        self.assertIn(b'#define CONFIG_VERSION "0.0.1"', self.output.read_bytes())

    def test_source_archive_nested_in_repository_ignores_parent_git(self):
        self.initialize_git()
        archive = self.root / "source archive"
        archive.mkdir()
        shutil.copy2(self.root / "control", archive / "control")
        shutil.copytree(self.root / "HostFrameworks", archive / "HostFrameworks")
        info = self.build_info(root=archive)
        self.assertEqual(info["CONFIG_COMMIT"], "unknown")
        self.assertEqual(info["CONFIG_BRANCH"], "unknown")

    def test_symlink_root_and_output_paths_with_whitespace(self):
        commit = self.initialize_git()
        alias = self.root / "repository alias with spaces"
        alias.symlink_to(self.root, target_is_directory=True)
        output = self.root / "generated output/build info.h"
        info = self.build_info(root=alias, output=output)
        self.assertEqual(info["CONFIG_COMMIT"], commit)
        self.assertEqual(info["CONFIG_BRANCH"], "main")
        self.assertEqual(info["CONFIG_VERSION"], "0.0.1")

    def test_invalid_arguments_fail_without_creating_header(self):
        for arguments in ([], ["--root"], ["--output"],
                          ["--root", str(self.root)],
                          ["--output", str(self.output)],
                          ["--unexpected"],
                          ["--root", str(self.root), "--output",
                           str(self.output), "unexpected"]):
            with self.subTest(arguments=arguments):
                result = subprocess.run(["/bin/bash", str(SCRIPT), *arguments],
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr)
                self.assertFalse(self.output.exists())

    def test_failed_generation_preserves_existing_header(self):
        self.generate()
        before = self.output.read_bytes()
        before_stat = self.output.stat()
        self.control_version("invalid")
        result = self.generate(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_bytes(), before)
        self.assertEqual(self.output.stat().st_ino, before_stat.st_ino)
        self.assertEqual(self.output.stat().st_mtime_ns, before_stat.st_mtime_ns)
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_output_directory_is_rejected_without_writing_inside(self):
        self.output.mkdir(parents=True)
        result = self.generate(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.output.iterdir()), [])
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_failed_replacement_cleans_up_and_preserves_existing_header(self):
        self.generate()
        before = self.output.read_bytes()
        before_stat = self.output.stat()
        self.control_version("0.0.2")
        failing_executable = shutil.which("false")
        self.assertIsNotNone(failing_executable, "false is required")
        environment = dict(os.environ, PATH=self.utility_path(
            overrides={"mv": failing_executable},
        ))
        result = self.generate(env=environment, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_bytes(), before)
        self.assertEqual(self.output.stat().st_ino, before_stat.st_ino)
        self.assertEqual(self.output.stat().st_mtime_ns, before_stat.st_mtime_ns)
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    @unittest.skipUnless(sys.platform == "darwin", "uses macOS plutil")
    def test_version_makefile_stamps_only_built_plist(self):
        make = shutil.which("gmake") or shutil.which("make")
        if not make or not shutil.which("plutil"):
            self.skipTest("make and plutil are required")
        # Copy the real include so its root-relative control lookup is tested
        # independently from this checkout and without loading Theos.
        (self.root / "version.mk").write_bytes(
            (REPO_ROOT / "version.mk").read_bytes()
        )
        source = self.framework_plist.read_bytes()
        built = self.root / "built.plist"
        built.write_bytes(source)
        (self.root / "Makefile").write_text(
            'include version.mk\n.PHONY: all\nall:\n'
            '\t$(call lc32_stamp_version,$(CURDIR)/built.plist)\n',
            encoding="utf-8",
        )
        subprocess.run([make, "--no-print-directory", "-C", str(self.root), "all"],
                       capture_output=True, text=True, check=True)
        self.assertEqual(self.framework_plist.read_bytes(), source)
        self.assertTrue(built.read_bytes().startswith(b"bplist00"))
        self.assertEqual(
            plistlib.loads(built.read_bytes())["CFBundleShortVersionString"],
            "0.0.1",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
