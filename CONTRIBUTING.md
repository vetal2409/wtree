# Contributing

Thanks for looking at `wtree`. It's a small, dependency-free tool and stays
that way on purpose — read the constraints below before writing code.

## Running the tests

```bash
./tests/wt.test.sh
./tests/wt-sync.test.sh
```

No framework, no dependencies. Each suite builds a throwaway git repo (and
worktrees) under `mktemp -d`, runs the real binaries against it, and asserts
on real output. Run both before opening a PR — CI runs them again on macOS
and Linux, but catching a failure locally first saves a round trip.

## The `bin/` vs `contrib/` rule

This is a hard constraint, not a style preference: **nothing under `bin/` may
require anything beyond git and coreutils.**

The one deliberate exception is `fzf`, used only by `wt rm -i`. When `fzf`
(or `$WT_FZF`) is not on `PATH`, that path degrades with a clear error
instead of failing silently or crashing.

Integrations with a specific editor, multiplexer, or agent (cmux, Claude
Code, your editor's worktree hook, …) go in `contrib/` instead. They're
published as examples for people to adapt, not as commands this project
supports or tests the way it supports `bin/`. If your change wires `wt` into
a specific tool, it belongs in `contrib/`, and it's fine for it to take on
dependencies `bin/` can't.

## The header comment is the documentation

Every script's `usage()` reprints its own header comment block, so `-h` and
the header can't drift apart — there's only one place to edit the docs, not
two to keep in sync by hand.

`bin/wt` and `contrib/wtc` use a self-terminating awk range
(`!/^#/ { exit }`), so they need no maintenance when the header grows or
shrinks.

**`bin/wt-sync` is the exception, and it will bite you if you forget this:**
its `usage()` uses a hardcoded `sed -n '2,NNp'` range. Adding or removing a
header line silently corrupts `-h` output unless that number is updated in
the same commit — there is no error, just a wrong range. This has already
needed fixing twice in this project's history.

Verify it before you commit:

```bash
awk 'NR>1 && !/^#/ { print NR-1; exit }' bin/wt-sync   # must equal the number in usage()
./bin/wt-sync -h | tail -3                              # must end with the --version line
```

If the first command's output doesn't match the `N` in `sed -n '2,Np'`
inside `usage()`, fix the number before committing.

## stdout is the data channel

`wt` and `wtc` print the bare worktree path to stdout — that's what makes
`cd "$(wt open foo)"` work. Every other message (progress, errors, logs)
goes to stderr via the scripts' `log()` helper. If you add output, get this
right: anything that isn't the path does not belong on stdout.

## New behaviour needs a test

Add a case to the relevant suite (`tests/wt.test.sh` or
`tests/wt-sync.test.sh`) for anything you add or change. Both suites are
plain bash assertions against real output — follow the existing `pass`/
`fail`/`assert_*` helpers already in each file rather than introducing a new
pattern.

## Commit style

Conventional commits (`feat:`, `fix:`, `docs:`, `ci:`, `refactor:`, …),
matching the existing history — check `git log --oneline` for the tone and
scope this project uses.

## PR flow

Branch off `main`, open a PR against `main`, and make sure CI is green on
both macOS and Linux before asking for review. If your change touches
`bin/` or `contrib/`, run both test suites locally first — see above.

## Cutting a release

Releases are cut with `script/release`, run from a clean `main` that's
up to date with `origin/main`:

```bash
script/release X.Y.Z
```

It runs both test suites, bumps `WT_VERSION` in `bin/wt`, `bin/wt-sync` and
`contrib/wtc`, promotes the CHANGELOG's `## [Unreleased]` section to
`## [X.Y.Z] - YYYY-MM-DD` and opens a fresh empty `Unreleased` above it, then
commits and tags `vX.Y.Z` locally.

Review the commit and tag it produced, then publish:

```bash
git push origin main --follow-tags
```

The script deliberately does not push — publishing a release is
irreversible, so that stays a separate, deliberate step. Pushing the tag
triggers `.github/workflows/release.yml`, which re-runs both test suites on
macOS and Linux, checks that each script's `WT_VERSION` matches the tag, and
then publishes the GitHub Release using the matching CHANGELOG section as
its notes.
