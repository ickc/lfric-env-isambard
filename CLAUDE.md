# CLAUDE.md

Orientation for AI coding agents. End-user steps live in [`README.md`](README.md);
deep rationale + maintenance in [`MAINTAINER.md`](MAINTAINER.md). Read those before
proposing non-trivial changes — don't duplicate them here.

## What this repo is

A reproducible build of the **LFRic Apps Spack environment** for **Isambard 3**
(Cray EX, Grace/aarch64, GCC 14.3). Pinned source submodules → a Spack build →
a self-contained Lmod modulefile. Two stages, two variants:

- **Stage 1** (`scripts/build.sh`): build the environment. The reproducible core.
- **Stage 2** (`examples/lfric-atm/`): a *worked example* of compiling a science
  target on the built environment. Adaptable, not core.
- **Variants** via `LFRIC_STACK`: `cray` (system cray-mpich + Cray HDF5/netCDF;
  default) and `spack` (mpich + HDF5/netCDF from source).

## The invariant — do not break it

**All four cases must still build:** {Stage 1, Stage 2 example} × {`cray`, `spack`}.
This is the one outcome that must stay green. The `cray`/`spack` solve assertions in
`scripts/build.sh` (grepping `spack.lock`) guard the variants — keep them.

## Layout (where to look)

- `scripts/common.sh` — sourced by everything; sets `PREFIX`, `WORKING_DIR`,
  `LFRIC_STACK`, `SPACK_ENV_DIR`, `MODULEFILE`, and puts vendored spack on `PATH`.
  Start here to understand any path.
- `scripts/build.sh` — Stage 1. `scripts/build.sbatch` — submits it to a compute node.
- `examples/lfric-atm/{build.sh,build.sbatch}` — Stage 2 example.
- `scripts/gen-modulefile.sh` + `scripts/lfric-env.lua` — the two-part modulefile
  (generated per-build data table + version-controlled logic).
- `spack-env/{common,cray/spack,spack/spack}.yaml` — env templates (instantiated under PREFIX).
- `spack-repo/lfric-isambard/` — local Spack packages.
- `vendor/` — pinned submodules. **Core (Stage 1):** spack, spack-packages,
  lfric_apps, lfric_core, mo-spack-packages. **Physics (Stage 2 only):**
  physics/{casim,jules,socrates,ukca}.
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
- **pixi is optional.** Every `pixi` task in `pixi.toml` is a thin wrapper around a
  `scripts/` (or `examples/`) script; keep that 1:1 mapping and keep docs no-pixi-first.
- **Reproducible/offline.** The lfric_atm compile must not fetch sources at build
  time (patch 30 enforces this via `PHYSICS_ROOT` + staged submodules). Don't
  reintroduce build-time clones.
- **Don't commit generated state.** Build output is outside the repo; submodules
  show as modified after `patch-all.sh` (expected) — don't commit those gitlink/
  content changes unless deliberately bumping a pin (see MAINTAINER.md).

## How to test a change

- **Static:** `bash -n scripts/*.sh examples/lfric-atm/build.sh`; `shellcheck` if present.
- **Cheap concretize (login node):** `STOP_AFTER_CONCRETIZE=1 LFRIC_STACK=cray bash
  scripts/build.sh` → `CONCRETIZE_OK`; repeat with `LFRIC_STACK=spack`. This runs the
  variant assertions without the multi-hour install. Do this before claiming a
  build-affecting change works.
- **Full build:** heavy + scheduler-gated; the user runs `sbatch`. Success markers:
  `BUILD_OK` (Stage 1), `LFRIC_ATM_OK` (Stage 2 example).

## Gotchas

- **Spack 1.0 needs CPython in [3.7, 3.12)** (it uses `ast.Str`). `common.sh` points
  `SPACK_PYTHON` at `python3`; the sbatch loads `cray-python/3.11.7`; pixi pins 3.11.
- **Private submodules need Met Office SSO** on the SSH key. A `submodule update`
  failure is almost always this.
- **The cray HDF5/netCDF module versions must match** the external prefixes in
  `spack-env/cray/spack.yaml` (and the from-source pins in `spack/spack.yaml` mirror
  them). Bumping one means bumping the others.
- **Temp files:** use the session scratchpad dir, not `/tmp` or the repo.
