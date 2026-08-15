#!/usr/bin/env bash
# Contract tests for scripts/sensitive-paths.sh (design D2 security overlay).

sp_run() { # newline-path-list -> sets OUT/RC
  OUT=$(printf '%s\n' "$1" | bash "$ITP_SCRIPTS/sensitive-paths.sh" 2>/dev/null)
  RC=$?
  export OUT RC
}

test_sp_true_positives() {
  sp_run "src/auth/login.py
db/migrations/001_users.sql
config/.env
lib/crypto/aes.go
services/payment/charge.rb
deploy/id_rsa"
  assert_key "$OUT" SENSITIVE true
  assert_contains "$OUT" "src/auth/login.py"
  assert_contains "$OUT" "config/.env"
}

test_sp_false_positives_do_not_trip() {
  # authors.py / thesaurus.md / payment_ui_copy.md must NOT match (segment/stem-exact).
  sp_run "docs/authors.py
content/thesaurus.md
ui/payment_ui_copy.md
src/authService.notes.md
README.md"
  assert_key "$OUT" SENSITIVE false
}

test_sp_env_variants() {
  sp_run ".env.production"
  assert_key "$OUT" SENSITIVE true
}

test_sp_auth_as_filename_stem() {
  sp_run "src/services/auth.ts"
  assert_key "$OUT" SENSITIVE true
}

test_sp_empty_input() {
  sp_run ""
  assert_key "$OUT" SENSITIVE false
  assert_key "$OUT" MATCHED ""
}

test_sp_case_insensitive() {
  sp_run "src/Auth/Login.java"
  assert_key "$OUT" SENSITIVE true
}

test_sp_json() {
  sp_run "src/auth/x.py"
  # re-run with --json
  OUT=$(printf '%s\n' "src/auth/x.py" | bash "$ITP_SCRIPTS/sensitive-paths.sh" --json 2>/dev/null)
  assert_contains "$OUT" '"SENSITIVE":"true"'
}

test_sp_unterminated_last_line() {
  # A path with NO trailing newline (e.g. a raw `git diff` tail) must still be
  # classified - the read loop keeps the final unterminated line.
  OUT=$(printf '%s' "src/auth/login.py" | bash "$ITP_SCRIPTS/sensitive-paths.sh" 2>/dev/null)
  assert_key "$OUT" SENSITIVE true
  assert_contains "$OUT" "src/auth/login.py"
}

# Regression: Alembic's layout has no segment named "migration" anywhere, so a
# schema change under alembic/versions/ used to slip past the security overlay.
test_sp_alembic_versions_is_sensitive() {
  sp_run "alembic/versions/8f2c_add_users_table.py"
  assert_key "$OUT" SENSITIVE true
}

# Both fixtures deliberately avoid `.sql`: that extension is sensitive on its own,
# so a `db/flyway/V3__x.sql` fixture stays green even with `flyway` deleted from the
# word list and proves nothing about the word it is named for. Flyway's Java-based
# migrations are the case that actually needs the segment to match.
test_sp_other_migration_tools_are_sensitive() {
  sp_run "db/flyway/V3__AddColumn.java"
  assert_key "$OUT" SENSITIVE true
  sp_run "liquibase/changelog.xml"
  assert_key "$OUT" SENSITIVE true
}

# The added words must stay precise: an unrelated `versions` directory is not a
# migration, and neither is prose that merely mentions one.
test_sp_bare_versions_dir_is_not_sensitive() {
  sp_run "docs/versions/changelog.md"
  assert_key "$OUT" SENSITIVE false
}

# Regression: Rails/goose/dbmate use db/migrate (singular), which matched none of
# the migration words, so the most common layout of all stayed invisible.
test_sp_rails_db_migrate_is_sensitive() {
  sp_run "db/migrate/20260809120000_add_api_tokens.rb"
  assert_key "$OUT" SENSITIVE true
}

# -- --base: the script collects the changed-file list itself --------------------

