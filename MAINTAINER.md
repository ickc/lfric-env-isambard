# Maintainer's guide — the examples

How the parts of `lfric-env-isambard` that *use* the environment work, and how to
maintain them. For the end-user walkthrough see [`README.md`](README.md); for
AI-agent orientation see [`CLAUDE.md`](CLAUDE.md).

> **Building the environment is not here.** Stage 1 is self-contained in
> [`stage1/`](stage1/) and documented in [`stage1/README.md`](stage1/README.md) —
> its layout, build locations, phases, the modulefile, the two variants, and
> where the pinned versions come from. This file covers everything downstream of
> `module load`.

## Repository layout

```
stage1/                 # BUILD THE ENVIRONMENT — self-contained, see stage1/README.md
examples/minimal-compile/  # compile lfric_atm + run its bundled example
  build.sh  build.sbatch  README.md
examples/science-suites/ # run real Rose/Cylc LFRic suites
  run-suite.sh           #   launcher: cylc vip a suite against the built env
  site/activate-env.sh   #   ACTIVATE_ENV: module-load the env for suite tasks
  site/patch-sources.sh  #   apply the LFRic patch stack to a suite's extracted tree
  site/bin/launch-exe    #   srun launcher (drop-in for the MO one; XIOS-server MPMD)
  site/rose.conf         #   rosie's `u-` prefix map, so `rosie checkout` works here
  u-dn704/ u-dr932/ u-dt000/  # only README + known-issues: the SUITES live upstream.
                          #   u-dr932 = submodule vendor/lfric_egp_bench (patches/40-*);
                          #   u-dn704 + u-dt000 = MOSRS checkouts in ~/roses
                          #   (patches/suites/42-*, 41-*)
scripts/                # shared helpers for the examples
  common.sh             #   which built environment to load, and where its modulefiles are
  activate.sh           #   `module load $MODULE_NAME` (pixi auto-activation)
  print-versions.sh     #   `pixi run activate`: report rose/cylc/psyclone
  patch-all.sh / unpatch.sh
  stage-physics.sh      #   set physics + lfric_core submodules to dependencies.yaml refs
  setup-cylc.sh         #   opt-in: write ~/.cylc run dir + isambard3 platform
vendor/                 # pinned submodules — the LFRic SOURCES the examples compile
  lfric_apps/  lfric_core/                     #   (Stage 1's own submodules are in stage1/vendor/)
  physics/{casim,jules,socrates,ukca}/
  lfric_egp_bench/                             #   upstream science suite (u-dr932), patched
patches/                # one *-patch.sh per upstream patch (applied in sorted order)
                        #   patch-all.sh is -maxdepth 1: BOTH subdirs below are outside it
  suites/               #   stagers for the MOSRS suites (41-u-dt000, 42-u-dn704) + their
                        #   .patch files. Out of the stack because they patch a checkout
                        #   in the user's $HOME; run-suite.sh runs them, not patch-all.sh
  optional/             #   per-suite source patches, OUTSIDE the stack — a suite opts
                        #   in by path from its own extract task (see its README)
staging/                # reproductions of reported problems, with evidence + conclusion
logs/                   # sbatch stdout (.gitkeep tracked; *.out ignored)
VERSION                 # which environment version the examples load. Keep in step
                        #   with stage1/VERSION.
```

## Patches

Each patch is a standalone, idempotent `patches/<NN>-<target>-patch.sh`, applied in
sorted order by `patch-all.sh` (discovered dynamically). These are the patches to
the LFRic *sources* and to the example suites; Stage 1 patches only its own
vendored `spack-packages` and does so itself (`stage1/patches/`).

- `10-/11-lfric_core-*` — Fortran/Make fixes in `vendor/lfric_core`.
- `30-lfric_apps-local-sources-patch.sh` — **reproducible/offline sources.** Rewrites
  `get_source()` in lfric_apps so the build stages the pinned `lfric_core` + physics
  submodules in place (symlink + sanity-check) instead of cloning/fetching at build
  time; a remote (`.git`) source now *raises* instead of silently fetching. So the
  lfric_atm compile is a pure function of the checked-out submodule SHAs.
- `31-lfric_apps-slow-physics-mphys-field-patch.sh` — an upstream 2026.07.1
  regression that breaks any dynamics-plus-forcing-only configuration (all UM
  physics sections `none`), i.e. u-dr932 and u-dt000.
