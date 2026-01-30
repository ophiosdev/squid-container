# Squid Patches

This project supports applying version-specific patches during the Docker build.
Patches are discovered under `/src/patch` (copied from the local `patch/` directory)
and applied in a deterministic order based on Squid version, specificity, and
priority.

## Directory layout

Use the following structure for patch files:

```text
patch/
  v6/
    10_fix-foo.patch
    20 fix-bar.patch
    1/
      10_fix-foo.patch
      30_add-baz.patch
      2/
        05_critical.patch
```

The build maps `SQUID_VERSION` to a patch base directory:

- Major only: `patch/v<major>/` (e.g. `patch/v7/`)
- Major + minor: `patch/v<major>/<minor>/` (e.g. `patch/v7/4/`)
- Major + minor + patch: `patch/v<major>/<minor>/<patch>/` (e.g. `patch/v7/4/1/`)

## Selection rules

1. **Specificity wins**: patches for `major.minor.patch` override `major.minor`,
   which override `major` when file names match.
2. **De-duplication by filename**: if `a.patch` exists in both `v7/` and
   `v7/4/`, only the more specific file (`v7/4/a.patch`) is applied.
3. **Priority order (descending)**: files are applied by numeric prefix:
   - `10_a.patch` or `10 a.patch`
   - higher numbers apply first
   - files without a numeric prefix default to priority `0`

## Applying order

Patches are collected in this order:

1. `patch/v<major>/<minor>/<patch>/`
2. `patch/v<major>/<minor>/`
3. `patch/v<major>/`

Within the final selection set, patches are applied by **priority descending**.

## Build behavior

- Each patch file is logged before application.
- Patches are applied with `patch -p1 --forward --batch` for idempotent,
  non-interactive operation.
- Any failed patch **fails the build immediately**.
- Missing version directories are skipped gracefully.

## Examples

Given:

- `SQUID_VERSION=7.4.1`
- `patch/v7/a.patch`
- `patch/v7/4/a.patch`
- `patch/v7/4/1/05_hotfix.patch`
- `patch/v7/4/1/10_feature.patch`

Applied patches:

1. `10_feature.patch` (priority 10)
2. `05_hotfix.patch` (priority 5)
3. `a.patch` from `v7/4/` (overrides `v7/a.patch`)
