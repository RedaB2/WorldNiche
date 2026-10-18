#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/worldniche-culture.XXXXXX")"
trap 'rm -rf "$CHECK_DIRECTORY"' EXIT
cp "$PROJECT_ROOT"/WorldNiche/Resources/{countries,insights,culture-topics}.json "$CHECK_DIRECTORY/"
swiftc -swift-version 6 -strict-concurrency=complete -D WORLDNICHE_TESTING \
  "$PROJECT_ROOT/WorldNiche/Models/Country.swift" \
  "$PROJECT_ROOT/WorldNiche/Services/CultureTopicDiscovery.swift" \
  "$PROJECT_ROOT/WorldNiche/Services/LiveCultureService.swift" \
  "$PROJECT_ROOT/Tests/LiveCultureChecks.swift" \
  "$PROJECT_ROOT/Tests/CultureDiscoveryChecks.swift" \
  -o "$CHECK_DIRECTORY/live-culture-checks"
"$CHECK_DIRECTORY/live-culture-checks" "$@"
