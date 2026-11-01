#!/usr/bin/env python3
"""Run built UI tests on a ready simulator; retry only the observed XCTest startup stall."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

OUTPUT = Path("outputs/ci/simulator")
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
DEVICE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"


def classify(code, summary, log):
    if (code == 0 and summary.get("result") == "Passed"
            and summary.get("passedTests", 0) >= 9 and summary.get("failedTests") == 0
            and summary.get("skippedTests") == 0 and not summary.get("testFailures")):
        return "passed"
    failures = summary.get("testFailures", [])
    # A real test starting is an absolute veto, even if XCTest also reports a stall.
    started = re.search(r"Test Case .+ started\.", log)
    if (code != 0 and not started and summary.get("passedTests") == 0
            and summary.get("skippedTests") == 0 and summary.get("failedTests") == 1
            and summary.get("totalTestCount") == 1 and len(failures) == 1):
        failure = failures[0]
        if (re.fullmatch(r"WorldNiche-Runner \(\d+\) encountered an error", failure.get("testIdentifierString", ""))
                and "operation never finished bootstrapping" in failure.get("failureText", "")
                and "-[XCTWaiter(StallHandling) handleStalledWait:]" in failure.get("failureText", "")):
            return "runner-startup"
    return "test-failure" if failures else "unverified"


def report(message, level=None):
    print(f"::{level}::{message}" if level else message, flush=True)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write(message + "\n\n")


def capture(command, path, timeout, check=True):
    print("+ " + " ".join(map(str, command)), flush=True)
    with path.open("w") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
    print(path.read_text(errors="replace"), flush=True)
    if check and result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); see {path}")
    return result.returncode


def check_environment():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    capture(["xcodebuild", "-version"], OUTPUT / "xcode.txt", 30)
    capture(["xcrun", "simctl", "list", "runtimes", "--json"], OUTPUT / "runtimes.json", 60)
    runtimes = json.loads((OUTPUT / "runtimes.json").read_text())["runtimes"]
    if not any(item["identifier"] == RUNTIME and item.get("isAvailable") for item in runtimes):
        raise RuntimeError(f"Required simulator runtime is unavailable: {RUNTIME}. Update the reviewed CI pin.")


def run_attempt(number):
    directory = OUTPUT / f"attempt-{number}"
    directory.mkdir(parents=True, exist_ok=False)
    device_id = None
    phase = "simulator setup"
    bundle = directory / "tests.xcresult"
    try:
        capture(["xcrun", "simctl", "create", f"WorldNiche-CI-{number}", DEVICE, RUNTIME],
                directory / "device.txt", 60)
        device_id = (directory / "device.txt").read_text().strip()
        capture(["xcrun", "simctl", "boot", device_id], directory / "boot.log", 60)
        capture(["xcrun", "simctl", "bootstatus", device_id, "-b"], directory / "bootstatus.log", 180)
        capture(["xcrun", "simctl", "io", device_id, "screenshot", str(directory / "ready.png")],
                directory / "readiness.log", 30)
        phase = "UI test execution"
        code = capture([
            "xcodebuild", "test-without-building",
            "-project", "apps/ios/WorldNiche.xcodeproj", "-scheme", "WorldNiche",
            "-derivedDataPath", "outputs/ci/DerivedData",
            "-destination", f"platform=iOS Simulator,id={device_id}",
            "-parallel-testing-enabled", "NO", "-resultBundlePath", str(bundle),
            "-only-testing:WorldNicheUITests/ProfileSetupUITests",
            "-only-testing:WorldNicheUITests/JournalUITests", "CODE_SIGNING_ALLOWED=NO",
        ], directory / "xcodebuild.log", 1200, check=False)
        phase = "test result verification"
        capture(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle), "--compact"],
                directory / "summary.json", 60)
        summary = json.loads((directory / "summary.json").read_text())
        verdict = classify(code, summary, (directory / "xcodebuild.log").read_text(errors="replace"))
        report(f"Attempt {number}: {verdict}; {summary.get('passedTests', 0)} passed, "
               f"{summary.get('failedTests', 0)} failed, {summary.get('skippedTests', 0)} skipped.")
        return verdict
    except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as error:
        report(f"Could not complete {phase}: {error}. No automatic retry; inspect simulator-results.", "error")
        return "unverified"
    finally:
        # Only touch the disposable simulator created by this attempt.
        if device_id:
            for action in ("shutdown", "delete"):
                try:
                    capture(["xcrun", "simctl", action, device_id], directory / f"{action}.log", 60, check=False)
                except (OSError, subprocess.TimeoutExpired) as error:
                    report(f"Simulator cleanup {action} failed: {error}", "warning")


def run_tests(attempt=run_attempt):
    for number in (1, 2):
        verdict = attempt(number)
        if verdict == "passed":
            report("All nine or more selected UI tests passed."
                   + (" Recovered from the known XCTest startup stall on a fresh simulator." if number == 2 else ""))
            return 0
        if verdict == "runner-startup" and number == 1:
            report("XCTest stalled before any test began. Preserving attempt 1 and retrying once on a fresh simulator.", "warning")
            continue
        message = ("XCTest startup failed twice; the runner could not validate this build."
                   if verdict == "runner-startup" else
                   "UI validation failed. Application failures and unknown errors are not retried.")
        report(message + " See the simulator-results artifact.", "error")
        return 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--check-environment"]:
        try:
            check_environment()
        except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as error:
            report(f"CI environment setup failed: {error}", "error")
            sys.exit(1)
    elif not sys.argv[1:]:
        sys.exit(run_tests())
    else:
        sys.exit("Usage: python3 scripts/ci_simulator.py [--check-environment]")
