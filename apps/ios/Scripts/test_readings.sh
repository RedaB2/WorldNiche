#!/usr/bin/env bash
set -euo pipefail
ios="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/worldniche-readings.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cp "$ios"/WorldNiche/Resources/{countries,historical-facts}.json "$scratch/"
swiftc -swift-version 6 "$ios/WorldNiche/Models/Country.swift" "$ios/WorldNiche/Services/HistoricalFactCatalog.swift" \
    "$ios/Tests/FactPublicationChecks.swift" "$ios/Tests/CountryReadingChecks.swift" -o "$scratch/checks"
"$scratch/checks"
