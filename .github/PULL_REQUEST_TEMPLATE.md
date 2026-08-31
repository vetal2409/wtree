## Summary

<!-- What does this change do, and why? -->

## Checklist

- [ ] Ran both test suites locally, and note which OS: `./tests/wt.test.sh` and `./tests/wt-sync.test.sh` (macOS / Linux)
- [ ] Updated the relevant script's header comment and confirmed `-h` output still matches, if behaviour changed
- [ ] If `bin/wt-sync`'s header grew or shrank, bumped the `sed -n '2,NNp'` range in its `usage()` to match (`awk 'NR>1 && !/^#/ { print NR-1; exit }' bin/wt-sync`)
- [ ] No new dependency added under `bin/` (fzf remains the only exception, used only by `wt rm -i`)
- [ ] Added or updated an entry under `## [Unreleased]` in `CHANGELOG.md`
