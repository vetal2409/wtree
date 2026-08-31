#!/usr/bin/env bash
# Tests for wt's safety classification (wt ls / wt rm --merged) and for base
# selection on `wt open` (--fresh, -b <ref>, -b .). Dependency-free (bash + git
# + coreutils): builds a throwaway origin + clone + worktrees, then asserts on
# wt's own output.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
WT="$script_dir/../bin/wt"
[[ -x "$WT" ]] || {
  echo "FAIL: wt not found/executable at $WT" >&2
  exit 1
}

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}
assert_eq() {
  [[ "$1" == "$2" ]] && pass "$3" || fail "$3 (want '$2', got '$1')"
}
assert_match() {
  grep -Eq -- "$2" <<<"$1" && pass "$3" || fail "$3 (no match for '$2' in: $1)"
}
assert_no_match() {
  grep -Eqv -- "$2" <<<"$1" && ! grep -Eq -- "$2" <<<"$1" &&
    pass "$3" || fail "$3 (unexpected match for '$2')"
}
assert_dir() { [[ -d "$1" ]] && pass "$2" || fail "$2 (missing dir: $1)"; }
assert_no_dir() { [[ ! -d "$1" ]] && pass "$2" || fail "$2 (dir still there: $1)"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export WT_ROOT="$tmp/worktrees"
main="$tmp/main"
wt() { "$WT" -C "$main" "$@"; }
# Names of the worktrees wt considers removable, one per line, sorted.
safe_names() { wt ls --safe | awk '/safe to remove/ { print $1 }' | sort; }

# ---- fixture: bare origin + clone + one commit ----------------------------
git init -q --bare -b master "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$main" 2>/dev/null
git -C "$main" config user.email test@example.com
git -C "$main" config user.name test
printf '.env\n' >"$main/.gitignore"
printf 'v1\n' >"$main/tracked.txt"
git -C "$main" add .gitignore tracked.txt
git -C "$main" commit -qm init
git -C "$main" push -q -u origin master
git -C "$main" remote set-head origin -a >/dev/null

# ---- fixture: one worktree per classification ----------------------------
for n in merged ahead dirty untracked ignored; do
  wt open "$n" >/dev/null 2>&1
done

# ahead: a commit that never reaches master
git -C "$WT_ROOT/main/ahead" config user.email test@example.com
git -C "$WT_ROOT/main/ahead" config user.name test
printf 'v2\n' >"$WT_ROOT/main/ahead/tracked.txt"
git -C "$WT_ROOT/main/ahead" commit -qam "work"

# dirty: a modified tracked file
printf 'local\n' >"$WT_ROOT/main/dirty/tracked.txt"

# untracked: a new non-ignored file — real work that a --force remove would eat
printf 'scratch\n' >"$WT_ROOT/main/untracked/notes.md"

# ignored: what wt-sync copies in. Gitignored, so it must NOT block removal.
printf 'SECRET=1\n' >"$WT_ROOT/main/ignored/.env"

# ---- classification ------------------------------------------------------
listing=$(wt ls)
assert_match "$listing" '^main +master .* \(main worktree\)' "main worktree is labelled, never safe"
assert_match "$listing" '^ahead .* ahead 1' "branch with an unmerged commit shows ahead 1"
assert_match "$listing" '^ahead .* unpushed 1' "never-pushed commit shows as unpushed"
assert_match "$listing" '^dirty .* dirty 1' "modified tracked file shows dirty 1"
assert_match "$listing" '^untracked .* dirty 1' "untracked non-ignored file counts as dirty"
assert_match "$listing" '^merged .* safe to remove' "merged clean worktree is safe"
assert_match "$listing" '^ignored .* safe to remove' "gitignored payload does not block removal"
assert_match "$listing" "2 removable" "footer counts removable worktrees"

assert_eq "$(safe_names | tr '\n' ' ')" "ignored merged " "--safe lists exactly the removable worktrees"

# ---- rm --merged ---------------------------------------------------------
dry=$(wt rm --merged --dry-run 2>&1)
assert_match "$dry" 'These 2 worktrees' "dry run reports both candidates"
assert_match "$dry" 'nothing removed' "dry run says it changed nothing"
assert_dir "$WT_ROOT/main/merged" "dry run leaves the worktree in place"

out=$(wt rm --merged --yes 2>&1)
assert_match "$out" 'done: 2 of 2 removed' "rm --merged removes both candidates"
assert_no_dir "$WT_ROOT/main/merged" "merged worktree is gone"
assert_no_dir "$WT_ROOT/main/ignored" "ignored-only worktree is gone"
assert_dir "$WT_ROOT/main/ahead" "unmerged worktree is kept"
assert_dir "$WT_ROOT/main/dirty" "dirty worktree is kept"
assert_dir "$WT_ROOT/main/untracked" "worktree with untracked work is kept"

branches=$(git -C "$main" branch --format='%(refname:short)' | tr '\n' ' ')
assert_no_match "$branches" '(^| )merged( |$)' "merged branch deleted with its worktree"
assert_match "$branches" '(^| )ahead( |$)' "unmerged branch kept"

nothing=$(wt rm --merged 2>&1)
assert_match "$nothing" 'nothing to remove' "second run finds nothing and does not prompt"

# ---- open --fresh -------------------------------------------------------
git clone -q "$tmp/origin.git" "$tmp/other"
git -C "$tmp/other" config user.email test@example.com
git -C "$tmp/other" config user.name test
printf 'upstream\n' >"$tmp/other/new.txt"
git -C "$tmp/other" add new.txt
git -C "$tmp/other" commit -qm upstream
git -C "$tmp/other" push -q origin master

before=$(git -C "$main" rev-parse master)
wt open --fresh feature >/dev/null 2>&1
assert_dir "$WT_ROOT/main/feature" "--fresh created the worktree"
[[ -f "$WT_ROOT/main/feature/new.txt" ]] &&
  pass "--fresh based the new branch on freshly fetched origin/master" ||
  fail "--fresh did not pick up the upstream commit"
[[ "$(git -C "$main" rev-parse master)" != "$before" ]] &&
  pass "--fresh fast-forwarded master in the main worktree" ||
  fail "--fresh left master behind"

# ---- fetch age footer (regression: cross-platform stat in fetch_age) ----
# `--fresh` above ran `git fetch`, so FETCH_HEAD now exists; this exercises
# the BSD-vs-GNU `stat` branch in `fetch_age`, whose age computation went
# silent-garbage on Linux (GNU `stat -f` means something else entirely).
stderr=$(wt ls 2>&1 >/dev/null)
assert_eq "$stderr" "" "wt ls prints nothing to stderr after a fetch"
listing=$(wt ls)
assert_match "$listing" 'fetched [0-9]+[smhdwy] ago' "footer reports fetch age after --fresh"

# ---- flag guard rails ---------------------------------------------------
set +e
err=$(wt rm --merged feature 2>&1); rc=$?
set -e
[[ $rc -ne 0 ]] && pass "wt rm --merged with a name is refused" ||
  fail "wt rm --merged accepted a name (rc=$rc)"
assert_match "$err" 'takes no name' "refusal explains the conflict"

set +e
err=$(wt ls -b master 2>&1); rc=$?
set -e
[[ $rc -ne 0 ]] && pass "-b on a non-open subcommand is refused" ||
  fail "wt ls -b silently ignored the flag"

set +e
err=$(wt ls --fresh 2>&1); rc=$?
set -e
[[ $rc -ne 0 ]] && pass "--fresh on a non-open subcommand is refused" ||
  fail "wt ls --fresh silently ignored the flag"

# ---- rm -i (interactive picker) -----------------------------------------
# A stand-in for fzf: records the rows it was offered, optionally runs the real
# --preview string against one of them, and selects the rows named in
# $FAKE_PICK. Exercises everything in `wt rm -i` except fzf's own UI.
picker="$tmp/fake-picker"
cat >"$picker" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
cat >"$FAKE_ROWS"
if [[ -n "${FAKE_PREVIEW_FOR:-}" ]]; then
  prev=""
  while [[ $# -gt 0 ]]; do
    [[ "$1" == "--preview" ]] && prev="$2"
    shift
  done
  # fzf substitutes {2} (the worktree path) before handing the string to sh.
  printf '%s' "${prev//\{2\}/'$FAKE_PREVIEW_FOR'}" | sh >"$FAKE_PREVIEW_OUT" 2>&1
fi
[[ -n "${FAKE_PICK:-}" ]] || exit 130
for want in $FAKE_PICK; do
  awk -F'\t' -v w="$want" '$5 == w' "$FAKE_ROWS"
done
FAKE
chmod +x "$picker"
export WT_FZF="$picker" FAKE_ROWS="$tmp/rows" FAKE_PREVIEW_OUT="$tmp/preview"

# What the picker is offered, and what the preview says about it.
FAKE_PREVIEW_FOR="$WT_ROOT/main/ahead" wt rm -i >/dev/null 2>&1 || true
offered=$(awk -F'\t' '{ print $5 }' "$FAKE_ROWS" | sort | tr '\n' ' ')
assert_eq "$offered" "ahead dirty feature untracked " "picker offers every removable worktree"
assert_no_match "$offered" '(^| )main( |$)' "picker never offers the main worktree"
preview=$(cat "$tmp/preview")
assert_match "$preview" '1 commit\(s\) not in master' "preview counts unmerged commits"
assert_match "$preview" 'work' "preview shows the commit subject"

FAKE_PREVIEW_FOR="$WT_ROOT/main/dirty" wt rm -i >/dev/null 2>&1 || true
preview=$(cat "$tmp/preview")
assert_match "$preview" 'fully merged into master' "preview reports a merged branch"
assert_match "$preview" '1 local change\(s\) — these are destroyed' "preview warns about local changes"
assert_match "$preview" 'tracked.txt' "preview lists the changed file"

# Nothing marked (picker exits 130, as fzf does on ESC).
out=$(wt rm -i 2>&1 || true)
assert_match "$out" 'nothing selected' "cancelling the picker removes nothing"
assert_dir "$WT_ROOT/main/dirty" "cancelled picker left the worktree alone"

# Dry run on a risky pick.
out=$(FAKE_PICK=dirty wt rm -i --dry-run 2>&1)
assert_match "$out" '1 local change\(s\) DESTROYED' "dry run spells out what is at stake"
assert_match "$out" 'dry run: nothing removed' "dry run says it changed nothing"
assert_dir "$WT_ROOT/main/dirty" "dry run left the worktree in place"

# The real thing: one safe worktree and one carrying unpushed commits.
out=$(FAKE_PICK="feature ahead" wt rm -i --yes 2>&1)
assert_match "$out" 'done: 2 of 2 removed' "picker removes every marked worktree"
assert_no_dir "$WT_ROOT/main/feature" "marked safe worktree is gone"
assert_no_dir "$WT_ROOT/main/ahead" "marked worktree with local commits is gone"
assert_dir "$WT_ROOT/main/dirty" "unmarked worktree is untouched"
branches=$(git -C "$main" branch --format='%(refname:short)' | tr '\n' ' ')
assert_no_match "$branches" '(^| )feature( |$)' "merged branch of a removed worktree is deleted"
assert_match "$branches" '(^| )ahead( |$)' "unmerged branch survives so its commits stay recoverable"

# Standing inside a worktree keeps it out of the picker.
(cd "$WT_ROOT/main/dirty" && wt rm -i >/dev/null 2>&1) || true
offered=$(awk -F'\t' '{ print $5 }' "$FAKE_ROWS" | sort | tr '\n' ' ')
assert_eq "$offered" "untracked " "the worktree you are standing in is not offered"

# ---- rm -i guard rails --------------------------------------------------
set +e
err=$(wt rm -i dirty 2>&1); rc=$?
set -e
[[ $rc -ne 0 ]] && pass "wt rm -i with a name is refused" || fail "wt rm -i accepted a name"
assert_match "$err" 'takes no name' "refusal explains the conflict"

set +e
err=$(wt rm -i --merged 2>&1); rc=$?
set -e
[[ $rc -ne 0 ]] && pass "wt rm -i --merged is refused" || fail "-i and --merged were combined"

set +e
err=$(WT_FZF=wt-no-such-picker wt rm -i 2>&1); rc=$?
set -e
[[ $rc -ne 0 ]] && pass "a missing picker is a clear error" || fail "missing picker was ignored"
assert_match "$err" 'WT_FZF' "the error names the WT_FZF escape hatch"

# ---- base selection ------------------------------------------------------
# --fresh and -b are orthogonal: --fresh refreshes the repo from origin, -b
# picks what the new branch starts from. Both together must do both.
first=$(git -C "$main" rev-parse master^)
out=$(wt open --fresh -b "$first" pinned 2>&1)
assert_dir "$WT_ROOT/main/pinned" "--fresh with -b creates the worktree"
assert_match "$out" 'fetched origin/master' "--fresh still fetches when -b is given"
assert_eq "$(git -C "$WT_ROOT/main/pinned" rev-parse HEAD)" "$first" \
  "-b wins over --fresh's origin/<default> when both are given"
assert_match "$out" "based on $first" "the log names the base actually used"
[[ ! -f "$WT_ROOT/main/pinned/new.txt" ]] &&
  pass "-b pinned the branch behind the fetched upstream commit" ||
  fail "-b was ignored in favour of origin/master"

# -b . means "whatever the repo context is on right now".
git -C "$WT_ROOT/main/pinned" config user.email test@example.com
git -C "$WT_ROOT/main/pinned" config user.name test
printf 'sidework\n' >"$WT_ROOT/main/pinned/side.txt"
git -C "$WT_ROOT/main/pinned" add side.txt
git -C "$WT_ROOT/main/pinned" commit -qm side
tip=$(git -C "$WT_ROOT/main/pinned" rev-parse HEAD)

out=$(cd "$WT_ROOT/main/pinned" && "$WT" open -b . stacked 2>&1)
assert_eq "$(git -C "$WT_ROOT/main/stacked" rev-parse HEAD)" "$tip" \
  "-b . bases the new branch on the current worktree's tip"
assert_match "$out" 'based on pinned' "-b . resolves to the branch name when attached"

# Detached HEAD has no branch name to borrow, so it falls back to the commit.
git -C "$WT_ROOT/main/pinned" checkout -q --detach
det=$(git -C "$WT_ROOT/main/pinned" rev-parse HEAD)
(cd "$WT_ROOT/main/pinned" && "$WT" open -b . detached-base >/dev/null 2>&1)
assert_eq "$(git -C "$WT_ROOT/main/detached-base" rev-parse HEAD)" "$det" \
  "-b . falls back to the SHA on a detached HEAD"

# -b . follows the repo context, not the shell: -C wins.
(cd "$WT_ROOT/main/dirty" && "$WT" -C "$main" open -b . from-ctx >/dev/null 2>&1)
assert_eq "$(git -C "$WT_ROOT/main/from-ctx" rev-parse HEAD)" \
  "$(git -C "$main" rev-parse HEAD)" "-b . resolves against -C, not the cwd"

# --- version -----------------------------------------------------------------
# Derived from wt's own WT_VERSION constant, not hardcoded: a release bumps
# that constant, and a literal here would fail every release after 0.1.0.
ver=$(sed -n 's/^WT_VERSION="\(.*\)"$/\1/p' "$WT")
assert_match "$ver" '^[0-9]+\.[0-9]+\.[0-9]+$' "WT_VERSION is semver"
out=$("$WT" --version)
assert_eq "$out" "wt $ver" "wt --version prints name and WT_VERSION"
out=$("$WT" -V)
assert_eq "$out" "wt $ver" "wt -V is the same as --version"
assert_match "$("$WT" -h)" "--version" "wt -h documents --version"

# ---- summary ------------------------------------------------------------
if [[ "$fails" -eq 0 ]]; then
  echo "all tests passed"
else
  echo "$fails test(s) failed" >&2
  exit 1
fi
