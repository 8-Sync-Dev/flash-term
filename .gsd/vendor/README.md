# GSD local runtime

Project-scoped gsd-pi vendoring. This directory is NOT global. Global runtime under ~/.gsd/agent/ stays untouched.

## Layout

| Folder | Role | Mutable | Runs? |
|---|---|---|---|
| gsd-pi/baseline-2.69.0/ | Immutable snapshot of gsd-pi@2.69.0 | No | No |
| gsd-pi/latest/ | Submodule of upstream https://github.com/gsd-build/gsd-2.git | No (auto-pull only) | No |
| gsd-pi/current/ | Working copy. Starts from baseline, patches applied. | Yes | **Yes** |
| gent/ | Local equivalent of ~/.gsd/agent/ -- auth, settings, extensions | Yes | **Yes** |

## Workflow

```
8sync gsd local init                # scaffold layout
8sync gsd local baseline            # seed baseline from global or clone
8sync gsd local add-submodule       # add upstream as submodule at latest/
8sync gsd local use baseline        # point current/ to baseline copy
8sync gsd local fix --stable        # patch current/ with known stable fixes
8sync gsd local enter               # activate GSD_CODING_AGENT_DIR for this shell
gsd ...                             # now runs from current/
8sync gsd local leave               # revert to global
```

## Notes

- current/ is yours to commit into the project repo for reproducibility.
- latest/ is a submodule reference; diff against baseline to decide what to merge.
- Global gsd-pi install is never touched by these commands.
- Global install is only refreshed when --allow-global is explicitly passed to 8sync gsd fix.