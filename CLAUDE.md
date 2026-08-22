# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`wtree` is a dependency-free CLI for git worktrees. Pure bash. No build system, no package manager, no runtime dependencies beyond git and coreutils.

## Layout

| Path | Contents |
|---|---|
| `bin/` | `wt`, `wt-sync` — the supported tool, dependency-free (git + coreutils) |
| `contrib/` | `wtc` — optional glue for specific editors, multiplexers, or agents |
| `tests/` | Shell test suites for `bin/` |
| `.worktreesync.example` | Template to copy into a repo as `.worktreesync` |

Boundary rule, as a hard constraint: **never add a dependency to `bin/`.** `wt rm -i` wants fzf and degrades with a clear error without it — that is the only exception, and it is deliberate. Editor, multiplexer, and agent integrations go in `contrib/`, not `bin/`.

## Conventions

- **The header comment IS the docs.** Every script's `usage()` reprints its own header block, so `-h` and the header cannot drift. `wt` and `wtc` use a self-terminating awk range (`!/^#/ { exit }`) and need no maintenance. **`wt-sync` uses a hardcoded `sed -n '2,37p'` range (bin/wt-sync line 56) — if you grow its header, you MUST bump that number.** Commit `3322835` in the dotfiles history was a fix for exactly this drift.
- **stdout is the data channel.** `wt` and `wtc` print the bare worktree path to stdout and everything else to stderr, so `cd "$(wt open foo)"` works. Any new output goes to stderr via `log()`.
- `set -euo pipefail` in every script; always quote variables.
- Avoid bash 4+ only features (associative arrays, `mapfile`, `${var^^}`) unless you also update the documented requirement in the README.

## Tests

```bash
./tests/wt.test.sh
./tests/wt-sync.test.sh
```

Both build a throwaway origin + clone + worktrees under `mktemp -d` and assert on real output. No mocking, no framework, and they must stay dependency-free too. Run both before committing any change under `bin/`.
