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
