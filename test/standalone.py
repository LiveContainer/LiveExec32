#!/usr/bin/env python3
"""Local packaging and launcher-contract tests; no game, device, or JIT needed."""
import os
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import subprocess
import tempfile
import unittest
import zipfile

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "Scripts/inject-standalone.sh"


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True,
                          capture_output=True, text=True, **kwargs)


def arm32(subtype=9, encrypted=False):
    commands = struct.pack("<II16sIIIIiiII", 1, 56, b"__TEXT", 0x1000,
                           0x1000, 0, 512, 5, 5, 0, 0)
    commands += struct.pack("<IIII", 0x25, 16, 0x70000, 0x70000)
    if encrypted:
        commands += struct.pack("<IIIII", 0x21, 20, 256, 128, 1)
    header = struct.pack("<7I", 0xFEEDFACE, 12, subtype, 2,
                         3 if encrypted else 2, len(commands), 0)
    return (header + commands).ljust(512, b"\0")


def slices(binary):
    magic, count = struct.unpack_from(">II", binary)
    assert magic == 0xCAFEBABE
    return {cpu: binary[offset:offset + size] for cpu, _, offset, size, _ in
            (struct.unpack_from(">5I", binary, 8 + 20 * i) for i in range(count))}


class StandaloneTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="lc32-standalone-build-")
        cls.addClassCleanup(cls.build.cleanup)
        cls.build_path = Path(cls.build.name)
        cls.launcher = cls.build_path / "launcher"
        cls.framework = cls.build_path / "LiveExec32Shared"
        run("xcrun", "--sdk", "macosx", "clang", "-arch", "arm64", "-Wall", "-Wextra", "-Werror",
            "-Wl,-headerpad,0x1000", "-Wl,-rpath,@executable_path/Frameworks",
            "-I" + str(REPO / "test/standalone-stubs"), REPO / "App/main.c", "-o", cls.launcher)
        run("xcrun", "--sdk", "macosx", "clang", "-arch", "arm64", "-dynamiclib",
            REPO / "test/standalone_runtime_stub.c", "-o", cls.framework)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lc32-standalone-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.game = self.root / "Game With Spaces.app"
        self.runtime = self.root / "LiveExec32.app"
        self.output = self.root / "Standalone Output.app"
        self.game.mkdir()
        self.runtime.mkdir()
        self.original = arm32()
        (self.game / "Game").write_bytes(self.original)
        (self.game / "Game").chmod(0o751)
        self.info = {"CFBundleExecutable": "Game", "CFBundleIdentifier": "org.liveexec32.test.game",
                     "CFBundleDisplayName": "Original Game", "MinimumOSVersion": "7.0",
                     "UIRequiredDeviceCapabilities": ["armv7", "opengles-1"],
                     "UISupportedInterfaceOrientations": ["UIInterfaceOrientationLandscapeLeft"]}
        self.write_info(self.game, self.info)
        self.write_info(self.runtime, {"CFBundleExecutable": "LiveExec32", "MinimumOSVersion": "15.0"})
        run("xcrun", "vtool", "-set-build-version", "2", "15.0", "27.0", "-replace",
            "-output", self.runtime / "LiveExec32", self.launcher)
        run("codesign", "--force", "--sign", "-", self.runtime / "LiveExec32")
        for relative in ("RootFS/usr/lib/dyld", "RootFS/System/Library/Frameworks/LC32.framework/LC32",
                         "Frameworks/LiveExec32Shared.framework/LiveExec32Shared"):
            path = self.runtime / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        os.link(self.runtime / "RootFS/usr/lib/dyld", self.runtime / "RootFS/usr/lib/dyld-hardlink")
        (self.runtime / "RootFS/lib").symlink_to("usr/lib")
        (self.game / "Frameworks/Original.framework").mkdir(parents=True)
        (self.game / "Frameworks/Original.framework/asset").write_bytes(b"keep")
        (self.game / "_CodeSignature").mkdir()
        (self.game / "_CodeSignature/CodeResources").write_bytes(b"stale seal")

    def write_info(self, app, info):
        (app / "Info.plist").write_bytes(plistlib.dumps(info))

    def package(self, *options, ok=True):
        result = subprocess.run(["/bin/bash", str(SCRIPT), *map(str, options), str(self.game),
                                 str(self.runtime)], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        self.assertFalse(list(self.root.glob(".lc32-standalone.*")), "staging directories leaked")
        return result

    def archive_app(self, app):
        ipa = self.root / (app.stem + ".ipa")
        # Make fixtures independently of the packager's zip command.
        with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as archive:
            prefix = Path("Payload") / app.name
            archive.write(app, str(prefix))
            for directory, directories, files in os.walk(app, followlinks=False):
                for name in directories + files:
                    path = Path(directory) / name
                    relative = str(prefix / path.relative_to(app))
                    if path.is_symlink():
                        entry = zipfile.ZipInfo(relative)
                        entry.create_system = 3
                        entry.external_attr = path.lstat().st_mode << 16
                        archive.writestr(entry, os.readlink(path))
                    else:
                        archive.write(path, relative)
            archive.writestr("iTunesMetadata.plist", b"original metadata")
            archive.writestr(".hidden-asset", b"keep hidden files")
        return ipa

    def extract_app(self, ipa):
        destination = self.root / "unpacked"
        run("/usr/bin/unzip", "-q", ipa, "-d", destination)
        return next((destination / "Payload").glob("*.app"))

    def verify(self, app, hardlinks=True, minimum="15.0"):
        images = slices((app / "Game").read_bytes())
        self.assertEqual(images[12], self.original)
        self.assertEqual(stat.S_IMODE((app / "Game").stat().st_mode), 0o751)
        header = struct.unpack_from("<8I", images[0x100000C])
        offset = 32
        sdk = None
        for _ in range(header[4]):
            command, size = struct.unpack_from("<II", images[0x100000C], offset)
            if command == 0x32:
                sdk = struct.unpack_from("<6I", images[0x100000C], offset)[4]
            offset += size
        self.assertEqual(sdk, 0x70000, "guest SDK changed")
        info = plistlib.loads((app / "Info.plist").read_bytes())
        self.assertEqual(info["MinimumOSVersion"], minimum)
        self.assertEqual(info["CFBundleExecutable"], "Game")
        self.assertEqual(info["CFBundleIdentifier"], self.info["CFBundleIdentifier"])
        self.assertEqual(info["UISupportedInterfaceOrientations"], self.info["UISupportedInterfaceOrientations"])
        self.assertEqual((app / "Frameworks/Original.framework/asset").read_bytes(), b"keep")
        self.assertEqual(os.readlink(app / "RootFS/lib"), "usr/lib")
        self.assertEqual((app / "RootFS/usr/lib/dyld").read_bytes(),
                         (app / "RootFS/usr/lib/dyld-hardlink").read_bytes())
        if hardlinks:
            self.assertEqual((app / "RootFS/usr/lib/dyld").stat().st_ino,
                             (app / "RootFS/usr/lib/dyld-hardlink").stat().st_ino)
        self.assertFalse((app / "_CodeSignature").exists())
        return info

    def test_output_preserves_input_and_guest_sdk(self):
        self.package("--output", self.output)
        info = self.verify(self.output)
        self.assertEqual(info["UIRequiredDeviceCapabilities"], ["opengles-1", "arm64"])
        self.assertEqual((self.game / "Game").read_bytes(), self.original)
        self.assertTrue((self.game / "_CodeSignature/CodeResources").exists())

    def test_default_is_in_place_with_backup(self):
        self.package()
        self.verify(self.game)
        backup = Path(str(self.game) + ".lc32-backup")
        self.assertEqual((backup / "Game").read_bytes(), self.original)
        self.assertEqual(plistlib.loads((backup / "Info.plist").read_bytes()), self.info)

    def test_backported_runtime_minimum_is_respected(self):
        for minimum in ("11.0", "12.0", "14.0"):
            with self.subTest(minimum=minimum):
                self.write_info(self.runtime, {"CFBundleExecutable": "LiveExec32",
                                               "MinimumOSVersion": minimum})
                run("xcrun", "vtool", "-set-build-version", "2", minimum, "27.0", "-replace",
                    "-output", self.runtime / "LiveExec32", self.launcher)
                run("codesign", "--force", "--sign", "-", self.runtime / "LiveExec32")
                output = self.root / ("Standalone-" + minimum + ".app")
                self.package("--output", output)
                self.verify(output, minimum=minimum)

    def test_higher_game_minimum_is_preserved(self):
        self.info["MinimumOSVersion"] = "16.0"
        self.write_info(self.game, self.info)
        self.package("--output", self.output)
        self.verify(self.output, minimum="16.0")

    def test_invalid_runtime_minimum_is_rejected(self):
        for minimum in (None, "", "14.invalid", 14):
            with self.subTest(minimum=minimum):
                info = {"CFBundleExecutable": "LiveExec32"}
                if minimum is not None:
                    info["MinimumOSVersion"] = minimum
                self.write_info(self.runtime, info)
                self.assertIn("invalid runtime MinimumOSVersion", self.package(ok=False).stderr)
                self.assertEqual((self.game / "Game").read_bytes(), self.original)
                self.assertFalse(Path(str(self.game) + ".lc32-backup").exists())

    def test_ipa_output_preserves_input_metadata_and_links(self):
        (self.game / "asset-link").symlink_to("Frameworks/Original.framework/asset")
        (self.runtime / "RootFS/guest-only-link").symlink_to("/lc32-guest-only/lib")
        self.game = self.archive_app(self.game)
        original = self.game.read_bytes()
        self.output = self.output.with_suffix(".ipa")
        self.package("--output", self.output)
        app = self.extract_app(self.output)
        self.verify(app, hardlinks=False)
        self.assertEqual(os.readlink(app / "asset-link"), "Frameworks/Original.framework/asset")
        self.assertEqual(os.readlink(app / "RootFS/guest-only-link"), "/lc32-guest-only/lib")
        self.assertEqual(self.game.read_bytes(), original)
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(archive.testzip(), None)
            self.assertEqual(archive.read("iTunesMetadata.plist"), b"original metadata")
            self.assertEqual(archive.read(".hidden-asset"), b"keep hidden files")
            self.assertFalse(any("lc32-backup" in name for name in archive.namelist()))

    def test_ipa_default_with_runtime_ipa_and_backup(self):
        self.game = self.archive_app(self.game)
        self.runtime = self.archive_app(self.runtime)
        original = self.game.read_bytes()
        runtime_original = self.runtime.read_bytes()
        self.package()
        self.verify(self.extract_app(self.game), hardlinks=False)
        self.assertEqual(Path(str(self.game) + ".lc32-backup").read_bytes(), original)
        self.assertEqual(self.runtime.read_bytes(), runtime_original)

    def test_app_accepts_runtime_ipa(self):
        self.runtime = self.archive_app(self.runtime)
        self.package("--output", self.output)
        self.verify(self.output, hardlinks=False)

    def test_output_format_must_match_input(self):
        self.package("--output", self.output.with_suffix(".ipa"), ok=False)
        self.game = self.archive_app(self.game)
        original = self.game.read_bytes()
        self.package("--output", self.output, ok=False)
        self.assertEqual(self.game.read_bytes(), original)

    def test_invalid_and_ambiguous_ipas_are_rejected(self):
        self.game = self.archive_app(self.game)
        with zipfile.ZipFile(self.game, "a") as archive:
            archive.writestr("Payload/Other.app/Info.plist", b"other app")
        original = self.game.read_bytes()
        self.assertIn("exactly one app", self.package(ok=False).stderr)
        self.assertEqual(self.game.read_bytes(), original)
        self.game.write_bytes(b"not a zip")
        self.package(ok=False)
        self.assertEqual(self.game.read_bytes(), b"not a zip")
        self.assertFalse(Path(str(self.game) + ".lc32-backup").exists())

    def test_ipa_traversal_and_symlink_payload_are_rejected(self):
        app = self.game
        self.game = self.root / "Unsafe.ipa"
        for path in ("../outside", "/absolute", "Payload/../../outside"):
            with self.subTest(path=path):
                with zipfile.ZipFile(self.game, "w") as archive:
                    archive.writestr(path, b"must not extract")
                self.assertIn("unsafe IPA entry", self.package(ok=False).stderr)
        with zipfile.ZipFile(self.game, "w") as archive:
            link = zipfile.ZipInfo("Payload")
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(link, str(self.root))
        self.assertIn("real Payload directory", self.package(ok=False).stderr)
        self.assertEqual((app / "Game").read_bytes(), self.original)

    def test_ipa_symlink_cannot_redirect_extraction(self):
        app = self.game
        self.game = self.root / "Symlink.ipa"
        with zipfile.ZipFile(self.game, "w") as archive:
            link = zipfile.ZipInfo("Payload/Redirect.app")
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(link, str(app))
            archive.writestr("Payload/Redirect.app/Game", b"must not overwrite the original")
        self.package(ok=False)
        self.assertEqual((app / "Game").read_bytes(), self.original)

    def test_ipa_archive_failure_leaves_original_untouched(self):
        self.game = self.archive_app(self.game)
        original = self.game.read_bytes()
        utilities = self.root / "utilities"
        utilities.mkdir()
        zipper = utilities / "zip"
        zipper.write_text('#!/bin/bash\nexit 97\n')
        zipper.chmod(0o755)
        environment = dict(os.environ, PATH=str(utilities) + ":" + os.environ["PATH"])
        result = subprocess.run(["/bin/bash", str(SCRIPT), str(self.game), str(self.runtime)],
                                env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 97, result.stderr)
        self.assertEqual(self.game.read_bytes(), original)
        self.assertFalse(Path(str(self.game) + ".lc32-backup").exists())
        self.assertFalse(list(self.root.glob(".lc32-standalone.*")))

    def test_all_arm32_slices_are_preserved(self):
        armv6 = arm32(subtype=6)
        payload = struct.pack(">II", 0xCAFEBABE, 2)
        payload += struct.pack(">5I", 12, 6, 4096, len(armv6), 12)
        payload += struct.pack(">5I", 12, 9, 8192, len(self.original), 12)
        payload = payload.ljust(4096, b"\0") + armv6
        payload = payload.ljust(8192, b"\0") + self.original
        (self.game / "Game").write_bytes(payload)
        self.package("--output", self.output)
        result = (self.output / "Game").read_bytes()
        self.assertEqual(struct.unpack_from(">II", result)[1], 3)
        for i, expected in ((1, armv6), (2, self.original)):
            _, _, offset, size, _ = struct.unpack_from(">5I", result, 8 + i * 20)
            self.assertEqual(result[offset:offset + size], expected)

    def test_copy_failure_does_not_replace_the_app(self):
        utilities = self.root / "utilities"
        utilities.mkdir()
        # Fail the final RootFS copy, after successful executable injection.
        rsync = utilities / "rsync"
        rsync.write_text('#!/bin/bash\ncase "$*" in *RootFS*) exit 99 ;; esac\n'
                         'exec /usr/bin/rsync "$@"\n')
        rsync.chmod(0o755)
        environment = dict(os.environ, PATH=str(utilities) + ":" + os.environ["PATH"])
        result = subprocess.run(["/bin/bash", str(SCRIPT), str(self.game), str(self.runtime)],
                                env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 99, result.stderr)
        self.assertEqual((self.game / "Game").read_bytes(), self.original)
        self.assertTrue((self.game / "_CodeSignature/CodeResources").exists())
        self.assertFalse(Path(str(self.game) + ".lc32-backup").exists())
        self.assertFalse(list(self.root.glob(".lc32-standalone.*")))

    def test_publish_failure_restores_the_original(self):
        utilities = self.root / "utilities"
        utilities.mkdir()
        move = utilities / "mv"
        move.write_text('#!/bin/bash\ncase "$*" in *Standalone.app*) exit 98 ;; esac\n'
                        'exec /bin/mv "$@"\n')
        move.chmod(0o755)
        environment = dict(os.environ, PATH=str(utilities) + ":" + os.environ["PATH"])
        result = subprocess.run(["/bin/bash", str(SCRIPT), str(self.game), str(self.runtime)],
                                env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 98, result.stderr)
        self.assertEqual((self.game / "Game").read_bytes(), self.original)
        self.assertEqual(plistlib.loads((self.game / "Info.plist").read_bytes()), self.info)
        self.assertFalse(Path(str(self.game) + ".lc32-backup").exists())
        self.assertFalse(list(self.root.glob(".lc32-standalone.*")))

    def test_explicit_in_place_and_dictionary_capabilities(self):
        self.info["UIRequiredDeviceCapabilities"] = {"armv7": True, "arm64": False, "gps": False}
        self.write_info(self.game, self.info)
        self.package("--in-place")
        self.assertEqual(self.verify(self.game)["UIRequiredDeviceCapabilities"], {"arm64": True, "gps": False})

    def test_existing_output_and_conflicting_options_are_rejected(self):
        self.output.mkdir()
        sentinel = self.output / "keep"
        sentinel.write_text("unchanged")
        self.package("--output", self.output, ok=False)
        self.package("--in-place", "--output", self.output, ok=False)
        self.assertEqual(sentinel.read_text(), "unchanged")
        self.assertEqual((self.game / "Game").read_bytes(), self.original)

    def test_framework_collision_and_existing_backup_are_rejected(self):
        collision = self.game / "Frameworks/LiveExec32Shared.framework"
        collision.mkdir()
        self.package(ok=False)
        collision.rmdir()
        Path(str(self.game) + ".lc32-backup").mkdir()
        self.package(ok=False)
        self.assertEqual((self.game / "Game").read_bytes(), self.original)

    def test_invalid_encrypted_and_native_inputs_leave_source_untouched(self):
        for payload in (b"not Mach-O", arm32(encrypted=True), self.launcher.read_bytes()):
            with self.subTest(payload_size=len(payload)):
                (self.game / "Game").write_bytes(payload)
                self.package(ok=False)
                self.assertEqual((self.game / "Game").read_bytes(), payload)
                self.assertFalse(Path(str(self.game) + ".lc32-backup").exists())

    def test_unsafe_executable_and_nested_output_are_rejected(self):
        self.info["CFBundleExecutable"] = "../outside"
        self.write_info(self.game, self.info)
        self.package(ok=False)
        self.package("--output", self.game / "Nested.app", ok=False)
        self.assertEqual((self.game / "Game").read_bytes(), self.original)

    def test_old_and_non_ios_launchers_are_rejected(self):
        launcher = self.runtime / "LiveExec32"
        launcher.write_bytes(launcher.read_bytes().replace(b"LiveExec32Standalone:1", b"LiveExec32Standalone:0"))
        result = self.package(ok=False)
        self.assertIn("lacks bundled RootFS support", result.stderr)
        shutil.copyfile(self.launcher, launcher)
        result = self.package(ok=False)
        self.assertIn("device iOS build", result.stderr)

    @unittest.skipUnless(os.environ.get("LC32_TEST_RUNTIME_APP"), "optional built-runtime smoke test")
    def test_built_runtime(self):
        self.runtime = Path(os.environ["LC32_TEST_RUNTIME_APP"]).resolve()
        self.package("--output", self.output)
        self.assertEqual(slices((self.output / "Game").read_bytes())[12], self.original)
        for relative in ("RootFS/usr/lib/dyld", "RootFS/System/Library/Frameworks/LC32.framework/LC32",
                         "Frameworks/LiveExec32Shared.framework/LiveExec32Shared"):
            self.assertEqual((self.output / relative).read_bytes(), (self.runtime / relative).read_bytes())

    @unittest.skipUnless(os.environ.get("LC32_TEST_RUNTIME_APP"), "optional built-runtime IPA smoke test")
    def test_built_runtime_ipa(self):
        runtime = Path(os.environ["LC32_TEST_RUNTIME_APP"]).resolve()
        self.runtime = self.archive_app(runtime)
        self.game = self.archive_app(self.game)
        self.package()
        app = self.extract_app(self.game)
        self.assertEqual(slices((app / "Game").read_bytes())[12], self.original)
        for relative in ("RootFS/usr/lib/dyld", "RootFS/System/Library/Frameworks/LC32.framework/LC32",
                         "Frameworks/LiveExec32Shared.framework/LiveExec32Shared"):
            self.assertEqual((app / relative).read_bytes(), (runtime / relative).read_bytes())

    def test_real_launcher_prefers_bundled_runtime_and_preserves_arguments(self):
        shutil.copyfile(self.launcher, self.game / "Game")
        (self.game / "Game").chmod(0o755)
        (self.game / "RootFS").mkdir()
        framework = self.game / "Frameworks/LiveExec32Shared.framework/LiveExec32Shared"
        framework.parent.mkdir()
        shutil.copyfile(self.framework, framework)
        environment = dict(os.environ, HOME=str(self.root), ROOT_PATH="/wrong",
                           NATIVE_GUEST_THREADS="0", DYLD_PATH="/wrong",
                           LC32_TEST_INSTALLED_LAUNCHER="/missing/LiveExec32.app/LiveExec32")
        result = run(self.game / "Game", "level 1", "--flag", env=environment)
        self.assertIn(f"root={self.game}/RootFS\n", result.stdout)
        self.assertIn(f"argv0={self.game}/Game\n", result.stdout)
        self.assertIn(f"argv1={self.game}/Game\n", result.stdout)
        self.assertIn("argv2=level 1\nargv3=--flag\n", result.stdout)
        self.assertIn("native-threads=unset\ndyld=unset\n", result.stdout)
        self.assertIn(f"home={self.root}\n", result.stdout)
        # Without bundled RootFS, retain the jailbreak-injected launch contract.
        (self.game / "RootFS").rmdir()
        environment["LC32_TEST_INSTALLED_LAUNCHER"] = str(self.runtime / "LiveExec32")
        result = run(self.game / "Game", env=environment)
        self.assertIn(f"root={self.runtime}/RootFS\n", result.stdout)
        self.assertIn(f"argv0={self.runtime}/LiveExec32\n", result.stdout)
        # The ordinary CLI path must still forward the caller's argv unchanged.
        cli = self.game / "LiveExec32"
        shutil.copyfile(self.launcher, cli)
        cli.chmod(0o755)
        result = run(cli, "/guest/program", env=environment)
        self.assertIn(f"argc=2\nargv0={cli}\nargv1=/guest/program\n", result.stdout)
        self.assertIn("root=/wrong\n", result.stdout)


if __name__ == "__main__":
    unittest.main()
