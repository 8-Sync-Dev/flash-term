# Upgrade procedure

## Pull latest upstream to inspect

```
cd .gsd/vendor/gsd-pi/latest
git pull
cd -
8sync gsd local diff                # shows baseline vs latest summary (planned)
```

## Decide what to merge

1. Read diff summary.
2. For each change in latest/:
   - If it fixes something we patched -> we can drop our patch from current/.
   - If it is new feature -> cherry-pick into current/.
   - If it breaks shape we patch -> rewrite patch against new shape.
3. Update PATCHES.md.

## Bump baseline

```
8sync gsd local baseline --from current --tag <new-version>
```

This snapshots current/ as aseline-<new-version>/. Old baseline stays for rollback.

## Rollback

```
8sync gsd local use baseline --version 2.69.0
```