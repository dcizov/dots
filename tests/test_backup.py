"""Exercise the backup workflow without accessing a real mount or package DB."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
SCRIPTS = REPO / "private_dot_local/share/ucli/scripts"
BACKUP = SCRIPTS / "backup/executable_backup-home.sh"
INVENTORY = SCRIPTS / "inventory/executable_inventory.sh"
PALETTE = REPO / "run_onchange_after_96-desktop-palette.sh"
REAL_RESTIC = shutil.which("restic")
REAL_JUST = shutil.which("just")
UUID = "096a9598-b488-4d51-8d14-e592387e1338"


@unittest.skipIf(os.getuid() == 0, "backup commands intentionally refuse root")
class BackupTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.home = self.root / "user home"
        self.drive = self.root / "backup drive"
        self.dest = self.drive / "cachyos/home"
        self.dest.mkdir(parents=True, mode=0o700)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.extra = self.root / "Portable Apps"
        self.extra.mkdir()
        self.config = self.root / "local config.bash"
        self.config.write_text(
            f"BACKUP_REPO={shlex.quote(str(self.dest))}\nBACKUP_UUID={UUID}\n"
            f"BACKUP_EXTRA_PATHS=({shlex.quote(str(self.extra))})\n"
        )
        self.write_home("Documents/note.txt", "my work\n")
        self.write_home("build/source.txt", "not all build dirs are disposable\n")
        self.write_home(".cache/browser", "regenerate\n")
        self.write_home(".local/share/flatpak/repo/objects.dat", "regenerate\n")
        self.write_home(".local/share/flatpak/overrides/org.test.App", "[Context]\n")
        self.write_home(".local/share/flatpak/overrides/global", "[Environment]\n")
        self.write_home(".var/app/org.test.App/config/settings", "user settings\n")
        self.image = self.extra / "Demo App.AppImage"
        self.image.write_text("fixture executable\n")
        self.image.chmod(0o755)
        (self.extra / "Demo App.AppImage.config").mkdir()
        (self.extra / "Demo App.AppImage.config/settings").write_text("portable data\n")
        self.write_home(".local/share/applications/demo.desktop", f"Exec={self.image}\n")
        (self.home / "Applications").mkdir()
        (self.home / "Applications/Demo Link.AppImage").symlink_to(self.image)
        self.flatpakconf = self.root / "flatpak conf"
        (self.flatpakconf / "installations.d").mkdir(parents=True)
        (self.flatpakconf / "installations.d/secondary.conf").write_text(
            '[Installation "secondary"]\nPath=/var/lib/secondary-flatpak\n'
        )
        self.log = self.root / "restic.args"
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("RESTIC_", "FLATPAK_", "XDG_"))}
        self.env.update(
            HOME=str(self.home), PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
            UCLI_BACKUP_CONFIG=str(self.config), XDG_CURRENT_DESKTOP="KDE",
            FLATPAK_CONFIG_DIR=str(self.flatpakconf), TEST_LOG=str(self.log),
            TEST_UUID=UUID, TEST_DRIVE=str(self.drive), TEST_REPO=str(self.dest),
            DBUS_SESSION_BUS_ADDRESS="unix:path=/not-a-real-bus",
        )
        self.stub("pacman", r'''
case "$1" in
  -Q) printf 'restic 0.19.1\nlocal-demo 1-1\nforeign-dep 2-1\n' ;;
  -Qe) printf 'restic 0.19.1\nlocal-demo 1-1\n' ;;
  -Qen) echo 'restic 0.19.1' ;;
  -Qem|-Qm)
    case "${FOREIGN_MODE:-normal}" in
      empty) exit 1 ;;
      error) echo 'package database not readable' >&2; exit 1 ;;
    esac
    echo 'local-demo 1-1'
    [[ "$1" != -Qm ]] || echo 'foreign-dep 2-1' ;;
  *) exit 99 ;;
esac
''')
        self.stub("pacman-conf", '[[ "$1" == --repo-list ]] && printf "cachyos\\ncore\\nextra\\n"\n')
        self.stub("flatpak", r'''
case "$1" in
  --installations) printf '/var/lib/flatpak\n/var/lib/secondary-flatpak\n' ;;
  remotes)
    [[ "${BROKEN_FLATPAK:-0}" == 0 ]] || exit 1
    printf '%s\thttps://example.invalid/%s\t\t\n' "${2#--}" "${2#--}" ;;
  list)
    case "$*" in
      *--columns=ref,origin,active*) printf 'app/org.test.App/x86_64/stable\t%s\tcommit\n' "${2#--}" ;;
      *--columns=application*) echo org.test.App ;;
    esac ;;
  *) exit 99 ;;
esac
''')
        self.stub("findmnt", r'''
[[ "$1" == -nro && "$3" == --target ]] || exit 99
target=$(realpath -e -- "$4") || exit 1
case "$target" in
  "$TEST_DRIVE"|"$TEST_DRIVE/"*)
    case "$2" in
      TARGET) echo "${MOCK_TARGET:-$TEST_DRIVE}" ;;
      FSTYPE) echo "${MOCK_FSTYPE:-ext4}" ;;
      UUID) echo "${MOCK_UUID:-$TEST_UUID}" ;;
      *) exit 99 ;;
    esac ;;
  *) [[ "$2" == UUID ]] || exit 99; echo 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' ;;
esac
''')
        self.stub("restic", r'''
[[ "$PWD" == "$TEST_REPO" && "$1" == --repo && "$2" == . ]] || exit 99
printf '%s\0' "$@" >> "$TEST_LOG"
if [[ "$3" == init ]]; then touch config; fi
exit "${RESTIC_EXIT:-0}"
''')

    def write_home(self, name, data):
        path = self.home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)

    def stub(self, name, script):
        path = self.bin / name
        path.write_text('#!/bin/bash\nset -eu\n' + script)
        path.chmod(0o755)

    def invoke(self, *args, **extra_env):
        return subprocess.run(args, env=self.env | extra_env, cwd=REPO, text=True, capture_output=True, timeout=60)

    def ok(self, *args, **extra_env):
        result = self.invoke(*args, **extra_env)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result.stdout

    def test_gnome_palette_ignores_plasma_with_gsettings_and_bus(self):
        self.stub("gsettings", 'echo "$*" >> "$TEST_LOG"\n')
        self.ok(PALETTE, XDG_CURRENT_DESKTOP="KDE", XDG_SESSION_DESKTOP="gnome")
        self.assertFalse(self.log.exists())
        self.ok(PALETTE, XDG_CURRENT_DESKTOP="GNOME:GNOME-Classic")
        self.assertEqual(len(self.log.read_text().splitlines()), 3)

    def test_inventory_preserves_scopes_checksums_and_overrides(self):
        output = self.root / "private inventory"
        self.ok(INVENTORY, output, "--appimage", self.extra)
        self.assertEqual(output.stat().st_mode & 0o777, 0o700)
        self.assertIn("foreign-dep 2-1", (output / "packages/foreign-all-with-versions.txt").read_text())
        self.assertIn("cachyos", (output / "packages/repositories.txt").read_text())
        fp = output / "flatpak"
        for scope, name in (("user", "user"), ("system", "system"), ("named-secondary", "installation=secondary")):
            self.assertIn(f"app/org.test.App/x86_64/stable\t{name}", (fp / f"{scope}-refs.tsv").read_text())
            self.assertIn(f"https://example.invalid/{name}", (fp / f"{scope}-remotes.tsv").read_text())
        self.assertTrue((fp / "user-overrides/org.test.App").is_file())
        self.assertEqual((fp / "user-overrides.txt").read_text(), "[Environment]\n")
        self.assertIn(str(self.image), (output / "appimages/appimages.sha256.txt").read_text())
        self.assertIn(str(self.image), (output / "appimages/appimages.symlinks.tsv").read_text())
        self.assertIn("demo.desktop", (output / "appimages/appimage-desktop-files.txt").read_text())
        self.assertFalse((output / "gnome").exists())

    def test_empty_foreign_query_is_not_a_database_failure(self):
        output = self.root / "no foreign packages"
        self.ok(INVENTORY, output, FOREIGN_MODE="empty")
        self.assertEqual((output / "packages/foreign-explicit.txt").read_text(), "")
        broken = self.root / "broken inventory"
        result = self.invoke(INVENTORY, broken, FOREIGN_MODE="error")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("package database not readable", result.stderr)
        self.assertFalse(broken.exists())

    def test_missing_or_wrong_mount_fails_before_restic_or_inventory(self):
        for override in ({"MOCK_TARGET": "/"}, {"MOCK_FSTYPE": "btrfs"}, {"MOCK_UUID": "other"}):
            with self.subTest(override=override):
                for action in ("init", "run"):
                    result = self.invoke(BACKUP, action, **override)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("expected ext4 UUID", result.stderr)
        self.assertFalse(self.log.exists())
        self.assertFalse((self.home / ".local/state").exists())
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_missing_tag_value_cannot_swallow_the_dry_run_flag(self):
        (self.dest / "config").touch()
        result = self.invoke(BACKUP, "run", "--tag", "--dry-run")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--tag needs a name", result.stderr)
        self.assertFalse(self.log.exists())

    def test_same_drive_extra_source_is_rejected(self):
        path = self.drive / "same drive data"
        path.mkdir()
        with self.config.open("a") as config:
            config.write(f"BACKUP_EXTRA_PATHS+=({shlex.quote(str(path))})\n")
        result = self.invoke(BACKUP, "preflight")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source is on the backup filesystem", result.stderr)

    def test_init_is_explicit_and_refuses_a_nonempty_directory(self):
        self.ok(BACKUP, "preflight")
        self.assertNotEqual(self.invoke(BACKUP, "run").returncode, 0)
        self.assertFalse(self.log.exists())
        existing = self.dest / ".existing"
        existing.touch()
        self.assertNotEqual(self.invoke(BACKUP, "init").returncode, 0)
        self.assertFalse(self.log.exists())
        existing.unlink()
        self.ok(BACKUP, "init")
        self.assertTrue((self.dest / "config").exists())
        self.assertNotEqual(self.invoke(BACKUP, "init").returncode, 0)

    def test_home_backup_embeds_manifest_and_passes_through_partial_exit(self):
        (self.dest / "config").touch()
        result = self.invoke(BACKUP, "run", "--dry-run", "--tag", "pre-chezmoi", RESTIC_EXIT="3")
        self.assertEqual(result.returncode, 3, result.stderr)
        args = self.log.read_bytes().split(b"\0")
        self.assertEqual(args[:3], [b"--repo", b".", b"backup"])
        for value in ("--dry-run", "--one-file-system", "pre-chezmoi", str(self.home), str(self.extra)):
            self.assertIn(value.encode(), args)
        manifest = self.home / ".local/state/ucli/backup/inventory.tar"
        self.assertIn(str(manifest).encode(), args)
        with tarfile.open(manifest) as tar:
            self.assertIn(b"cachyos", tar.extractfile("./packages/repositories.txt").read())
            self.assertIn(str(self.image).encode(), tar.extractfile("./appimages/appimages.txt").read())
        self.assertEqual(manifest.stat().st_mode & 0o077, 0)

    def test_failed_flatpak_inventory_prevents_snapshot(self):
        (self.dest / "config").touch()
        result = self.invoke(BACKUP, "run", BROKEN_FLATPAK="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Flatpak remote query failed", result.stderr)
        self.assertFalse(self.log.exists())
        state = self.home / ".local/state/ucli/backup"
        self.assertFalse(list(state.glob(".run.*")))
        self.assertFalse((state / "inventory.tar").exists())

    @unittest.skipUnless(REAL_JUST, "just is not installed")
    def test_just_recipe_preserves_paths_with_spaces(self):
        deployed = self.home / ".local/share/ucli/scripts/inventory/inventory.sh"
        deployed.parent.mkdir(parents=True)
        deployed.symlink_to(INVENTORY)
        output = self.root / "output with spaces"
        justfile = REPO / "private_dot_config/ucli/justfile"
        self.ok(REAL_JUST, "--justfile", justfile, "inventory", output, "--appimage", self.extra)
        self.assertIn(str(self.image), (output / "appimages/appimages.txt").read_text())

    @unittest.skipUnless(REAL_RESTIC, "Restic is not installed")
    def test_real_restic_round_trip(self):
        # Only mount detection is simulated; Restic uses scratch files, with no sudo.
        (self.bin / "restic").unlink()
        (self.bin / "restic").symlink_to(REAL_RESTIC)
        password = self.home / ".password [backup]"
        password.write_text("fixture password\n")
        password.chmod(0o600)
        self.env["RESTIC_PASSWORD_FILE"] = str(password)
        self.ok(BACKUP, "init")
        self.ok(BACKUP, "run", "--dry-run")
        direct = (REAL_RESTIC, "--repo", self.dest)
        self.assertEqual(json.loads(self.ok(*direct, "snapshots", "--json")) or [], [])
        self.ok(BACKUP, "run", "--tag", "smoke")
        self.ok(BACKUP, "check")
        target = self.root / "staging"
        self.ok(*direct, "restore", "latest", "--target", target)
        home = target / self.home.relative_to("/")
        self.assertTrue((home / "Documents/note.txt").is_file())
        self.assertTrue((home / "build/source.txt").is_file())
        self.assertTrue((home / ".local/share/flatpak/overrides/org.test.App").is_file())
        self.assertTrue((home / ".var/app/org.test.App/config/settings").is_file())
        self.assertTrue((home / ".local/state/ucli/backup/inventory.tar").is_file())
        self.assertFalse((home / ".cache/browser").exists())
        self.assertFalse((home / ".local/share/flatpak/repo/objects.dat").exists())
        self.assertFalse((home / password.name).exists())
        image = target / self.image.relative_to("/")
        self.assertEqual(image.read_bytes(), self.image.read_bytes())
        self.assertEqual(image.stat().st_mode & 0o777, 0o755)
        self.assertTrue((image.parent / "Demo App.AppImage.config/settings").is_file())


if __name__ == "__main__":
    unittest.main()
