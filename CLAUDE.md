# CLAUDE.md

Orientation for AI coding agents. End-user steps live in [`README.md`](README.md);
deep rationale + maintenance in [`MAINTAINER.md`](MAINTAINER.md). Read those before
proposing non-trivial changes — don't duplicate them here.

## What this repo is

A reproducible build of the **LFRic Apps Spack environment** for **Isambard 3**
(Cray EX, Grace/aarch64, GCC 14.3). Pinned source submodules → a Spack build →
a self-contained Lmod modulefile. **One prerequisite build + two tiers of example**,
two variants:

- **Stage 1** (`scripts/build.sh`): build the environment. The reproducible **core** —
  the one true prerequisite. (Still called "Stage 1"; the rest are examples built *on*
  it, not sequential stages.)
- **`examples/minimal-compile/`** — the **minimal compilation example**: compile a
  science target (`lfric_atm`) on the built env, no science run. Adaptable, not core.
  (Historically "Stage 2".)
- **`examples/science-suites/u-*/`** — the **full science-suite examples**: run real
  Rose/Cylc suites (compile *and* run) on the built env. Adaptable, not core.
  (Historically "Stage 3".) minimal-compile and science-suites are **siblings** — both
  depend only on Stage 1, not on each other; each compiles its own `lfric_atm`.
- **Variants** via `LFRIC_STACK`: `cray` (system cray-mpich + Cray HDF5/netCDF;
  default) and `spack` (mpich + HDF5/netCDF from source).

## The invariant — do not break it

**All four cases must still build:** {the env build (Stage 1), the minimal-compile
example} × {`cray`, `spack`}. This is the one outcome that must stay green. The
`cray`/`spack` solve assertions in `lfric_concretize` (`scripts/lib.sh`, grepping
`spack.lock`) guard the variants — keep them.

## Layout (where to look)

- `scripts/common.sh` — sourced by everything; sets `PREFIX`, `WORKING_DIR`,
  `LFRIC_STACK`, `SPACK_ENV_DIR`, `MODULEFILE`, and puts vendored spack on `PATH`.
  Start here to understand any path.
- `scripts/lib.sh` — the Stage-1 build PHASES as sourceable `lfric_*` functions
  (prepare/concretize/install/fetch/…). The drivers below just compose these.
- `scripts/build.sh` — Stage 1 driver (prepare+concretize+install+modulefile).
  `scripts/concretize.sh` — solve only (the cheap login-node check). `scripts/fetch.sh`
  — login-node source pre-fetch. `scripts/build.sbatch` — submits build to a compute node.
- `examples/minimal-compile/{build.sh,build.sbatch}` — the minimal-compile example.
- `examples/science-suites/{run-suite.sh,site/extract-sources.sh,u-*/}` — the
  science-suite examples (Cylc-driven; per-suite source via `dependencies.yaml`).
- `scripts/gen-modulefile.sh` + `scripts/lfric-env.lua` — the two-part modulefile
  (generated per-build data table + version-controlled logic).
- `spack-env/{common,cray/spack,spack/spack}.yaml` — env templates (instantiated under PREFIX).
- `spack-repo/lfric-isambard/` — local Spack packages.
- `vendor/` — pinned submodules, two classes. **Env/build tooling (Stage 1):** spack,
  spack-packages, mo-spack-packages. **LFRic source (the examples build from these):**
  lfric_apps, lfric_core, physics/{casim,jules,socrates,ukca} — these are the
  `dependencies.yaml` set; the science-suites treat them as local mirrors to extract a
  declared ref from (see `examples/science-suites/site/extract-sources.sh`).
- `patches/*-patch.sh` — applied in sorted order by `patch-all.sh`.

## Conventions (the design rules of this repo)

- **Explicit over automagic.** Configuration is two env vars set explicitly (the
  sbatch config blocks): `LFRIC_PREFIX` (persistent install, outside the repo) and
  `LFRIC_WORKING_DIR` (transient Spack stage, node-local on a compute node). There is
  deliberately **no** build-stage filesystem probing, no `SPACK_ENV` back-derivation,
  no auto-config of the user's home dir. If you're tempted to add inference, prefer a
  required/defaulted variable + a clear error instead.
- **`PREFIX` = persistent, `WORKING_DIR` = transient.** Persistent output (install
  tree, env+view, modulefiles, caches) → `$PREFIX`. Only Spack's `build_stage` →
  `$WORKING_DIR`. Both variants share one `$PREFIX/opt`, so keep `PREFIX`
  variant-independent.
- **Builds run on a compute node.** Never run a full Stage-1 build on a login node —
  it hits `ulimit -u` (~900 procs) and fails with `fork: Resource temporarily
  unavailable`. Concretization alone is fine on the login node.
- **The science-suite examples use Rose/Cylc on purpose — don't reinvent it.**
  Scientists run LFRic suites with `cylc`/`rose`, so the science-suite examples run them
  *that* way: the environment Stage 1 builds already ships `rose`, `cylc`, `rose_picker`
  in the view (deps of `lfric-apps-isambard`), and the job is to make a real suite run on
  Isambard 3 against our env — adapt the suite's site/platform config + declare its
  sources in `dependencies.yaml`, don't replace Cylc's scheduler with `sbatch` or
  hand-roll a `rose-app.conf` parser. (The env build and the minimal-compile example stay
  `sbatch`-driven; only the science-suites are Cylc-driven, because that is the
  user-facing workflow we must support. The `extract` step still honours the offline
  invariant — `git archive` from the vendored local mirrors, no MO clones.)
- **pixi is optional.** Every `pixi` task in `pixi.toml` is a thin wrapper around a
  `scripts/` (or `examples/`) script; keep that 1:1 mapping and keep docs no-pixi-first.
- **Reproducible/offline.** The lfric_atm compile must not fetch sources at build
  time (patch 30 enforces this via `PHYSICS_ROOT` + staged submodules). Don't
  reintroduce build-time clones.
- **Don't commit generated state.** Build output is outside the repo; submodules
  show as modified after `patch-all.sh` (expected) — don't commit those gitlink/
  content changes unless deliberately bumping a pin (see MAINTAINER.md).

## How to test a change

- **Static:** `bash -n scripts/*.sh examples/minimal-compile/build.sh`; `shellcheck` if present.
- **Cheap concretize (login node):** `LFRIC_STACK=cray bash scripts/concretize.sh`
  → `CONCRETIZE_OK`; repeat with `LFRIC_STACK=spack`. This runs the variant
  assertions without the multi-hour install (idempotent — a no-op when the lock is
  current; add `FORCE_CONCRETIZE=1` to force a fresh re-solve). Do this before
  claiming a build-affecting change works.
- **Full build:** heavy + scheduler-gated; the user runs `sbatch`. Success markers:
  `BUILD_OK` (Stage 1 env build), `LFRIC_ATM_OK` (minimal-compile example).

## Gotchas

- **Spack 1.0 needs CPython in [3.7, 3.12)** (it uses `ast.Str`). `common.sh` points
  `SPACK_PYTHON` at `python3`; the sbatch loads `cray-python/3.11.7`; pixi pins 3.11.
- **Private submodules need Met Office SSO** on the SSH key. A `submodule update`
  failure is almost always this.
- **The cray HDF5/netCDF module versions must match** the external prefixes in
  `spack-env/cray/spack.yaml` (and the from-source pins in `spack/spack.yaml` mirror
  them). Bumping one means bumping the others.
- **Temp files:** use the session scratchpad dir, not `/tmp` or the repo.
