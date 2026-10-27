#!/bin/sh
# Creates and destroys an isolated local cluster. Does not accept a remote URL.
set -eu
project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
pg_bin=${WORLDNICHE_PG_BIN:-}
if [ -z "$pg_bin" ] && command -v pg_config >/dev/null 2>&1; then
  pg_bin=$(pg_config --bindir)
fi
for command in initdb pg_ctl psql; do
  test -x "$pg_bin/$command" || { echo "Set WORLDNICHE_PG_BIN to an installed PostgreSQL bin directory." >&2; exit 1; }
done
scratch=$(mktemp -d /tmp/worldniche-db-tests.XXXXXX)
finish() {
  "$pg_bin/pg_ctl" -D "$scratch/data" stop -m fast >/dev/null 2>&1 || true
  rm -rf "$scratch"
}
trap finish EXIT HUP INT TERM
"$pg_bin/initdb" -D "$scratch/data" --locale=C --encoding=UTF8 --auth=trust -U wn_test >"$scratch/init.log"
"$pg_bin/pg_ctl" -D "$scratch/data" -l "$scratch/server.log" -o "-k $scratch -h '' -p 55433" start >/dev/null
"$pg_bin/psql" -h "$scratch" -p 55433 -U wn_test -d postgres -v ON_ERROR_STOP=1 -q \
  -f "$project_root/tests/bootstrap.sql" \
  -f "$project_root/tests/storage_bootstrap.sql" \
  -f "$project_root/supabase/migrations/202610170001_social.sql" \
  -f "$project_root/supabase/migrations/202610180003_profile_photos.sql" \
  -f "$project_root/tests/social_security.sql" \
  -f "$project_root/tests/avatar_security.sql" \
  -f "$project_root/supabase/migrations/202610180004_profile_moderation.sql" \
  -f "$project_root/tests/moderation_security.sql" \
  -f "$project_root/supabase/migrations/202610240005_automatic_profile_checks.sql" \
  -f "$project_root/supabase/migrations/202610240006_profile_check_disclosure.sql" \
  -f "$project_root/tests/automatic_moderation.sql" \
  -f "$project_root/tests/sharing_preferences.sql"
PGUSER=wn_test python3 "$project_root/tests/automatic_check_race.py" --psql "$pg_bin/psql" --socket "$scratch"
PGUSER=wn_test python3 "$project_root/tests/consent_race.py" --psql "$pg_bin/psql" --socket "$scratch"
PGUSER=wn_test python3 "$project_root/tests/invitation_race.py" --psql "$pg_bin/psql" --socket "$scratch"
"$pg_bin/psql" -h "$scratch" -p 55433 -U wn_test -d postgres -v ON_ERROR_STOP=1 -q \
  -f "$project_root/supabase/migrations/202610270007_moderation_abuse_limits.sql"
PGUSER=wn_test python3 "$project_root/tests/moderation_abuse.py" --psql "$pg_bin/psql" --socket "$scratch"
PGUSER=wn_test python3 "$project_root/tests/automatic_check_race.py" --psql "$pg_bin/psql" --socket "$scratch"
