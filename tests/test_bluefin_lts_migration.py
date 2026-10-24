#!/usr/bin/env python3
"""Unit tests for the Bluefin LTS bootc migration helper."""

import importlib.machinery
import importlib.util
import os
import pathlib
import tempfile
import types
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).parents[1] / "system_files/usr/bin/bluefin-lts-migration"
LOADER = importlib.machinery.SourceFileLoader("bluefin_lts_migration", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
migration = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(migration)


def booted_status(image_ref):
    return {"status": {"booted": {"image": {"image": {"image": image_ref}}}}}


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        root = self.tempdir.name
        self.stamp = os.path.join(root, "bluefin-lts-migrated")
        self.motd_dir = os.path.join(root, "motd.d")
        self.motd_file = os.path.join(self.motd_dir, "50-bluefin-lts-migration")
        self.paths = mock.patch.multiple(
            migration,
            MIGRATED_STAMP=self.stamp,
            MOTD_DIR=self.motd_dir,
            MOTD_FILE=self.motd_file,
        )
        self.paths.start()
        self.addCleanup(self.paths.stop)
        self.addCleanup(self.tempdir.cleanup)

    def run_migration(self, image_ref, *, arch="x86_64", switch_returncode=0):
        switch = mock.Mock(return_value=types.SimpleNamespace(returncode=switch_returncode))
        with (
            mock.patch.object(migration, "get_bootc_status", return_value=booted_status(image_ref)),
            mock.patch.object(migration.os, "uname", return_value=types.SimpleNamespace(machine=arch)),
            mock.patch.object(migration.subprocess, "run", switch),
        ):
            result = migration.main()
        return result, switch

    def test_resolves_all_supported_legacy_repositories(self):
        self.assertEqual(
            migration.resolve_target("ostree-image-signed:docker://ghcr.io/ublue-os/bluefin:lts-hwe", "x86_64"),
            "bluefin-lts:stable",
        )
        self.assertEqual(
            migration.resolve_target("ghcr.io/ublue-os/bluefin-dx:lts", "x86_64"),
            "bluefin-lts:stable",
        )
        self.assertEqual(
            migration.resolve_target("ghcr.io/ublue-os/bluefin-gdx@sha256:abc", "x86_64"),
            "bluefin-lts-nvidia:stable",
        )

    def test_rejects_unknown_or_similarly_named_images(self):
        for image_ref in (
            "ghcr.io/ublue-os/bazzite:lts",
            "ghcr.io/ublue-os/bluefin-dx-extra:lts",
            "ghcr.io/other-org/bluefin:lts",
        ):
            with self.subTest(image_ref=image_ref):
                self.assertIsNone(migration.resolve_target(image_ref, "x86_64"))

    def test_stages_regular_image_switch_with_signature_enforcement(self):
        result, switch = self.run_migration("ghcr.io/ublue-os/bluefin:lts-hwe")

        self.assertEqual(result, 0)
        switch.assert_called_once_with(
            [
                "bootc",
                "switch",
                "--enforce-container-sigpolicy",
                "ghcr.io/projectbluefin/bluefin-lts:stable",
            ]
        )
        self.assertTrue(os.path.exists(self.stamp))

    def test_stages_gdx_to_nvidia_equivalent(self):
        result, switch = self.run_migration("ghcr.io/ublue-os/bluefin-gdx:lts")

        self.assertEqual(result, 0)
        self.assertEqual(
            switch.call_args.args[0][-1],
            "ghcr.io/projectbluefin/bluefin-lts-nvidia:stable",
        )
        self.assertTrue(os.path.exists(self.stamp))

    def test_projectbluefin_image_is_a_noop(self):
        result, switch = self.run_migration("ghcr.io/projectbluefin/bluefin-lts:stable")

        self.assertEqual(result, 0)
        switch.assert_not_called()
        self.assertTrue(os.path.exists(self.stamp))

    def test_unknown_image_is_not_switched_or_stamped(self):
        result, switch = self.run_migration("ghcr.io/ublue-os/bazzite:lts")

        self.assertEqual(result, 1)
        switch.assert_not_called()
        self.assertFalse(os.path.exists(self.stamp))

    def test_arm64_regular_image_switches_to_multi_arch_equivalent(self):
        result, switch = self.run_migration("ghcr.io/ublue-os/bluefin:lts-arm64", arch="aarch64")

        self.assertEqual(result, 0)
        self.assertEqual(
            switch.call_args.args[0][-1],
            "ghcr.io/projectbluefin/bluefin-lts:stable",
        )
        self.assertTrue(os.path.exists(self.stamp))

    def test_arm64_gdx_switches_to_compatible_regular_lts_image(self):
        result, switch = self.run_migration("ghcr.io/ublue-os/bluefin-gdx:lts-arm64", arch="aarch64")

        self.assertEqual(result, 0)
        self.assertEqual(
            switch.call_args.args[0][-1],
            "ghcr.io/projectbluefin/bluefin-lts:stable",
        )

    def test_failed_switch_is_left_unstamped_for_retry(self):
        result, switch = self.run_migration("ghcr.io/ublue-os/bluefin-dx:lts", switch_returncode=1)

        self.assertEqual(result, 1)
        switch.assert_called_once()
        self.assertFalse(os.path.exists(self.stamp))


if __name__ == "__main__":
    unittest.main()
