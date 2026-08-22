#!/usr/bin/env bash
# Tests for wt-sync depth-matching patterns. Dependency-free (bash + git + coreutils).
# Builds a throwaway git repo + linked worktree, runs wt-sync, asserts results.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
WT_SYNC="$script_dir/../bin/wt-sync"
[[ -x "$WT_SYNC" ]] || { echo "FAIL: wt-sync not found/executable at $WT_SYNC" >&2; exit 1; }

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; fails=$((fails + 1)); }
assert_file()   { [[ -f "$1" ]] && pass "$2" || fail "$2 (missing: $1)"; }
assert_absent() { [[ ! -e "$1" ]] && pass "$2" || fail "$2 (unexpected: $1)"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
wt="$tmp/wt"

# ---- fixture --------------------------------------------------------------
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test

cat >"$repo/.gitignore" <<'EOF'
.env
secret.txt
node_modules/
config/
EOF

mkdir -p "$repo/a/b" "$repo/deep" "$repo/config" "$repo/node_modules/pkg"
printf 'root\n'  >"$repo/.env"
printf 'a\n'     >"$repo/a/.env"
printf 'ab\n'    >"$repo/a/b/.env"
printf 'r\n'     >"$repo/secret.txt"
printf 'd\n'     >"$repo/deep/secret.txt"
printf 'ini\n'   >"$repo/config/local.ini"
printf 'idx\n'   >"$repo/node_modules/pkg/index.js"
printf 'nmenv\n' >"$repo/node_modules/pkg/.env"
printf 'keep\n'  >"$repo/keep.txt"

git -C "$repo" add .gitignore keep.txt
git -C "$repo" commit -qm init

cat >"$repo/.worktreesync" <<'EOF'
copy .env
clone node_modules
copy /secret.txt
copy config/local.ini
copy nope.env
EOF

git -C "$repo" worktree add -q "$wt" -b wt HEAD

# ---- run ------------------------------------------------------------------
set +e
run1=$("$WT_SYNC" --to "$wt" --from "$repo" 2>&1); rc=$?
set -e
[[ $rc -eq 0 ]] && pass "run exits 0" || fail "run exit $rc: $run1"

# ---- assertions -----------------------------------------------------------
assert_file   "$wt/.env"                      "depth: root .env copied"
assert_file   "$wt/a/.env"                    "depth: a/.env copied"
assert_file   "$wt/a/b/.env"                  "depth: a/b/.env copied"
assert_file   "$wt/node_modules/pkg/index.js" "clone: node_modules cloned"
assert_file   "$wt/secret.txt"                "anchor: /secret.txt copied"
assert_absent "$wt/deep/secret.txt"           "anchor: deep/secret.txt NOT copied"
assert_file   "$wt/config/local.ini"          "literal: interior path copied"

grep -q 'skip nope.env (no matches)' <<<"$run1" \
  && pass "zero-match: nope.env skipped" \
  || fail "zero-match: expected 'skip nope.env (no matches)' in output"

grep -q "copied $wt/node_modules/pkg/.env" <<<"$run1" \
  && fail "collapse: node_modules/.env copied individually" \
  || pass "collapse: node_modules/.env not copied individually"

# ---- idempotency ----------------------------------------------------------
run2=$("$WT_SYNC" --to "$wt" --from "$repo" 2>&1)
grep -qE 'copied|cloned|symlinked' <<<"$run2" \
  && fail "idempotent: second run changed things: $run2" \
  || pass "idempotent: second run made no changes"

# ---- summary --------------------------------------------------------------
if [[ "$fails" -gt 0 ]]; then
  echo "$fails assertion(s) failed" >&2
  exit 1
fi
echo "all assertions passed"
