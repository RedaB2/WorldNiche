#!/usr/bin/env python3
"""Reject ignored files in Git's index and keep the bundled service template blank."""
import json
from pathlib import Path
import subprocess
import sys


def check(root: Path) -> int:
    def git(*args: str) -> bytes:
        return subprocess.check_output(["git", *args], cwd=root)

    ignored = git("ls-files", "--cached", "--ignored", "--exclude-standard", "-z")
    private_paths = [path.decode() for path in ignored.split(b"\0") if path]
    if private_paths:
        print("FAIL: private or generated files are tracked in Git:", file=sys.stderr)
        for path in private_paths:
            print(f"  {path}", file=sys.stderr)
        print("Unstage these files and keep them local. No file contents were printed.", file=sys.stderr)
        return 1

    template = "apps/ios/WorldNiche/Resources/SocialConfiguration.json"
    try:
        config = json.loads(git("show", f":{template}"))
    except (subprocess.CalledProcessError, ValueError):
        print("FAIL: the tracked public service template is missing or invalid.", file=sys.stderr)
        return 1
    if config.get("serviceURL") != "" or config.get("publicAPIKey") != "" or config.get("appleSignInEnabled") is not False:
        print("FAIL: keep the tracked service template blank. Use SocialConfiguration.local.json.", file=sys.stderr)
        return 1
    print("PASS: no ignored files are tracked; the public service template is blank.")
    return 0


if __name__ == "__main__":
    raise SystemExit(check(Path(__file__).resolve().parents[1]))
