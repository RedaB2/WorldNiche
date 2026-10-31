#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/worldniche-globe-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 \
  "$project_dir/WorldNiche/Models/GlobeInteraction.swift" \
  "$project_dir/Tests/GlobeChecks.swift" -o "$check_dir/globe-checks"
"$check_dir/globe-checks"
