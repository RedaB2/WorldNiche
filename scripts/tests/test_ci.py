"""Keep routing conservative and never retry an application test failure."""
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CHANGES = load("ci_changes")
SIMULATOR = load("ci_simulator")


class ChangeRoutingTests(unittest.TestCase):
    def test_website_and_listing_only_skip_native(self):
        self.assertFalse(CHANGES.needs_native([
            "apps/web/landing-site/index.html", "apps/web/invite-hosting/tests/landing-preview.test.mjs",
            "marketing/app-store/badge.svg", "docs/deployment.md",
        ]))

    def test_native_shared_and_unknown_changes_run_native(self):
        for path in ["apps/ios/WorldNiche/App.swift", "scripts/check.sh", "scripts/ci_simulator.py",
                     ".github/workflows/ci.yml", "ops/production.json", "backend/schema.sql", "new-config"]:
            with self.subTest(path=path):
                self.assertTrue(CHANGES.needs_native(["apps/web/index.html", path]))
        self.assertTrue(CHANGES.needs_native([]))

    def test_manual_or_missing_base_runs_native(self):
        for event, base in [("workflow_dispatch", "abc"), ("push", "0" * 40), ("push", "")]:
            self.assertTrue(CHANGES.detect(event, base, "def"))

    def test_git_diff_handles_branch_base_deletions_and_renames(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args], text=True).strip()

            git("init", "-q", "-b", "main")
            git("config", "user.name", "CI Fixture")
            git("config", "user.email", "ci@example.invalid")
            for folder in ["apps/ios", "apps/web"]:
                (root / folder).mkdir(parents=True)
            (root / "apps/ios/App.swift").write_text("fixture\n")
            (root / "apps/web/index.html").write_text("old\n")
            git("add", ".")
            git("commit", "-qm", "base")
            base = git("rev-parse", "HEAD")
            git("checkout", "-qb", "website")
            (root / "apps/web/index.html").write_text("new\n")
            git("commit", "-qam", "website")
            head = git("rev-parse", "HEAD")
            git("checkout", "-q", "main")
            (root / "apps/ios/App.swift").write_text("base branch moved\n")
            git("commit", "-qam", "native on main")
            moved_base = git("rev-parse", "HEAD")
            self.assertFalse(CHANGES.detect("pull_request", moved_base, head, cwd=root))
            self.assertFalse(CHANGES.detect("push", base, head, cwd=root))
            git("checkout", "-q", "website")
            git("mv", "apps/ios/App.swift", "apps/web/moved.swift")
            git("commit", "-qm", "move native file out")
            self.assertTrue(CHANGES.detect("push", head, git("rev-parse", "HEAD"), cwd=root))


