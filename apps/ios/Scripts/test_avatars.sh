#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/worldniche-avatar-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 \
  "$project_dir/WorldNiche/Models/Country.swift" \
  "$project_dir/WorldNiche/Models/DiscoveryJournal.swift" \
  "$project_dir/WorldNiche/Models/Social/SocialModels.swift" \
  "$project_dir/WorldNiche/Services/Social/AvatarPhotoFiles.swift" \
  "$project_dir/WorldNiche/Services/Social/SocialAPI.swift" \
  "$project_dir/Tests/AvatarAPIChecks.swift" \
  "$project_dir/WorldNiche/Services/Social/AvatarPhotoProcessor.swift" \
  "$project_dir/Tests/AvatarChecks.swift" -o "$check_dir/avatar-checks"
"$check_dir/avatar-checks"
