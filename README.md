# wtree

Git worktrees in one place — create them, sync the untracked state they need, and clean them up without losing work.

`wtree`'s main command is `wt`. It keeps every worktree under one root (`$WT_ROOT`, default `~/worktrees`), brings across the untracked files a worktree needs in order to run, and can tell which worktrees are safe to delete.

```console
wt open fix-login    # create or reuse a worktree, sync it, print its path
wt ls                # what exists, how old it is, what is unsaved
wt rm -i             # pick what to delete, with the cost shown first
```

## Why

`git worktree add` gives you a directory. It does not give you the `.env` the app needs, the `node_modules` that takes minutes to install, or any way to tell weeks later which of your worktrees still hold unpushed work. `wt` covers those three gaps and nothing else.

## Install

Clone to `~/development/wtree`:

```bash
git clone https://github.com/vetal2409/wtree.git ~/development/wtree
```

Then add to `~/.zshrc`:

```bash
export PATH="$PATH:$HOME/development/wtree/bin"
eval "$(wt init zsh)"     # optional: adds `wt cd`
```

`contrib/` is a second, optional PATH entry — only needed if you want `wtc`, which wires `wt` into cmux and Claude Code.

## Commands

| Command | What it does |
|---|---|
| `wt open [<name>]` | Open a worktree, creating it if needed; syncs either way |
| `wt cd [<name>]` | Same, then `cd` into it (needs `wt init zsh`) |
| `wt ls [--safe] [--all]` | List worktrees — name, branch, age, status |
| `wt path <name>` | Print a worktree's directory |
| `wt rm <name> [--force]` | Remove a worktree, and its branch if merged |
| `wt rm --merged [--dry-run]` | Remove every worktree that is safe to remove |
| `wt rm -i [--dry-run]` | Pick worktrees to remove in fzf, with a cost preview |
| `wt mv <old> <new>` | Rename a worktree, and its branch when the names match |
| `wt sync [<path>]` | Re-run the untracked-state sync for a worktree |
| `wt init zsh` | Print the zsh shell integration |

Options:

- `-C <repo>` — repo context (default: repo containing cwd)
- `-b <base-ref>` — base for a NEW branch (default: HEAD of the main worktree, or `origin/<default>` under `--fresh`). `-b .` means whatever the repo context is on right now: the branch checked out there, or its commit when HEAD is detached
- `--branch <name>` — branch to create/check out (default: same as worktree name)
- `--fresh` — before opening: fetch the repo's default branch and fast-forward it in the main worktree, so the worktree starts from fresh code. A NEW branch is based on `origin/<default>` unless `-b` picks something else — the two compose, so `wt open --fresh -b . spike` refreshes the repo and still branches off where you are standing

## The output contract

stdout is ALWAYS the bare worktree path. Everything else goes to stderr. That is why `wt` composes with anything:

```bash
cd "$(wt open foo)"
zed "$(wt path foo)"
```

## Syncing untracked state (`.worktreesync`)

Modes:

| Mode | Behavior |
|---|---|
| `copy` | One-time copy when missing in the target; never overwrites, so a worktree can diverge freely after creation |
| `clone` | Block-sharing tree clone when the target is missing or empty — for big generated dirs where a plain copy is slow and doubles disk usage |
| `link` | Symlink target -> source, so state is shared bidirectionally and survives worktree deletion; refuses to clobber a diverged regular file |

Path matching:

| Pattern | Meaning |
|---|---|
| bare name (no slash) | Depth pattern — matches *ignored* paths only (per `git ls-files --others --ignored --exclude-standard`) whose basename equals it, at any depth |
| leading `/` | Root-anchored literal (`/.env` = the root `.env` only) |
| embedded `/` | Literal repo-relative path (`src/app/.env`) |

An untracked file that is not gitignored will not match a depth pattern — `wt-sync` logs `skip <name> (no matches)` for it and leaves it alone.

Example config:

```
clone node_modules
copy .env
link .claude/settings.local.json
```

See [.worktreesync.example](.worktreesync.example) for a fuller, commented version. Every mode is idempotent, so `wt open` on an existing worktree is safe to re-run.

### Running `wt-sync` standalone

`wt open` runs `wt-sync` automatically, so most people never call it directly. It is a supporting command, not something you need day to day — but it is on `$PATH` alongside `wt`, and `wt sync` only forwards `--to`, so reach for it directly when you need the other flags:

```
wt-sync [<target-worktree>] [--to <path>] [--from <path>] [--dry-run] [--quiet]
```

| Flag | Meaning |
|---|---|
| `<target-worktree>` / `--to <path>` | Target worktree to populate (default: the worktree containing `$PWD`) |
| `--from <path>` | Source worktree to read from (default: the repo's main worktree) |
| `--dry-run` | Print what would happen without changing anything |
| `--quiet` | Suppress the `[wt-sync] ...` progress log lines |

## What "safe to remove" means

`wt ls` and `wt rm --merged` treat a worktree as safe to remove when all three hold:

- the branch is fully merged into the default branch
- no tracked file is modified
- no untracked non-ignored file exists

Two caveats make this trustworthy: `wt-sync`'s payloads (`.env`, `node_modules`, …) are gitignored, so they never mask real work as "untracked changes". And nothing here fetches — merge state is only as fresh as the last fetch, and `wt ls` prints that age in its footer.

## Requirements

- git
- coreutils
- bash 3.2+ (macOS system bash works)
- fzf — only for `wt rm -i`; override the picker with `$WT_FZF`

## Layout

| Path | Contents |
|---|---|
| `bin/` | `wt`, `wt-sync` — the supported tool, dependency-free (git + coreutils) |
| `contrib/` | `wtc` — optional glue for cmux and Claude Code |
| `tests/` | Shell test suites for `bin/` |
| `.worktreesync.example` | Template to copy into a repo as `.worktreesync` |

Everything in `bin/` runs on git and coreutils alone — `wt rm -i` additionally wants fzf and degrades with a clear error without it; integrations with specific editors, multiplexers, or agents belong in `contrib/`.

## License

MIT — see [LICENSE](LICENSE).