class SimulatorVerdictTests(unittest.TestCase):
    def setUp(self):
        # Sanitized summary of PR5's actual XCTest startup failure.
        self.startup = {
            "result": "Failed", "passedTests": 0, "failedTests": 1, "skippedTests": 0,
            "totalTestCount": 1,
            "testFailures": [{
                "testIdentifierString": "WorldNiche-Runner (79080) encountered an error",
                "failureText": "Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. "
                               "(Underlying Error: The test runner crashed while preparing to run tests: "
                               "WorldNiche-Runner at -[XCTWaiter(StallHandling) handleStalledWait:])",
            }],
        }
        self.passed = {"result": "Passed", "passedTests": 9, "failedTests": 0,
                       "skippedTests": 0, "totalTestCount": 9, "testFailures": []}

    def test_recorded_pre_test_runner_crash_is_retryable(self):
        self.assertEqual(SIMULATOR.classify(65, self.startup, "Testing started\n"), "runner-startup")

    def test_started_test_or_assertion_is_never_retryable(self):
        log = "Test Case '-[WorldNicheUITests.JournalUITests testExample]' started."
        self.assertEqual(SIMULATOR.classify(65, self.startup, log), "test-failure")
        self.startup["testFailures"][0]["testIdentifierString"] = "JournalUITests/testExample()"
        self.assertEqual(SIMULATOR.classify(65, self.startup, ""), "test-failure")

    def test_launch_timeout_after_eight_passes_is_not_retried(self):
        self.startup.update(passedTests=8, totalTestCount=9)
        self.startup["testFailures"][0]["failureText"] = "Failed to launch io.worldniche.app: Timed out"
        self.assertEqual(SIMULATOR.classify(65, self.startup, ""), "test-failure")

    def test_unknown_runner_failure_is_not_retried(self):
        self.startup["testFailures"][0]["failureText"] = "unexpected application crash"
        self.assertEqual(SIMULATOR.classify(65, self.startup, ""), "test-failure")

    def test_success_requires_exit_code_and_complete_results(self):
        self.assertEqual(SIMULATOR.classify(0, self.passed, ""), "passed")
        self.assertNotEqual(SIMULATOR.classify(65, self.passed, ""), "passed")
        for summary in [{}, {**self.passed, "passedTests": 0}, {**self.passed, "skippedTests": 1},
                        {**self.passed, "failedTests": 1}, {**self.passed, "result": "Failed"}]:
            self.assertNotEqual(SIMULATOR.classify(0, summary, ""), "passed")

    def test_retry_is_bounded_and_does_not_mask_later_failure(self):
        for outcomes, expected_code, calls in [
            (["passed"], 0, 1), (["runner-startup", "passed"], 0, 2),
            (["runner-startup", "runner-startup"], 1, 2),
            (["runner-startup", "test-failure"], 1, 2),
            (["test-failure"], 1, 1), (["unverified"], 1, 1),
        ]:
            with self.subTest(outcomes=outcomes), patch.object(SIMULATOR, "report"):
                attempt = Mock(side_effect=outcomes)
                self.assertEqual(SIMULATOR.run_tests(attempt), expected_code)
                self.assertEqual(attempt.call_count, calls)

    def test_attempt_waits_for_boot_and_preserves_results_before_cleanup(self):
        commands = []

        def capture(command, path, timeout, check=True):
            commands.append(command)
            if "create" in command:
                path.write_text("fixture-device\n")
            elif "xcresulttool" in command:
                import json
                path.write_text(json.dumps(self.passed))
            else:
                path.write_text("")
            return 0

        with tempfile.TemporaryDirectory() as directory, patch.object(SIMULATOR, "OUTPUT", Path(directory)), \
                patch.object(SIMULATOR, "capture", side_effect=capture), patch.object(SIMULATOR, "report"):
            self.assertEqual(SIMULATOR.run_attempt(1), "passed")
            self.assertTrue((Path(directory) / "attempt-1/summary.json").exists())
        actions = [command[2] if command[0] == "xcrun" else command[1] for command in commands]
        self.assertEqual(actions, ["create", "boot", "bootstatus", "io", "test-without-building", "get", "shutdown", "delete"])
        self.assertIn(SIMULATOR.RUNTIME, commands[0])
        self.assertIn("-b", commands[2])
        self.assertIn("platform=iOS Simulator,id=fixture-device", commands[4])
        self.assertTrue(all(command[-1] == "fixture-device" for command in commands[-2:]))

    def test_boot_timeout_never_starts_tests_and_still_cleans_up(self):
        commands = []

        def capture(command, path, timeout, check=True):
            commands.append(command)
            path.write_text("fixture-device\n" if "create" in command else "")
            if "bootstatus" in command:
                raise subprocess.TimeoutExpired(command, timeout)
            return 0

        with tempfile.TemporaryDirectory() as directory, patch.object(SIMULATOR, "OUTPUT", Path(directory)), \
                patch.object(SIMULATOR, "capture", side_effect=capture), patch.object(SIMULATOR, "report"):
            self.assertEqual(SIMULATOR.run_attempt(1), "unverified")
        self.assertFalse(any(command[0] == "xcodebuild" for command in commands))
        self.assertEqual([command[2] for command in commands[-2:]], ["shutdown", "delete"])


if __name__ == "__main__":
    unittest.main()
