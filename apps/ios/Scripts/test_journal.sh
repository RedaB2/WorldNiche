#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/worldniche-journal-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
cp "$project_dir"/WorldNiche/Resources/{countries,insights}.json "$check_dir/"
swiftc -swift-version 6 "$project_dir/WorldNiche/Models/Country.swift" "$project_dir/WorldNiche/Models/DiscoveryJournal.swift" "$project_dir/Tests/JournalChecks.swift" -o "$check_dir/journal-checks"
"$check_dir/journal-checks"
