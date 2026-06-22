# lfric-env-isambard

A [pixi](https://pixi.sh)-driven, submodule-based, reproducible build of the
**LFRic Apps Spack environment** for **Isambard 3** (GCC 14.3).

> The Met Office packages come from
> [`mo-spack-packages`](https://github.com/MetOffice/mo-spack-packages) (the
> Spack-1.0-native successor to `simit-spack`); the cylc/rose workflow tools come
> from the vendored Spack builtin repo. See [Pinned versions](#pinned-versions).

This is a refactor of a single large `install.sh` driver into:

- **pixi** as the Stage-1 Python bootstrap *and* task runner — optional, since the
  built environment is `module`-loadable without it (see [Architecture](#architecture)),
- **git submodules** for every upstream source (Spack, the Spack package repo,
  and the Met Office repos), pinned to known-good commits,
- **standalone patch scripts** (`patches/*-patch.sh`) replacing the inline
  `sed`/`awk`/`perl`/heredoc patching that the driver used to do,
- a repo-local, git-ignored `working_dir/` for all heavy build output.

## Architecture

The repo turns pinned upstream sources into a **prebuilt, `module`-loadable LFRic
Apps environment**, in two stages. The key separation: **pixi matters only for
Stage 1, and even there it is optional** — it is not needed to *use* what gets
built.

```
Stage 1 — BUILD the environment        (Python 3.7–3.11: pixi, or cray-python/3.11.7)
  pinned submodules ─▶ Spack: concretize ─▶ spack.lock ─▶ install ─▶ view ─▶ modulefile
                                                                       │
                                                                       ▼
            product:  working_dir/modulefiles/lfric-env/<variant>.lua  (self-contained)
                                                                       │
Stage 2 — USE the environment          (just `module load`; no pixi, no Spack)
  module load lfric-env/<variant> ─▶ rose / cylc / psyclone / spack ...
                                  └─▶ compile a science suite (scripts/build-lfric-atm.sh)
```

**Stage 1 — build (needs Python 3.7–3.11 + the submodules).** Spack concretizes and
installs the whole stack (rose, cylc, psyclone, xios, mpi, ...) into
`working_dir/`, regenerates the env view, and — as its final step — writes a
self-contained **Lmod modulefile**. The only thing pixi contributes is the Python
that *runs* Spack (Spack 1.0 needs CPython <3.12); supply that yourself and pixi
is out of the picture (`build.sh` checks it up front).

**Stage 2 — use (needs only the Stage-1 modulefile).** Everything downstream loads
the environment with `module load lfric-env/<variant>`. That module is
self-contained — it puts the Spack view, the env's own Python, rose/cylc/psyclone,
shumlib and (for the `cray` variant) the Cray MPI/IO libraries on the right paths
with no nested `module load` — so **neither pixi nor Spack is needed** to use the
environment or to build a science suite on top of it. `scripts/build-lfric-atm.sh`
is precisely that: load the module, compile `lfric_atm`, run its example.

| | Stage 1 — build | Stage 2 — use / build a suite |
|---|---|---|
| Needs | Python 3.7–3.11 + submodules + Spack | the Stage-1 Lmod modulefile only |
| With pixi | `pixi run build` | `pixi run build-lfric-atm` |
| Without pixi | `module load cray-python/3.11.7` → `bash scripts/build.sh` | `module load lfric-env/<variant>` → `bash scripts/build-lfric-atm.sh` |

pixi therefore plays three roles, all confined to Stage 1: it **bootstraps** the
Python that runs Spack, **auto-activates** the built module on every `pixi run`
(a convenience — see [Activation](#activation)), and is the **task runner** for
the table under [Tasks](#tasks). Every task wraps a script in `scripts/`, so each
has a direct no-pixi equivalent (`bash scripts/<script>`).

## Quickstart

### Stage 1 — build the environment

With pixi (it supplies the Python that runs Spack):

```bash
pixi run submodule-init   # one-time: clone the pinned submodules (needs repo access)
pixi run build            # build the Spack environment (~2-4 h from scratch)
pixi run activate         # report rose / cylc / psyclone versions
```

Without pixi (bring your own Python 3.7–3.11 — Spack 1.0 needs CPython <3.12):

```bash
module load cray-python/3.11.7                      # or any python3 in [3.7,3.12)
git submodule update --init --recursive --filter=blob:none --jobs 4   # = submodule-init
bash scripts/build.sh                               # = build
bash scripts/print-versions.sh                      # = activate
```

The second dependency variant (mpich + HDF5/netCDF from source instead of the
Cray PE libraries) is selected with `LFRIC_STACK=spack`; it coexists with the
default and shares one install tree, so only the MPI subtree is rebuilt:

```bash
LFRIC_STACK=spack pixi run build          # or: pixi run build-spack
LFRIC_STACK=spack bash scripts/build.sh   # no-pixi equivalent
```

### Stage 2 — use the environment (no pixi required)

Once Stage 1 has written the modulefile, load it for a working environment — no
pixi, no Spack:

```bash
module use working_dir/modulefiles    # absolute path also fine
module load lfric-env/cray            # or lfric-env/spack
rose --version; cylc --version; psyclone --version
```

Optionally compile the `lfric_atm` science suite against it (uses the pinned
`vendor/physics/` submodules; no build-time SSH):

```bash
bash scripts/build-lfric-atm.sh       # with the module loaded as above
pixi run build-lfric-atm              # equivalent inside pixi (auto-loads the module)
```

`build-lfric-atm.sh` compiles against whichever variant you loaded (it adopts the
loaded module's `LFRIC_STACK`), so `module load lfric-env/spack` then the command
above builds the spack stack — no extra flag needed.

Inside pixi you can skip the explicit `module load`: after `build`, **every**
`pixi run ...` (and `pixi shell`) auto-activates the environment via Lmod (see
[Activation](#activation)), so `pixi run rose --version` / `pixi run spack find`
work directly.

Expected result after a complete build (exact rose/cylc versions track the
vendored Spack builtin repo; psyclone comes from mo-spack-packages):

```
rose 2.4.2
cylc 8.4.2
PSyclone version: 3.2.2
```

## Tasks

| Task | What it does |
|------|--------------|
| `submodule-init` | Clone the pinned submodules under `vendor/` (blobless `--filter=blob:none` — full history is not fetched). Run once. |
| `stage-physics` | Set the physics + `lfric_core` submodules to their `dependencies.yaml` refs (then commit the gitlinks). The explicit way to pull in new science. |
| `patch` | Apply every `patches/*-patch.sh` (sorted, idempotent). |
| `unpatch` | Revert all patches by resetting the patched submodules. |
| `concretize` | (Re)solve the **cray** variant and write the tracked lock `spack-env/cray/spack.lock` — **without** installing. The Spack analogue of refreshing `pixi.lock`; run after bumping a pin/manifest, then commit the lock. |
| `concretize-spack` | Same for the **spack** variant (`spack-env/spack/spack.lock`). |
| `build` | Build the Spack environment, **cray** variant: apply patches, then install **from the committed lock** (re-solves only if the lock is missing or `LFRIC_RECONCRETIZE=1`). |
| `build-spack` | Same, **spack** variant — `mpich` + HDF5/netCDF from source (`LFRIC_STACK=spack`). |
| `build-lfric-atm` | Optionally compile `lfric_atm` + run its example (uses the pinned `vendor/physics/` submodules; no build-time SSH). |
| `activate` | Activate + print rose/cylc/psyclone versions (cray variant). |
| `activate-spack` | Same for the spack variant (`LFRIC_STACK=spack`). |
| `verify-xios` | Check the migrated XIOS source matches the pinned commit. |
| `print-pins` | Print the submodule pin table (Markdown) for the "Pinned versions" section. |
| `clean` | Remove `working_dir/` (keeps submodules and patches). |

`pixi run spack ...` works because activation puts the vendored Spack on `PATH`
(`vendor/spack`). The Spack environments live in `spack-env/<variant>/` (the
`spack.yaml` manifests, shared `common.yaml`, and resolved `spack.lock` are
tracked; only the generated `.spack-env/` view is git-ignored). `LFRIC_STACK`
(default `cray`) selects which variant every task operates on.

Each task is a thin wrapper around a script in `scripts/`; without pixi, run that
script directly for the same effect (e.g. `bash scripts/build.sh`, or
`git submodule update --init --recursive` for `submodule-init`).

## Activation

The built environment is loaded through **Lmod**, so **pixi is only needed to
_build_ it** — once built, loading the environment needs nothing but `module`.
It is self-contained — it puts the resolved Spack view + package prefixes on
`PATH`/`PYTHONPATH`/`SHUMLIB_ROOT`/`LD_LIBRARY_PATH`/`SPACK_ENV`/… with no nested
`module load` — so it is fast and works under `/bin/sh`.

To stay auditable, the modulefile is split in two:

- **Logic** — [`scripts/lfric-env.lua`](scripts/lfric-env.lua): version-controlled,
  syntax-highlighted Lua holding all the `setenv`/`prepend_path`/`pushenv` rules.
  Audit it once.
- **Data** — `working_dir/modulefiles/lfric-env/<variant>.lua` (generated per
  build by `scripts/gen-modulefile.sh`): a flat table of the per-build paths,
  ending in `assert(loadfile(".../scripts/lfric-env.lua"))(data)`. Trivial to
  eyeball/diff.

(Lmod's Lua sandbox forbids `dofile()` but allows `loadfile()` + passing the
table as an argument, which is how the two halves connect.)

- **Inside pixi** (the usual path): nothing to do — every `pixi run ...` /
  `pixi shell` auto-activates the `LFRIC_STACK` variant. `common.sh` puts
  `working_dir/modulefiles` on `MODULEPATH` and `activate.sh` `module load`s
  `lfric-env/$LFRIC_STACK`.
- **Outside pixi** (a Slurm job, a plain login shell — no pixi required):

  ```bash
  module use working_dir/modulefiles   # absolute path also fine
  module avail lfric-env               # -> lfric-env/cray, lfric-env/spack
  module load lfric-env/cray           # or lfric-env/spack
  ```

  The two share the module name `lfric-env`, so loading one **swaps out** the
  other; bare `module load lfric-env` resolves to the default (`cray`).

The modulefiles live under the git-ignored `working_dir/`, so they are not
tracked (their paths contain per-build content hashes). Regenerate one without a
full rebuild — e.g. after moving `working_dir` — with:

```bash
bash scripts/gen-modulefile.sh                 # cray (default)
LFRIC_STACK=spack bash scripts/gen-modulefile.sh
```

## Layout

```
pixi.toml                 # pixi project: deps, activation hook, tasks
spack-env/                # Spack envs (manifests + spack.lock tracked; .spack-env/ ignored)
  common.yaml             #   shared config included by both variants (repos, gcc, python)
  cray/spack.yaml         #   variant: system cray-mpich + Cray HDF5/netCDF (default)
  spack/spack.yaml        #   variant: mpich + HDF5/netCDF built from source
spack-repo/lfric-isambard # local repo: "lfric-apps-isambard" bundle, xios, foxml
vendor/                   # submodules (pinned)
  spack/                  # spack/spack
  spack-packages/         # spack/spack-packages (Spack builtin packages)
  lfric_apps/             # MetOffice/lfric_apps
  lfric_core/             # MetOffice/lfric_core
  mo-spack-packages/      # MetOffice/mo-spack-packages (the "metoffice" repo)
  physics/                # MetOffice casim/jules/socrates/ukca (lfric_atm science)
patches/                  # one *-patch.sh per upstream patch (sorted by prefix)
scripts/                  # common.sh, activate.sh, build.sh, gen-modulefile.sh, ...
  lfric-env.lua           #   Lmod modulefile logic (data table generated per build)
working_dir/              # git-ignored: Spack install tree, caches, env view, logs
  modulefiles/lfric-env/  #   generated Lmod modulefiles (cray.lua, spack.lua)
```

## Pinned versions

The authoritative pins live in the git index (`git submodule status`); the table
below is a convenience snapshot, **generated** by `scripts/print-pins.sh`
(`pixi run print-pins`) so it never drifts. "Nearest ref" is `git describe`
(annotated tags, matching `git submodule status`); "Pinned at" says whether the
commit sits exactly on that tag, some commits past it, or on a branch tip.

| Submodule | Commit | Nearest ref | Pinned at |
|-----------|--------|-------------|-----------|
| `vendor/spack` | `7ae1d68c` | `develop-2026-03-29` | 191 commits past tag |
| `vendor/spack-packages` | `7e330489` | `develop-2025-11-12` | 2286 commits past tag |
| `vendor/lfric_apps` | `b5aee0b1` | `vn3.1.1` | 88 commits past tag |
| `vendor/lfric_core` | `bf236737` | `2026.03.2` | 38 commits past tag |
| `vendor/mo-spack-packages` | `5e8359e0` | `main` | branch tip (untagged) |
| `vendor/physics/casim` | `b0a6e38f` | `2026.03.2` | exact tag |
| `vendor/physics/jules` | `3647a429` | `2026.03.2` | 14 commits past tag |
| `vendor/physics/socrates` | `fb97f50a` | `2026.03.2` | exact tag |
| `vendor/physics/ukca` | `1cdb9c26` | `2026.03.2` | 5 commits past tag |

`vendor/spack` and `vendor/spack-packages` track Spack's rolling `develop`, so
their nearest tag is a dated dev snapshot far behind the pinned commit (not a
release); `vendor/mo-spack-packages` follows `main` (it publishes no tags). The
Met Office repos pin a release tag (`vn*` / `YYYY.MM.x`) or a few commits past
one — those few-commits-past pins come from `lfric_apps/dependencies.yaml` (see
`stage-physics`). The fully-resolved version of *every* package (not just these
top-level sources) is the committed lock, `spack-env/<variant>/spack.lock`.

## Key version decisions

Beyond the raw pins above, a few versions are deliberate choices made *in this
repo* (with the reason), rather than whatever an unconstrained solve would pick:

- **GCC 14.3.0** (`spack-env/common.yaml`). The only *complete* Cray-native
  C/C++/Fortran toolchain on Isambard 3: the older `gcc@12.3.0` has been reduced
  to a C-only compiler (no `g++`/`gfortran`). Declared as an explicit external and
  pinned per-language so the solve never drifts to another gcc.
- **Two Pythons — 3.11 to *run* Spack, 3.12 *in* the env.** pixi pins Python
  `3.11.*` (and `cray-python/3.11.7` is the no-pixi equivalent) because Spack 1.0
  parses recipes with `ast.Str`, removed in CPython 3.12. The built LFRic
  environment then contains its *own* `python@3.12+shared` (`depends_on` in the
  `lfric-apps-isambard` bundle) — that is what LFRic uses at runtime, independent
  of the Python that ran Spack.
- **XIOS r2252** (`spack-repo/lfric-isambard/packages/xios`). LFRic Apps targets
  the former SVN revision **r2252** (`depends_on("xios@2252")`, pinned to the
  migrated Git commit `26cc7d88`). That revision predates newer GCC/libstdc++,
  which no longer expose some transitive STL headers it relies on, so it carries
  a small build patch (`gcc12_remap_standard_headers.patch`, applied `when@2252`)
  to compile under GCC 14. So the pin is *"LFRic needs this specific old XIOS,
  patched for the new compiler"* — not *"newer XIOS is broken"*. `pixi run
  verify-xios` checks the upstream commit still matches.
- **HDF5 1.14.3 / netCDF-c 4.9.2 / netCDF-fortran 4.6.1.** The `cray` variant
  externalizes the Cray parallel builds at these versions; the `spack` variant
  pins the *same* versions from source (`spack-env/spack/spack.yaml`) so the two
  variants concretize an identical downstream DAG (yaxt/xios/shumlib/lfric) and
  stay apples-to-apples.
- **cray-mpich 9.1.0** (cray variant). The system MPI; though built with gnu/12.3,
  its Fortran `.mod` files are format v15, which `gcc@14.3.0` also emits, so
  `use mpi` / `use mpi_f08` compile cleanly against it.
- **PSyclone 3.2.2, rose 2.4.2, cylc 8.4.2.** PSyclone is pinned
  (`py-psyclone@3.2.2`) via `mo-spack-packages`; rose/cylc come from the vendored
  Spack builtin repo (their exact versions track that pin).
- **py-setuptools ≤79** (`common.yaml`). Held below 80, which removed
  `easy_install` and legacy `setup.py` build commands that some Met Office Python
  packages still rely on.
- **Spack 1.0.x + `mo-spack-packages`.** The build runs on Spack 1.0 (vendored
  `develop`), and Met Office packages come from `mo-spack-packages` — the
  Spack-1.0-native (`api: v2.0`) successor to the pre-1.0 `simit-spack`, which is
  why the old `simit-*` patch set is gone (see below).

This list is the *decided* set, not the full dependency graph — for the complete
resolved set of every package and version, read the committed lock
(`spack-env/<variant>/spack.lock`).

## Patches

Each patch is a standalone, idempotent `patches/<NN>-<target>-patch.sh`,
applied in sorted order by `patch-all.sh` (discovered dynamically — names are
not hardcoded):

- `10-lfric_core-*`, `11-lfric_core-*` — Fortran/Make fixes in `vendor/lfric_core`.
- `20-spack-packages-papi-*`, `21-spack-packages-papi-*` — papi build fixes in
  `vendor/spack-packages` (no-ops at the pinned commit, kept as guards against a
  submodule bump).
- `22-spack-packages-gdbm-automake-patch.sh` — gdbm `automake` build fix in
  `vendor/spack-packages`.
- `30-lfric_apps-local-sources-patch.sh` — rewrites `get_source()` in
  `vendor/lfric_apps` so the build stages the pinned `lfric_core` + physics
  submodules in place instead of cloning/fetching them at build time (see
  *Reproducible, offline science sources* under Notes).

The Met Office package definitions are **no longer patched**: the old
`simit-spack` repo (Spack < 1.0) needed ~40 `30-/40-simit-*` patch scripts to
work under Spack 1.0, but its replacement, `mo-spack-packages`, is Spack-1.0
native (`api: v2.0`), and the cylc/rose workflow tools it used to carry now ship
in the Spack builtin repo. Those patches were therefore removed in the port.

Because every remaining patch modifies files **inside a submodule** (overwriting
tracked files), `pixi run unpatch` reverts them all by `git reset --hard &&
git clean -fd` on `lfric_core`, `lfric_apps`, and `spack-packages`. `build`
re-applies patches automatically, so it is always self-contained.

## Notes / caveats

- **Locked, reproducible solve (`spack.lock`).** Each variant's resolved
  environment is committed as `spack-env/<variant>/spack.lock` — the Spack
  analogue of `pixi.lock`. `build` installs straight from it, so a fresh checkout
  reproduces byte-identical specs and skips the multi-minute solve; the lock holds
  only concrete specs and stable system externals (`/opt/cray/...`,
  `/usr/bin/gcc-14`), no per-user paths. *Solving* and *installing* are separate
  steps: refresh the lock with `pixi run concretize` (or `LFRIC_RECONCRETIZE=1`)
  after bumping a pin or editing a manifest, then commit the new lock — its diff
  is a reviewable record of what the bump changed.
- **Blobless submodule clones.** `submodule-init` clones with
  `--filter=blob:none`: every pinned commit stays reachable (so the historical
  `spack`/`spack-packages` pins still check out — a plain shallow clone would
  not) while the hundreds of MB of *historical* file blobs are skipped, fetching
  only the checked-out commit's blobs (git lazily fetches more if you later run,
  e.g., `git -C vendor/spack log -p`). It shrinks the download and `.git` size,
  not the checked-out working trees. Drop `--filter` for a full-history clone.
- **Build output location.** Everything heavy (~7.5 GB) goes under
  `working_dir/` next to the repo. The build redirects Spack's user config and
  cache there too (`SPACK_USER_CONFIG_PATH`, `SPACK_USER_CACHE_PATH`), so it
  neither reads nor writes your global `~/.spack`. Put the repo on a filesystem
  with space (e.g. `$SCRATCH`), or set `LFRIC_WORKING_DIR` to relocate output.
- **GCC 14.3.** The compiler is declared as an explicit external in
  `spack-env/common.yaml` (`gcc@14.3.0` → `/usr/bin/{gcc,g++,gfortran}-14`) and
  pinned via per-language `require`s, so the solve is deterministic and `build`
  does *not* run `spack compiler find`. It is shared by both variants. Isambard 3
  previously shipped a complete `gcc@12.3.0` toolchain (used by earlier builds)
  but that has been reduced to a C-only compiler (no `g++`/`gfortran` 12.3);
  `gcc@14.3.0` is now the only complete cray-native C/C++/Fortran toolchain. To
  target a different gcc, edit the external + `require`s in `common.yaml`.
- **Dependency variants (`cray` / `spack`).** The MPI + parallel I/O stack is
  selectable via **`LFRIC_STACK`** (default `cray`). Each variant is its own Spack
  directory environment under `spack-env/<variant>/`, both `include:`-ing the
  shared `spack-env/common.yaml` (repos, the `gcc@14.3.0` external, python). They
  **share one install tree** (`working_dir/opt`): Spack's content-addressed store
  builds the large MPI-independent subtree (python/rose/cylc/psyclone/…) once and
  links both views to it; only the MPI-dependent subtree (mpi, hdf5, netcdf, yaxt,
  xios, shumlib, lfric) is built per variant. So both environments coexist and
  activate independently (`pixi run activate` vs `LFRIC_STACK=spack pixi run
  activate`) without rebuilding the world. `build` asserts the concretized lock
  actually matches the requested variant, so a mis-resolved external can't
  silently produce the wrong stack.
  - **`cray`** (default) uses the system **cray-mpich** (Cray PE, `PrgEnv-gnu`)
    plus the Cray **parallel HDF5/netCDF** as externals (`buildable: false`);
    `build` loads `PrgEnv-gnu` + `craype-arm-grace` + `cray-hdf5-parallel` +
    `cray-netcdf-hdf5parallel`. cray-mpich 9.1.0 is a `gnu/12.3` build, but its
    Fortran modules are *GFORTRAN module version 15* — which `gcc@14.3.0` also
    emits — so `use mpi` / `use mpi_f08` compile cleanly against it. Because the
    concretizer prunes an external's dependencies, the `libfabric`/`pmi`/`pals`
    library directories are injected through the externals' `extra_attributes` so
    dependents link and run.
  - **`spack`** builds **`mpich` + HDF5/netCDF from source**, loading no Cray
    modules (the `gcc` external is the always-present `/usr/bin/gcc-14`). HDF5,
    netCDF-c and netCDF-fortran are pinned to the **same versions** the cray
    variant externalizes (`1.14.3` / `4.9.2` / `4.6.1`, with matching `+mpi`
    variants) so the downstream DAG concretizes identically — the two stay
    apples-to-apples. It is the portable fallback; from-source `mpich` will not
    use the Slingshot/`cxi` fabric unless built with libfabric, so it is for
    correctness/CI/comparison rather than production runs. The `build-lfric-atm`
    compile for this variant uses the view's `mpif90`/`mpic++` wrappers (which
    lfric_core maps to its gfortran/g++ flag sets via `fortran/mpif90.mk` /
    `cxx/mpic++.mk`) instead of the Cray `ftn`/`CC`. Both variants are validated
    end-to-end on a `grace` node (env build + `lfric_atm` compile + example run;
    spack on `mpich@5.0.1`).
- **MetOffice SSH/SSO.** The private Met Office submodules (`lfric_apps`,
  `lfric_core`, `mo-spack-packages`, and the physics repos under
  `vendor/physics/`: `casim`, `jules`, `socrates`, `ukca`) are cloned over SSH
  and require an SSH key authorized for `MetOffice` SAML SSO (GitHub → Settings →
  SSH keys → Configure SSO), or an HTTPS credential helper (`gh auth setup-git`).
  If `submodule-init` fails on one of them, that is the usual cause.
- **Build on a compute node — keep the job small and short.** The Isambard 3
  login nodes cap user processes at `ulimit -u` 900, which a full parallel build
  (and pixi's first-time env solve) can exhaust (`fork: Resource temporarily
  unavailable`). Run the build on a `grace` compute node with the provided batch
  script:

  ```bash
  sbatch scripts/build.sbatch        # from the repo root
  ```

  The `grace` partition is usually full, so request a **small, short,
  non-exclusive** job: it backfills into the schedule far sooner than a
  whole-node (`--exclusive`) reservation, and the build is not CPU-bound past
  ~16 cores (past builds finished in ~50–70 min on 16–32 cores). This project
  standardises on **12 cores** (so `SPACK_JOBS`/`MAKE_JOBS=12`) — a good
  backfill/throughput balance. The directives `build.sbatch` uses — copy these if
  rolling your own job:

  ```bash
  #SBATCH --partition=grace
  #SBATCH --ntasks=1
  #SBATCH --cpus-per-task=12     # project default; raise only if the queue is empty
  #SBATCH --time=03:30:00        # builds take <70 min; a short limit backfills sooner
  ```

  Build the **spack** variant on a node by passing the selector through Slurm:

  ```bash
  sbatch --export=ALL,LFRIC_STACK=spack scripts/build.sbatch
  sbatch --export=ALL,LFRIC_STACK=spack scripts/build-lfric-atm.sbatch
  ```

  Both batch scripts honour **`LFRIC_USE_PIXI=0`** for the no-pixi path on a node:
  the build job then `module load`s `cray-python/3.11.7` (override with
  `CRAY_PYTHON_MODULE`) and runs `scripts/build.sh` directly; the lfric_atm job
  just runs `scripts/build-lfric-atm.sh` (the Lmod module supplies its Python):

  ```bash
  sbatch --export=ALL,LFRIC_USE_PIXI=0 scripts/build.sbatch
  sbatch --export=ALL,LFRIC_USE_PIXI=0 scripts/build-lfric-atm.sbatch
  ```

  Avoid `--exclusive`/whole-node requests and multi-hour `--time` limits — both
  push the job behind the partition's reservations. `SPACK_JOBS` defaults to
  `$SLURM_CPUS_PER_TASK`. Concretization alone is single-process and fine on the
  login node.
- **lfric_atm** is intentionally not part of `build`: it needs the private
  physics repos (casim/jules/socrates/ukca), vendored as pinned submodules under
  `vendor/physics/` and consumed via `PHYSICS_ROOT`, so the compile itself does
  no build-time cloning. The Spack environment is complete without it.
- **Reproducible, offline science sources.** `local_build.py` upstream
  auto-clones/rsyncs/git-fetches the science sources during the build (which can
  silently change the stack). `patches/30-lfric_apps-local-sources-patch.sh`
  disables that: `get_source()` now symlinks the **staged** submodules in place
  and sanity-checks them — a remote source raises instead of fetching. So the
  compile is a pure function of the checked-out submodule SHAs (`lfric_core` +
  `vendor/physics/*`). To pull in new science, bump the refs in
  `vendor/lfric_apps/dependencies.yaml`, run `pixi run stage-physics`, and commit
  the updated gitlinks — never a silent build-time change.

## Useful overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `LFRIC_STACK` | `cray` | Dependency variant: `cray` (system cray-mpich + Cray HDF5/netCDF) or `spack` (mpich + HDF5/netCDF from source). Selects the `spack-env/<variant>/` environment for every task |
| `LFRIC_RECONCRETIZE` | `0` | Set `1` so `build` re-solves and rewrites `spack.lock` instead of installing from the committed lock (what `pixi run concretize` sets). Use after bumping a pin/manifest |
| `SPACK_JOBS` | `8` | Parallel Spack make jobs (raise on a dedicated compute node; keep modest on a shared login node) |
| `HEAVY_JOBS` | `6` | Make jobs for LLVM/V8-bundling packages (`node-js`, `rust`); capped to avoid OOM (see below) |
| `HEAVY_PKGS` | `node-js rust` | Packages built first at `HEAVY_JOBS` before the rest |
| `MAKE_JOBS` | `8` | Parallel make jobs for `lfric_atm` |
| `LFRIC_WORKING_DIR` | `<repo>/working_dir` | Where build output lands |
| `PRGENV_MODULE` | `PrgEnv-gnu` | _cray variant only_: Cray PE module loaded by `build`; puts the `cray-mpich`/`libfabric`/`cray-pmi` externals on the module path + sets the `CRAY_*` lib paths (required) |
| `CRAYPE_TARGET` | `craype-arm-grace` | _cray variant only_: Cray CPU-target module (Grace / Neoverse-V2) |
| `HDF5_MODULE` / `NETCDF_MODULE` | `cray-hdf5-parallel/1.14.3.9` / `cray-netcdf-hdf5parallel/4.9.2.3` | _cray variant only_: parallel Cray HDF5/netCDF modules backing the `hdf5`/`netcdf` externals |
| `RUN_XIOS_VERIFICATION` | `1` | Set `0` to skip the XIOS network check in `build` |
| `CYLC_RUN_BASE` | `$PROJECTDIR/$USER/cylc-run` | Cylc run directory |

**Memory / OOM.** `node-js` (V8) and `rust` (LLVM) have translation units that use
several GB each; at high `-j` on a swapless or shared node they get OOM-killed
(`cc1plus: Killed signal`). `build` therefore installs the `HEAVY_PKGS` first at
`HEAVY_JOBS` (default 6) and the rest at `SPACK_JOBS`. On a busy login node use a
modest `SPACK_JOBS` (≤16); on a dedicated compute node with plenty of RAM you can
raise both.