# sp_repo - a repo on `work` cut from `main`, used by the --base tests below.
sp_repo() {
  local dir
  dir=$(init_repo "$TEST_TMPDIR/sp")
  git -C "$dir" switch -qc work
  printf '%s' "$dir"
}

test_sp_base_sees_a_committed_change() {
  local d
  d=$(sp_repo)
  mkdir -p "$d/src/auth"
  printf 'x\n' >"$d/src/auth/login.py"
  git -C "$d" add src/auth/login.py
  git -C "$d" commit -qm "add auth"
  cd "$d" || fail "cd failed"
  run_script sensitive-paths.sh --base main
  assert_key "$OUT" SENSITIVE true
  assert_contains "$OUT" "src/auth/login.py"
}

# The overlay runs at Step 7, before the Step 9 commit, so an edit sitting in the
# working tree is the common case, not the exception.
test_sp_base_sees_uncommitted_and_untracked_work() {
  local d
  d=$(sp_repo)
  mkdir -p "$d/lib/crypto"
  printf 'v1\n' >"$d/lib/crypto/aes.go"
  git -C "$d" add lib/crypto/aes.go
  git -C "$d" commit -qm "seed crypto"
  printf 'v2\n' >"$d/lib/crypto/aes.go"       # tracked, edited, not committed
  printf 'k\n' >"$d/deploy_id_rsa_backup.pem" # untracked
  cd "$d" || fail "cd failed"
  run_script sensitive-paths.sh --base main
  assert_key "$OUT" SENSITIVE true
  assert_contains "$OUT" "lib/crypto/aes.go"
  assert_contains "$OUT" "deploy_id_rsa_backup.pem"
}

# The whole reason the collection moved into the script: a two-dot diff against a
# base that moved on reports files this branch never touched, and the model was
# being asked to remember the difference while typing the command by hand.
test_sp_base_ignores_work_that_landed_on_the_base() {
  local d
  d=$(sp_repo)
  printf 'note\n' >"$d/notes.md"
  git -C "$d" add notes.md
  git -C "$d" commit -qm "branch work"
  git -C "$d" switch -q main
  mkdir -p "$d/src/auth"
  printf 'y\n' >"$d/src/auth/other.py"
  git -C "$d" add src/auth/other.py
  git -C "$d" commit -qm "unrelated auth change on the base"
  git -C "$d" switch -q work
  cd "$d" || fail "cd failed"
  run_script sensitive-paths.sh --base main
  assert_key "$OUT" SENSITIVE false
  assert_not_contains "$OUT" "src/auth/other.py"
}

test_sp_base_reports_each_path_once() {
  local d
  d=$(sp_repo)
  mkdir -p "$d/src/auth"
  printf 'v1\n' >"$d/src/auth/login.py"
  git -C "$d" add src/auth/login.py
  git -C "$d" commit -qm "add auth"
  printf 'v2\n' >"$d/src/auth/login.py" # same file, committed AND edited
  cd "$d" || fail "cd failed"
  run_script sensitive-paths.sh --base main
  local n
  n=$(printf '%s' "$OUT" | grep -c 'src/auth/login.py,src/auth/login.py' || true)
  [ "$n" = 0 ] || fail "MATCHED lists the same path twice: $OUT"
}

# A base that does not resolve must DEGRADE, never report a clean scan: the overlay
# only ever adds a review pass, so a silent SENSITIVE=false is indistinguishable from
# a real green and skips the security review outright.
test_sp_base_with_an_unresolvable_ref_degrades() {
  local d
  d=$(sp_repo)
  cd "$d" || fail "cd failed"
  run_script sensitive-paths.sh --base no/such/ref
  assert_rc 4 "$RC"
  assert_key "$OUT" DEGRADED_REASON base-unresolvable
  assert_not_contains "$OUT" "SENSITIVE=false"
}

test_sp_base_outside_a_repo_degrades() {
  mkdir -p "$TEST_TMPDIR/norepo"
  cd "$TEST_TMPDIR/norepo" || fail "cd failed"
  run_script sensitive-paths.sh --base main
  assert_rc 4 "$RC"
  assert_key "$OUT" DEGRADED_REASON not-a-git-repo
}
