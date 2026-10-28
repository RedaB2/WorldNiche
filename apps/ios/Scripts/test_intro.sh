#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/worldniche-intro-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 \
  "$project_dir/WorldNiche/Models/IntroProgress.swift" \
  "$project_dir/Tests/IntroChecks.swift" -o "$check_dir/intro-checks"
"$check_dir/intro-checks"
