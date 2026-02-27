# Cargo Update Test Suite for renovatebot/renovate#39137

Reproducible test suite for `cargo update` behavior that exposed a bug in renovate's `cargoUpdatePrecise` logic. Each scenario runs in a fresh Docker container to avoid state leakage between tests.

## Background

### The bug

Renovate's `cargoUpdatePrecise` function (in `lib/modules/manager/cargo/artifacts.ts`) updates lockfile-pinned crate versions by running a sequence of commands:

```
cargo update --manifest-path <path> --package <dep>@<lockedVersion> --precise <newVersion>
```

In a **workspace** with multiple members that share a dependency (e.g. `reqwest = "0.12"`), this sequence breaks:

1. **Command 1** (from `subdir/Cargo.toml`): `cargo update --package reqwest@0.12.23 --precise 0.12.24` — succeeds, updates the shared `Cargo.lock` from `0.12.23` → `0.12.24`.
2. **Command 2** (from `subdir2/Cargo.toml`): `cargo update --package reqwest@0.12.23 --precise 0.12.24` — **fails** because the lockfile now has `0.12.24`, so the `@0.12.23` spec no longer matches anything. Cargo reports: `"package ID specification did not match"`.

The root cause is that workspaces share a single `Cargo.lock`, so the first `--precise` call mutates it and subsequent calls reference a stale `lockedVersion`.

### The fix

The fix adds a guard in `cargoUpdatePrecise` (lines 54-59 of `artifacts.ts`):

```typescript
// If the range is bumped in Cargo.toml, the old lockedVersion may no longer
// exist in Cargo's dependency graph, so let the --workspace update at the
// end re-resolve it instead.
if (dep.currentValue && dep.newValue && dep.currentValue !== dep.newValue) {
  continue;
}
```

When `currentValue !== newValue` (i.e. the manifest range was bumped, like `"0.14"` → `"0.15"`), the function skips `--precise` for that dependency. A final `cargo update --workspace` command then re-resolves all dependencies against the new ranges.

This works because `--workspace` doesn't reference specific locked versions — it just resolves the entire dependency graph from the manifest ranges, avoiding the stale-spec problem.

## Quick Start (Docker)

```bash
./run_all_tests.sh
```

This builds the Docker image (pinned to `rust:1.90-slim`), then runs the bug reproduction and all three scenarios in **separate containers** — each `docker run` starts fresh so there's no state leakage between scenarios. No local Rust installation required.

### Run a single scenario

```bash
docker build -t cargo-update-tests .

# Bug reproduction only
docker run --rm cargo-update-tests ./repro_bug.sh

# Individual scenarios
docker run --rm cargo-update-tests ./run_tests.sh 1   # Range bump
docker run --rm cargo-update-tests ./run_tests.sh 2   # Stale lockedVersion
docker run --rm cargo-update-tests ./run_tests.sh 3   # Multi-version ambiguity
```

## Prerequisites (running locally)

