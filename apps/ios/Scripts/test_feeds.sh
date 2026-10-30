#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/worldniche-feed-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
cp "$project_dir"/WorldNiche/Resources/{countries,insights,culture-topics,apple-music-storefronts,global-voices-feeds}.json "$check_dir/"
swiftc -swift-version 6 \
  "$project_dir/WorldNiche/Models/Country.swift" \
  "$project_dir/WorldNiche/Models/CountryFeed.swift" \
  "$project_dir/WorldNiche/Services/DiscoveryFeedService.swift" \
  "$project_dir/Tests/FeedChecks.swift" -o "$check_dir/feed-checks"
"$check_dir/feed-checks" "$@"
