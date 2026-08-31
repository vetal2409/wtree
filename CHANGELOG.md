# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

First public release.

### Added
- `wt` — create, open, list, rename and remove git worktrees under one root
  (`$WT_ROOT`, default `~/worktrees`).
- `wt rm -i` — pick worktrees to remove in fzf, with a preview showing the
  unpushed commits and local changes each one would cost.
- `wt-sync` — declarative untracked-state sync driven by a repo's
  `.worktreesync`, with `copy`, `clone` and `link` modes.
- `wt open --fresh` — fetch and fast-forward the default branch before
  opening, so a new worktree starts from current code.
- `-b .` — base a new branch on whatever the repo context is on right now.
  Composes with `--fresh`.
- `--version` on `wt`, `wt-sync` and `wtc`.
- `contrib/wtc` — cmux + Claude Code session starter, published as an example.

### Fixed
- The `.worktreesync` depth-pattern documentation claimed a bare name matched
  every untracked path; it matches ignored paths only.
