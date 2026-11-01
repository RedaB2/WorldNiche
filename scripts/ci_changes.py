#!/usr/bin/env python3
"""Skip native CI only when every changed path is known to be non-native."""
import os
import subprocess

NON_NATIVE = ("apps/web/", "docs/", "marketing/", "metadata/")


def needs_native(paths):
    return not paths or any(not path.startswith(NON_NATIVE) for path in paths)


def detect(event, base, head, cwd=None):
    if event not in ("pull_request", "push") or not base or set(base) == {"0"}:
        return True
    # PRs use their merge base; pushes include every commit in the push.
    comparison = f"{base}{'...' if event == 'pull_request' else '..'}{head}"
    changed = subprocess.check_output(
        ["git", "diff", "--name-only", "--no-renames", "-z", comparison, "--"], cwd=cwd,
    ).decode().rstrip("\0").split("\0")
    return needs_native(changed)


if __name__ == "__main__":
    native = detect(os.environ["GITHUB_EVENT_NAME"], os.environ.get("BASE_SHA", ""), os.environ["HEAD_SHA"])
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"native={str(native).lower()}\n")
    message = "Native checks required." if native else "Native checks skipped: only website, documentation or listing files changed."
    print(message)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(message + "\n")
