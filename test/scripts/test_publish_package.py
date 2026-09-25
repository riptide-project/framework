"""Publication control flow without contacting registries or using credentials."""

import importlib.util
import os
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "publish_package", Path(__file__).resolve().parents[2] / "scripts/publish-package.py"
)
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)
check_index = publisher.already_published


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.index_check = patch.object(publisher, "already_published", return_value=False)
        self.index_check.start()
        self.addCleanup(self.index_check.stop)

    @patch.dict(os.environ, {"REGISTRY_TOKEN": "test-credential"})
    def test_existing_package_skips_authentication_and_publish(self):
        with patch.object(publisher, "already_published", return_value=True):
            with patch.object(publisher.subprocess, "run") as run:
                publisher.publish("wally")
                run.assert_not_called()

    def test_index_formats_identify_exact_published_version(self):
        pesde = "['0.9.0-maelstrom.3 roblox']\npublished_at = 'today'\n"
        wally = '{"package":{"name":"riptide/core","version":"0.9.0-maelstrom.3"}}\n'
        with patch.object(publisher, "urlopen") as open_index:
            open_index.return_value.__enter__.return_value.read.return_value = pesde.encode()
            manifest = {"name": "riptide/core", "version": "0.9.0-maelstrom.3", "target": {"environment": "roblox"}, "indices": {"default": "https://github.com/pesde-pkg/index"}}
            self.assertTrue(check_index("pesde", manifest, manifest))
            manifest["version"] = "0.9.0-maelstrom.4"
            self.assertFalse(check_index("pesde", manifest, manifest))
            open_index.return_value.__enter__.return_value.read.return_value = wally.encode()
            package = {"name": "riptide/core", "version": "0.9.0-maelstrom.3", "registry": "https://github.com/UpliftGames/wally-index"}
            self.assertTrue(check_index("wally", package, {"package": package}))
            package["version"] = "0.9.0-maelstrom.4"
            self.assertFalse(check_index("wally", package, {"package": package}))

    def test_acknowledgements_require_the_expected_package(self):
        cases = [
            ("pesde", "\x1b[32mpublished riptide/core@1.2.3 roblox\x1b[0m\n", True),
            ("pesde", "published riptide/core@1.2.30 roblox\n", False),
            ("pesde", "published other/core@1.2.3 roblox\n", False),
            ("wally", "Package published successfully!\n", True),
        ]
        for registry, output, expected in cases:
            with self.subTest(registry=registry, output=output):
                self.assertEqual(
                    publisher.acknowledged(registry, output, "riptide/core", "1.2.3"), expected
                )

    @patch.dict(os.environ, {"REGISTRY_TOKEN": "test-credential"})
    def test_zero_exit_registry_errors_block_publication_and_logout(self):
        failures = [
            ("pesde", "error occurred publishing workspace root: unauthorized\n"),
            ("wally", "Error: 403 Forbidden\n"),
        ]
        for registry, output in failures:
            with self.subTest(registry=registry), patch.object(publisher.subprocess, "run") as run:
                run.side_effect = [
                    subprocess.CompletedProcess([], 0),
                    subprocess.CompletedProcess([], 0, output),
                    subprocess.CompletedProcess([], 0),
                ]
                with self.assertRaises(SystemExit):
                    publisher.publish(registry)
                self.assertEqual(run.call_args_list[-1].args[0][-1], "logout")

    @patch.dict(os.environ, {"REGISTRY_TOKEN": "test-credential"})
    def test_nonzero_exit_is_rejected_even_with_success_text(self):
        with patch.object(publisher.subprocess, "run") as run:
            run.side_effect = [
                subprocess.CompletedProcess([], 0),
                subprocess.CompletedProcess([], 1, "Package published successfully!\n"),
                subprocess.CompletedProcess([], 0),
            ]
            with self.assertRaises(SystemExit):
                publisher.publish("wally")

    @patch.dict(os.environ, {"REGISTRY_TOKEN": "test-credential"})
    def test_confirmed_publication_finishes_and_logs_out(self):
        with patch.object(publisher.subprocess, "run") as run:
            run.side_effect = [
                subprocess.CompletedProcess([], 0),
                subprocess.CompletedProcess([], 0, "Package published successfully!\n"),
                subprocess.CompletedProcess([], 0),
            ]
            publisher.publish("wally")
            self.assertEqual(run.call_args_list[-1].args[0], ["wally", "logout"])

    @patch.dict(os.environ, {"REGISTRY_TOKEN": ""})
    def test_missing_credentials_do_not_invoke_cli(self):
        with patch.object(publisher.subprocess, "run") as run:
            with self.assertRaises(SystemExit):
                publisher.publish("pesde")
            run.assert_not_called()

    def test_pesde_login_uses_one_bearer_prefix(self):
        for token in ("test-credential", "Bearer test-credential"):
            with self.subTest(token=token), patch.dict(os.environ, {"REGISTRY_TOKEN": token}):
                with patch.object(publisher.subprocess, "run") as run:
                    run.side_effect = [
                        subprocess.CompletedProcess([], 1),
                        subprocess.CompletedProcess([], 0),
                    ]
                    with self.assertRaises(SystemExit):
                        publisher.publish("pesde")
                    self.assertEqual(run.call_args_list[0].args[0][-1], "Bearer test-credential")


if __name__ == "__main__":
    unittest.main()
