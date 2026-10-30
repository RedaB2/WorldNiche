"""Release checks must inspect the same private override that the app loads."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release_config", ROOT / "apps/ios/Scripts/check_release_readiness.py")
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)


class ReleaseConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "WorldNiche/Resources").mkdir(parents=True)
        (self.root / "Config").mkdir()
        self.config = {
            "serviceURL": "https://fixture.supabase.co",
            "publicAPIKey": "sb_" + "publishable_" + "x" * 32,
            "invitationHost": "worldniche.app", "privacyPolicyURL": "https://worldniche.app/privacy",
            "supportURL": "https://worldniche.app/support", "appleSignInEnabled": True,
        }
        self.template = self.root / "WorldNiche/Resources/SocialConfiguration.json"
        self.local = self.root / "WorldNiche/Resources/SocialConfiguration.local.json"
        self.template.write_text(json.dumps({key: "" for key in RELEASE.FIELDS}))
        self.shared = self.root / "Config/Shared.xcconfig"
        self.shared.write_text('PRODUCT_BUNDLE_IDENTIFIER = io.worldniche.app\nDEVELOPMENT_TEAM =\n#include? "Signing.local.xcconfig"\n')
        (self.root / "Config/Signing.local.xcconfig").write_text("DEVELOPMENT_TEAM = ZYX9876543\n")
        (self.root / "Config/WorldNiche.entitlements").write_bytes(plistlib.dumps({"com.apple.developer.associated-domains": ["applinks:worldniche.app"]}))
        self.aasa = self.root / "aasa.json"
        self.aasa.write_text(json.dumps({"applinks": {"details": [{"appIDs": ["ZYX9876543.io.worldniche.app"], "components": [{"/": "/invite/*"}]}]}}))

    def blockers(self):
        return RELEASE.check(self.root, self.aasa)[0]

    def test_local_configuration_and_signing_pass_with_blank_public_template(self):
        self.local.write_text(json.dumps(self.config))
        self.assertEqual(self.blockers(), [])

    def test_unconfigured_clone_is_blocked(self):
        self.assertTrue(any("blank" in item for item in self.blockers()))

    def test_invalid_override_does_not_silently_fall_back(self):
        self.template.write_text(json.dumps(self.config))
        self.local.write_text("invalid JSON")
        self.assertTrue(any("invalid JSON" in item for item in self.blockers()))

    def test_local_signing_is_ignored_when_not_included(self):
        self.shared.write_text('PRODUCT_BUNDLE_IDENTIFIER = io.worldniche.app\nDEVELOPMENT_TEAM =\n')
        self.local.write_text(json.dumps(self.config))
        self.assertTrue(any("DEVELOPMENT_TEAM" in item for item in self.blockers()))

    def test_privileged_key_in_local_override_is_rejected(self):
        self.config["publicAPIKey"] = "sb_" + "secret_" + "synthetic-value"
        self.local.write_text(json.dumps(self.config))
        self.assertTrue(any("secret key" in item for item in self.blockers()))
        self.assertFalse(any(self.config["publicAPIKey"] in item for item in self.blockers()))


if __name__ == "__main__":
    unittest.main()
