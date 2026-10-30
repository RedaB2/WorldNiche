#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-all}" in
  web)
    npm --prefix apps/web test
    npm --prefix apps/web run build
    npm --prefix apps/web run validate
    ;;
  backend)
    npm --prefix backend ci --ignore-scripts
    npm --prefix backend run test:edge
    npm --prefix backend run test:invites
    npm --prefix backend run test:database
    ;;
  swift)
    for suite in intro journal avatars feeds live_culture social; do
      bash "apps/ios/Scripts/test_${suite}.sh"
    done
    ;;
  assets) python3 scripts/check_assets.py ;;
  all)
    for suite in assets web backend swift; do bash scripts/check.sh "$suite"; done
    ;;
  *) echo "Usage: bash scripts/check.sh [assets|web|backend|swift|all]" >&2; exit 2 ;;
esac
