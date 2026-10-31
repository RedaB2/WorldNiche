#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-all}" in
  private)
    python3 scripts/check_private_files.py
    python3 -m unittest discover -s scripts/tests -p 'test_*.py'
    ;;
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
    for suite in globe intro journal avatars feeds live_culture social; do
      bash "apps/ios/Scripts/test_${suite}.sh"
    done
    ;;
  assets) python3 scripts/check_assets.py ;;
  all)
    for suite in private assets web backend swift; do bash scripts/check.sh "$suite"; done
    ;;
  *) echo "Usage: bash scripts/check.sh [private|assets|web|backend|swift|all]" >&2; exit 2 ;;
esac