- `40-lfric_egp_bench-u-dr932-*` — stages the u-dr932 suite for Isambard 3
  (`rose app-upgrade` to the env's vn, then the site diff). Inert without `rose`,
  so `run-suite.sh` re-runs it with the environment activated.

Every patch above modifies files **inside a submodule**, so `unpatch.sh` reverts
them all by `git reset --hard && git clean -fd` on `lfric_core`, `lfric_apps` and
`lfric_egp_bench`. The Met Office *package* definitions are no longer patched: the
old `simit-spack` repo needed ~40 patch scripts under Spack 1.0, but its successor
`mo-spack-packages` is Spack-1.0 native (`api: v2.0`) and the cylc/rose tools now
ship in the Spack builtin repo.

## Bumping pinned versions

The authoritative pins are the submodule gitlinks (`git submodule status`).

(Spack and the two package repos are Stage 1's — see
[`stage1/README.md`](stage1/README.md).)

- **`lfric_apps`:** `cd vendor/lfric_apps`, `git fetch`, `git checkout <ref>`, then
  `git add vendor/lfric_apps && git commit`. Then re-derive everything else from
  its `dependencies.yaml` (below) and re-check the environment's own pins against
  the sources listed in `stage1/README.md` §8.
- **Science sources (physics + lfric_core):** bump the ref(s) in
  `vendor/lfric_apps/dependencies.yaml`, run `bash scripts/stage-physics.sh` (or
  `pixi run stage-physics`) to checkout each submodule to its ref, then
  `git add vendor/physics vendor/lfric_core && git commit`. This is the explicit,
  reviewable way to pull in new science — `local_build.py` no longer auto-clones
  (patch 30), so the build only reads what you stage.

## Maintainer-only overrides

Beyond the user-facing vars in the README:

| Variable | Default | Purpose |
|----------|---------|---------|
| `PSYCLONE_TRANSFORMATION` | `minimum` | minimal-compile example: PSyclone optimisation set. A directory under `applications/lfric_atm/optimisation/`; `meto-ex1a` is the Cray-EX-tuned one. |
| `MAKE_JOBS` | `8` | minimal-compile example: parallel make jobs. |
| `LFRIC_SUITE_DIR` | `~/roses/<id>` | science-suites: where the MOSRS checkout lives. |
| `USE_MIRRORS` | `false` | science-suites: extract from `vendor/mirrors/` instead of the network. |

Stage 1's own overrides (`HEAVY_JOBS`, `FORCE_CONCRETIZE`, `FETCH_JOBS`, the Cray
module names) are in [`stage1/README.md`](stage1/README.md) and `stage1/lib.sh`.

## Adding things

- **A new science example:** copy `examples/minimal-compile/` and change the build target
  + which physics deps you stage. The environment-activation block is reusable —
  it is the contract between Stage 1 and anything built on it.

## Testing

- **Static:** `bash -n` and `shellcheck` over every shell script:
  `git ls-files '*.sh' '*.sbatch' | xargs -r bash -n` (then the same with
  `shellcheck`, if available).
- **Cheap (login node):** in `stage1/`, `pixi run concretize` and
  `pixi run concretize-spack` → `CONCRETIZE_OK`. Validates the manifest
  instantiation and the variant assertions without the multi-hour install.
- **Full (compute node) — the invariant:** the four cases must build:
  `cd stage1 && sbatch build.sbatch` (+ `--export=ALL,LFRIC_STACK=spack`) →
  `BUILD_OK`, then `sbatch examples/minimal-compile/build.sbatch` (+ spack) →
  `LFRIC_ATM_OK`.
  **Run the two minimal-compile variants SEQUENTIALLY, not in parallel.** Both
  compile in the same in-tree scratch dir
  (`vendor/lfric_apps/applications/lfric_atm/working/scratch/`), so concurrent jobs
  race on the source symlinks it stages and one dies with
  `FileNotFoundError: ... working/scratch/lfric_core` from `get_git_sources.py`.
  Chain them instead: `sbatch --dependency=afterany:<cray-jobid> ...`. (The two
  Stage-1 builds are worth chaining too — they share `$LFRIC_PREFIX/opt`.)
- **Integration (the examples are the test).** minimal-compile and the science-suites
  double as integration tests that a bare `module load` is a sufficient toolchain —
  they load the env like an end user and add nothing of their own to it. After
  changing `stage1/gen-modulefile.sh` / `stage1/lfric-env.lua` (what the module
  exports), re-run
  both minimal-compile variants and, on `cray`, at least one science suite
  (`bash examples/science-suites/run-suite.sh u-dn704` or `u-dr932`) — an end-user
  suite gets no toolchain setup from us, so this is what proves the `module load`
  alone still compiles + runs.