- Rust toolchain via [rustup](https://rustup.rs/)
- `cargo` available in PATH (tested with Rust 1.90; behavior may differ on older toolchains)

## Running Locally

```bash
# Reproduce the exact bug from #39137
./repro_bug.sh

# Run individual scenarios
./run_tests.sh 1   # Range bump (hashbrown)
./run_tests.sh 2   # Stale lockedVersion (reqwest)
./run_tests.sh 3   # Multi-version ambiguity (syn)
```

## Using a Specific Toolchain

```bash
CARGO="rustup run 1.80.0 cargo" ./run_tests.sh 1
CARGO="rustup run nightly cargo" ./run_tests.sh 3
```

## What Each Scenario Tests

Every scenario is tested against both a **single-crate** layout (`single_crate/`) and a **workspace** layout (`workspace/` with `subdir1` + `subdir2`). Each scenario writes its Cargo.toml, runs `cargo update` to resolve deps into the lockfile, then pins specific versions with `cargo update --precise` as needed.

### Scenario 1: Range Bump (`hashbrown "0.14"` → `"0.15"`)

Tests what happens when the `Cargo.toml` dependency range is bumped to a new semver-incompatible range. For 0.x crates, `^0.14` and `^0.15` are incompatible ranges (cargo treats the first non-zero component as the major version), so the locked version `0.14.5` is outside the new `"0.15"` range.

**Setup:** Write `hashbrown = "0.14"` and `cargo update` to resolve (locks `0.14.x`), then overwrite `Cargo.toml` to `hashbrown = "0.15"`.

| Test | Command | Expected | Why |
|------|---------|----------|-----|
| **1a** | `--package hashbrown@0.14.x --precise 0.15.2` | Success | Modern cargo can resolve across the range bump |
| **1b** | `--workspace` | Success | Re-resolves to latest `0.15.x` — **this is what our fix uses** |

Both single-crate (**1a**, **1b**) and workspace (**1a-ws**, **1b-ws**) variants are tested.

### Scenario 2: Stale lockedVersion (Sequential `--precise`)

Directly reproduces the #39137 bug: two workspace members share a dependency (`reqwest = "0.12"`), and the second `--precise` call fails because the lockfile was already mutated by the first.

**Setup:** Write `reqwest = "0.12"` and `cargo update` to resolve, then pin to `0.12.23` via `cargo update --precise`.

| Test | Command | Expected | Why |
|------|---------|----------|-----|
| **2a** | `--package reqwest@0.12.23 --precise 0.12.24` | Success | First call, lockfile still has `0.12.23` |
| **2b** | `--package reqwest@0.12.23 --precise 0.12.24` (again) | Failure: `"did not match"` | Lockfile now has `0.12.24`, so `@0.12.23` is stale |

In the workspace variant (**2a-ws**, **2b-ws**), the first call is from `subdir1` and the second from `subdir2`, matching the exact sequence from the bug report.

### Scenario 3: Multi-Version Ambiguity (`syn@1` + `syn@2`)

Tests behavior when multiple major versions of the same crate coexist. For the single-crate layout, `syn = "2"` is a direct dependency and `syn@1` comes in transitively via `clap = "3"` (which uses `clap_derive` → `syn@1`). For the workspace layout, `subdir1` depends on `syn = "1"` and `subdir2` on `syn = "2"`.

**Setup:** Write `syn = "2"` + `clap = "3"` (or `syn = "1"` / `syn = "2"` in workspace) and `cargo update` to resolve both syn versions, then pin `syn@2` to `2.0.100`.

| Test | Command | Expected | Why |
|------|---------|----------|-----|
| **3a** | `--workspace` | Success | `--workspace` handles multi-version deps correctly |
| **3b** | `--package syn --precise 2.0.100` | Failure: `"ambiguous"` | Bare `syn` matches both `syn@1.x` and `syn@2.x` |
| **3c** | `--package syn@2.0.100 --precise 2.0.90` | Success | `@version` disambiguates which syn to target |
| **3d** | `--workspace` after bumping range to `">=2.0.110, <3"` | Success | Correctly re-resolves only the matching version |

Both single-crate and workspace variants are tested.

## How `repro_bug.sh` Works

This is a standalone reproduction of the exact bug from the issue. It uses the `repro_crate/` workspace (two members, both depending on `reqwest = "0.12"`) with a committed `Cargo.lock` already pinned to `reqwest@0.12.23`. It then runs the 3 commands from the issue:

1. **Command 1:** `cargo update --manifest-path subdir/Cargo.toml --package reqwest@0.12.23 --precise 0.12.24` — succeeds, updates lockfile from `0.12.23` → `0.12.24`
2. **Command 2:** `cargo update --manifest-path subdir/Cargo.toml --workspace` — succeeds (no-op)
3. **Command 3:** `cargo update --manifest-path subdir2/Cargo.toml --package reqwest@0.12.23 --precise 0.12.24` — **fails** with `"did not match"` because the lockfile already has `0.12.24`

## Relationship to Renovate Code Change

The code change lives in `lib/modules/manager/cargo/artifacts.ts`. The `cargoUpdatePrecise` function builds a list of `cargo update --precise` commands for each dependency, then appends a final `--workspace` call. The fix inserts a `continue` guard at the top of the loop:

```typescript
for (const dep of updatedDeps) {
  // Skip --precise when the range was bumped — the old lockedVersion
  // may not exist in the lockfile anymore
  if (dep.currentValue && dep.newValue && dep.currentValue !== dep.newValue) {
    continue;
  }

  cmds.push(
    `cargo update ... --package ${dep.packageName}@${dep.lockedVersion} --precise ${dep.newVersion}`
  );
}

// Final --workspace resolves any skipped deps against their new ranges
cmds.push(`cargo update ... --workspace`);
```

This means:
- **Range unchanged** (`currentValue === newValue`): still uses `--precise` with the exact `@lockedVersion` spec (existing behavior)
- **Range bumped** (`currentValue !== newValue`): skips `--precise`, lets the trailing `--workspace` re-resolve against the new range (the fix)

The trailing `--workspace` was already present before the fix — the only change is the `continue` guard that skips `--precise` when it would fail.

## E2E Tests (Renovate updateArtifacts)

The `e2e/` directory contains end-to-end tests that directly invoke Renovate's
cargo `updateArtifacts()` function against fixture Cargo projects. This verifies
that the `cargoUpdatePrecise` fix works by exercising the actual Renovate code
that generates and executes `cargo update` commands.

The test script (`e2e/test_update_artifacts.ts`) uses `tsx` to import the
`updateArtifacts` function from the Renovate source, sets up `GlobalConfig`,
and calls it with the same parameters Renovate would pass during a real update.

The Renovate fork is included as a git submodule. To initialize it:

    git submodule update --init

To run the e2e tests alone:

    docker build -t cargo-update-e2e-tests -f e2e/Dockerfile.e2e .
    docker run --rm cargo-update-e2e-tests

Or run everything (unit tests + e2e):

    ./run_all_tests.sh

## Directory Structure

```
repro_crate/       — Static workspace matching the exact #39137 setup
  Cargo.toml       — Workspace root with members: [subdir, subdir2]
  Cargo.lock       — Committed lockfile with reqwest pinned to 0.12.23
  subdir/          — First workspace member (reqwest = "0.12")
  subdir2/         — Second workspace member (reqwest = "0.12")
workspace/         — Workspace template, overwritten per scenario by run_tests.sh
  Cargo.toml       — Workspace root with members: [subdir1, subdir2]
  subdir1/         — First workspace member
  subdir2/         — Second workspace member
single_crate/      — Single crate template, overwritten per scenario by run_tests.sh
repro_bug.sh       — Standalone reproduction of the #39137 bug
run_tests.sh       — Test suite (accepts scenario number: 1, 2, or 3)
run_all_tests.sh   — Host-side orchestrator: builds image, runs all scenarios
Dockerfile         — Builds a container with pinned Rust 1.90 toolchain
.dockerignore      — Excludes .git and target/ from Docker context
```
