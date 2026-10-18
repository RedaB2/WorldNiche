#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/worldniche-social-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
cp "$project_dir"/WorldNiche/Resources/{countries,insights}.json "$check_dir/"
swiftc -swift-version 6 \
  "$project_dir/WorldNiche/Models/Country.swift" \
  "$project_dir/WorldNiche/Models/DiscoveryJournal.swift" \
  "$project_dir/WorldNiche/Models/Social/SocialModels.swift" \
  "$project_dir/WorldNiche/Services/CultureTopicDiscovery.swift" \
  "$project_dir/WorldNiche/Services/LiveCultureService.swift" \
  "$project_dir/WorldNiche/Services/Social/SocialAPI.swift" \
  "$project_dir/WorldNiche/Services/Social/AvatarPhotoFiles.swift" \
  "$project_dir/WorldNiche/Services/Social/SocialStore.swift" \
  "$project_dir/Tests/SocialChecks.swift" -o "$check_dir/social-checks"
TMPDIR="$check_dir/" "$check_dir/social-checks" "$@"
