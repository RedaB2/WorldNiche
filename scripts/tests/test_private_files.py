"""Exercise Git's actual index so forced adds cannot silently bypass the check."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("private_files", ROOT / "scripts/check_private_files.py")
GUARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUARD)
TEMPLATE = "apps/ios/WorldNiche/Resources/SocialConfiguration.json"


class PrivateFilesTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git("init", "--quiet")
        shutil.copy2(ROOT / ".gitignore", self.root / ".gitignore")
        self.write(TEMPLATE, json.dumps({"serviceURL": "", "publicAPIKey": "", "appleSignInEnabled": False}))
        self.git("add", ".gitignore", TEMPLATE)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.DEVNULL)

    def write(self, path, value="synthetic fixture"):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value)

    def check(self):
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured), contextlib.redirect_stderr(captured):
            result = GUARD.check(self.root)
        return result, captured.getvalue()

    def test_add_all_excludes_private_files_and_keeps_source_and_examples(self):
        private = [
            "backend/.env.local", ".envrc", ".local/archive/old-project.tar.gz",
            "apps/ios/Config/Signing.local.xcconfig",
            "apps/ios/WorldNiche/Resources/SocialConfiguration.local.json",
            "AuthKey_TEST.p8",
            "distribution.p12",
            "certificate.cer",
            "profile.mobileprovision",
            "ExportOptions.plist", "release/WorldNiche.xcarchive/Info.plist",
            "WorldNiche.ipa", "WorldNiche.app/Info.plist", "accounts.dump", "journal.sqlite",
            "accounts.db-journal",
            "outputs/reviewer-notes.txt", "work/private-fixture.json",
            ".xcodebuildmcp/config.yaml", "apps/web/.vercel/output/config.json",
        ]
        public = ["backend/.env.example", "apps/ios/WorldNiche/App.swift", "marketing/screenshot.png"]
        for path in private + public:
            self.write(path)
        self.git("add", "--all")
        tracked = self.git("ls-files", "-z").decode().split("\0")
        for path in private:
            self.assertNotIn(path, tracked)
        for path in public:
            self.assertIn(path, tracked)
        self.assertEqual(self.check()[0], 0)

    def test_forced_add_is_rejected_without_printing_content(self):
        path = ".local/private-review.txt"
        self.write(path, "do not print this private content")
        self.git("add", "--force", path)
        result, message = self.check()
        self.assertEqual(result, 1)
        self.assertIn(path, message)
        self.assertNotIn("do not print this private content", message)

    def test_commit_hook_blocks_a_force_added_private_file(self):
        (self.root / "scripts").mkdir()
        (self.root / ".githooks").mkdir()
        shutil.copy2(ROOT / "scripts/check_private_files.py", self.root / "scripts/check_private_files.py")
        shutil.copy2(ROOT / ".githooks/pre-commit", self.root / ".githooks/pre-commit")
        self.git("config", "core.hooksPath", ".githooks")
        self.git("config", "user.name", "Synthetic Test")
        self.git("config", "user.email", "fixture@example.com")
        self.write("backend/.env.local", "synthetic private content")
        self.git("add", "--force", "backend/.env.local")
        result = subprocess.run(["git", "commit", "-m", "Must be blocked"], cwd=self.root, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("private or generated files are tracked", result.stderr)
        self.assertNotIn("synthetic private content", result.stderr)

    def test_already_tracked_key_becomes_rejected_when_ignore_rule_is_added(self):
        self.write("unexpected.p8")
        self.git("add", "--force", "unexpected.p8")
        self.assertEqual(self.check()[0], 1)

    def test_configured_public_template_is_rejected(self):
        self.write(TEMPLATE, json.dumps({"serviceURL": "https://example.com", "publicAPIKey": "synthetic", "appleSignInEnabled": True}))
        self.git("add", TEMPLATE)
        result, message = self.check()
        self.assertEqual(result, 1)
        self.assertNotIn("https://example.com", message)

    def test_staged_template_is_checked_instead_of_unstaged_working_copy(self):
        self.write(TEMPLATE, json.dumps({"serviceURL": "https://example.com", "publicAPIKey": "synthetic", "appleSignInEnabled": True}))
        self.git("add", TEMPLATE)
        self.write(TEMPLATE, json.dumps({"serviceURL": "", "publicAPIKey": "", "appleSignInEnabled": False}))
        self.assertEqual(self.check()[0], 1)


if __name__ == "__main__":
    unittest.main()
