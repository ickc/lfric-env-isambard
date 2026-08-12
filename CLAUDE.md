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
- **Variants** via `LFRIC_STACK` (keyword stays `cray`/`spack`; the prose names are for
  communication). Both are Spack environments — the difference is what satisfies the deps:
  - **`cray` = the "cray environment"** (default): uses the system Cray libraries wherever
    possible — cray-mpich + Cray HDF5/netCDF (and the Cray `libfabric`/Slingshot stack).
  - **`spack` = the "vanilla spack environment"**: satisfies *all* dependencies from Spack
    (MPI, HDF5, netCDF, …) except the compiler — fully self-contained / portable.

> **Run everything on the cray environment (`cray`).** On Isambard 3 (Cray EX / Slingshot)
> MPI only works *properly* there — cray-mpich + the system `libfabric` (`cxi` provider) +
> `srun` give RDMA over the interconnect and multi-node scaling. The vanilla spack
> environment (`spack`) is a **portable, self-contained fallback only**: its from-source
> `mpich` is `ch4:ofi` over a `libfabric` with no `cxi` provider (inter-node MPI falls back
> to TCP) and is built `~slurm` (no srun PMI; needs Hydra `mpiexec`), so it is
> single-node/TCP at best. So: **all jobs we actually run here use the cray environment**
> (the default). The vanilla spack environment exists to keep the build portable and is
> what the build-invariant below exercises — not for production runs. Batch scripts and the
> science-suite runs must default to `cray`.

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
- `examples/science-suites/{run-suite.sh,site/,u-*/}` — the science-suite examples
  (Cylc-driven; per-suite source via `dependencies.yaml`). `site/patch-sources.sh`
  applies the LFRic patch stack to a suite's extracted tree; all three suites use
  the upstream `merge_sources.py` extract.
- `scripts/gen-modulefile.sh` + `scripts/lfric-env.lua` — the two-part modulefile
  (generated per-build data table + version-controlled logic).
- `spack-env/{common,cray/spack,spack/spack}.yaml` — env templates (instantiated under PREFIX).
- `spack-repo/lfric-isambard/` — local Spack packages.
- `vendor/` — pinned submodules, three classes. **Env/build tooling (Stage 1):** spack,
  spack-packages, mo-spack-packages. **Science suite:** lfric_egp_bench (Denis Sergeev's
  repo — u-dr932). u-dn704 and u-dt000 are NOT here and must not be: they are Met Office
  rose suites living in MOSRS subversion (`roses-u/d/n/7/0/4/trunk`,
  `d/t/0/0/0/trunk`), fetched with `rosie checkout` into `~/roses/<id>` and patched
  there. Do not vendor a third party's copy of them — this repo supersedes the
  UniExeterRSE one, and that copy is upstream plus *their* port.
  **LFRic source (the examples build from these):**
  lfric_apps, lfric_core, physics/{casim,jules,socrates,ukca} — these are the
  `dependencies.yaml` set; the science-suites treat them as local mirrors to extract a
  declared ref from — `vendor/mirrors/` presents them in the Met Office
  `MetOffice/<repo>.git` layout so the upstream extract can use them offline.
- `patches/*-patch.sh` — applied in sorted order by `patch-all.sh` (top level only,
  `-maxdepth 1`). `40-lfric_egp_bench-*` stages u-dr932 (`rose app-upgrade` + a
  `git apply` of the site diff); it is inert without `rose`, so `run-suite.sh` re-runs it
  with the env activated. Two subdirectories are **outside** that stack, both on purpose:
  `patches/suites/` — the stagers for the MOSRS suites (`41-roses-u-u-dt000-*`,
  `42-roses-u-u-dn704-*`). They patch a checkout in the user's `$HOME`, which an
  environment build must never rewrite; `run-suite.sh` runs them. u-dn704's has no
  `rose app-upgrade` step (upstream is already vn3.2) and applies `-p0` (`svn diff`);
  u-dt000's has one and applies `-p1` (`diff -ruN a b`).
  `patches/optional/` — per-suite LFRic-source patches a single suite opts into by path
  from its own extract task, because applying them everywhere would break the other
  suites. Currently one — the u-dt000 ice-giants forcing.
- `staging/<investigation>/` — reproductions of reported problems, with their evidence
  and conclusion. Off the invariant; nothing in `scripts/`/`spack-env/`/`examples/`
  may depend on it. See `staging/README.md`.

## Conventions (the design rules of this repo)

- **Explicit over automagic.** Configuration is two env vars set explicitly (the
  sbatch config blocks): `LFRIC_PREFIX` (persistent install, outside the repo) and
  `LFRIC_WORKING_DIR` (transient Spack stage, node-local on a compute node). There is
  deliberately **no** build-stage filesystem probing, no `SPACK_ENV` back-derivation,
  no auto-config of the user's home dir. If you're tempted to add inference, prefer a
  required/defaulted variable + a clear error instead.
- **The examples load the env like an end user — keep them thin.** `module load
  lfric-env/<version>/<variant>` is the whole contract: it exports the toolchain
  (`FC`/`CXX`/`LDMPI`, the Cray PE modules, the view's `FFLAGS`/`LDFLAGS`). The
  examples — minimal-compile's `build.sh` and the science-suites'
  `site/activate-env.sh` + `u-*/flow.cylc` (which inherit via `FC = $FC`) — must
  **consume** that and never re-derive it. They are integration tests that a bare
  `module load` suffices, and they stand in for a real end-user Rose/Cylc suite whose
  sources we do *not* stage. The toolchain logic lives in `scripts/lfric-env.lua` +
  `gen-modulefile.sh`; if you change those, the examples are what prove the contract
  still holds (rerun them — see MAINTAINER.md "Testing").
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
  user-facing workflow we must support.)
- **Stage 1's `module load` is the contract; inside a suite, business as usual.** The
  modulefile exports the whole toolchain and a suite only consumes it (`FC = $FC`).
  On the *other* side of that line, keep the Met Office mechanisms a scientist
  already uses — `dependencies.yaml` + `merge_sources.py` for source, the MO
  `launch-exe`, the suite's own machine detection, tasks running where the suite says
  they run. Change only what the platform requires (srun, the `isambard3` platform),
  what is measurably wrong here (Slurm placement), or what version alignment forces
  (`rose app-upgrade`) — and mark each change `[isambard3]` in place, with the reason.
  **Stage 1's offline invariant does not propagate into the suites**: compute nodes
  here have outbound network, and pre-fetching on a user's behalf is exactly the kind
  of unfamiliar machinery that gets the environment rejected. Offline extraction stays
  *available* (`USE_MIRRORS=true` → `vendor/mirrors/`), not imposed.
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
- **One private submodule needs Met Office SSO** on the SSH key: `mo-spack-packages`
  (still `git@github.com:`). The six LFRic source repos (lfric_apps, lfric_core,
  casim, jules, socrates, ukca) are public and on HTTPS URLs — they clone
  anonymously. A `submodule update` failure is almost always mo-spack-packages.
- **The cray HDF5/netCDF module versions must match** the external prefixes in
  `spack-env/cray/spack.yaml` (and the from-source pins in `spack/spack.yaml` mirror
  them). Bumping one means bumping the others.
- **Temp files:** use the session scratchpad dir, not `/tmp` or the repo.
