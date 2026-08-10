# u-dr932 — GungHo Shallow/Deep Hot Jupiter Temperature Forcing, on Isambard 3

This is **Denis Sergeev's suite**, run against this repo's environment. Not a port,
not a rewrite, and **not a copy**: the suite is a pinned submodule of his repository,
[`dennissergeev/lfric_egp_bench@e6ee57a`](https://github.com/dennissergeev/lfric_egp_bench/tree/main/src/suites/u-dr932),
and this repo carries only a **patch** against it — the same treatment Stage 1 gives
its LFRic sources.

```
vendor/lfric_egp_bench/src/suites/u-dr932            the suite (submodule, pinned)
patches/40-lfric_egp_bench-u-dr932-patch.sh          stages it: rose app-upgrade, then...
patches/40-lfric_egp_bench-u-dr932-isambard3.patch   ...this — the site diff, 419 lines
examples/science-suites/u-dr932/                     only what this repo owns: this
                                                     file, and known-issues notes
```

So the difference between what a scientist runs and what runs here is a **real diff**,
not a described one: `git apply -R` gives you his suite back, `git diff` in the
submodule shows exactly what we changed, and the patch file is directly the pull
request to send upstream. His working configuration in `rose-suite.conf` is used
as-is. Every hunk carries an `[isambard3]` comment saying what it replaced and why;
this file is the index of them.

The suite is the one from [`staging/dr932-mpi-scaling/`](../../../staging/dr932-mpi-scaling/):
it ran 3–4× slower on Isambard 3 than on Monsoon, and that investigation found why.
Everything under "Placement" below is that investigation's conclusion, applied.

## What was NOT changed

Worth stating first, because it is most of the suite:

- **The task graph, the app configs, the science.** Deep hot Jupiter forcing, C48
  multigrid, 66 levels to 4000 km, the mesh stretched by 0.5 towards (−90°, 0°), the
  `stability` physics options, dt = 50 s, 108 ranks, gnu — Denis' values, unedited.
- **The hostname → `MACHINE` detection** and every other platform's branch
  (`ex1a-monsoon`, `dial3-gnu`, `uoe-epic-gnu`, Met Office EX1). This file still works
  on those machines exactly as before; nothing here is conditional on being in this
  repo.
- **`launch-exe`.** `LAUNCH_SCRIPT` is still
  `$APPS_ROOT_DIR/rose-stem/site/meto/common/bin` — the stock Met Office launcher out
  of the extracted source. Its `RUN_METHOD=srun` path emits exactly the
  `srun <exe> configuration.nml` this run wants, so there is nothing to replace.
- **The extract mechanism.** Still `merge_sources.py` reading `dependencies.yaml`.
  Changing what gets built is the same edit you would make at the Met Office.
- **`RDEF_PRECISION=32`** and the rest of the build precisions, `PSYCLONE_TRANSFORMATION`,
  `HOUSEKEEPING`, the retry delays, the XIOS XML.

## The changes

### Environment — the Stage-1 contract

| where | change |
|---|---|
| `[[ISAMBARD3GNU]] pre-script` | `source .../UoEGCC1120SWstackBuild/RoseStemSource.sh` → source the `ACTIVATE_ENV` that `module load`s `lfric-env/<version>/<variant>`. That one module supplies the entire toolchain. `module purge` dropped (the module manages the Cray PE modules itself). |
| `[[root]] init-script` | **added.** Cylc runs each job under `bash -l`, which resets Lmod and purges the module the scheduler had loaded — the job then dies with `cylc: command not found` before any `pre-script` runs. `init-script` is the only hook early enough. |
| `[[BUILD]]` | **added** `FC = $FC`, `LDMPI = $LDMPI`, `FPP = $FPP` — inherit the compiler from the loaded module instead of hardcoding one, so `LFRIC_STACK=cray|spack` needs no edit here. |
| `platform` | `uoe-isambard3` → `isambard3`, the Slurm platform `scripts/setup-cylc.sh` writes. |

### Placement — now upstream's, not ours

This used to be the largest part of the patch. It is gone from it, because the fix
went upstream and came back: `staging/dr932-mpi-scaling/fix-u-dr932.patch` was
proposed as [lfric_egp_bench#1](https://github.com/dennissergeev/lfric_egp_bench/pull/1)
and Denis merged it, so `e6ee57a` already carries `--nodes` + `--ntasks-per-node` +
`--exclusive` + `--mem=0`, `NUMA_REGIONS_PER_NODE = 2`, and the `LFRIC_ATM_PPN`
derivation. **We now inherit the placement rather than imposing it** — which is the
whole point of carrying a patch instead of a copy: the delta shrinks as upstream
absorbs what was site-specific.

What upstream cannot know, and the patch still adds, is one line's worth: under
`RUN_METHOD=srun`, `--export=NONE` needs `export SLURM_EXPORT_ENV=ALL` in the family
pre-script, or every `srun` step starts with no environment at all (measured: the step
cannot even find `bash`). That is inert under Hydra, which is what upstream runs.

Upstream's merge also brought `SITE_MPI_LAUNCHER_OPTS = -bind-to core -ppn … -n …`.
It is **inert here** and left untouched: `launch-exe` only reads it inside its
`RUN_METHOD = mpiexec` branch. Verified with the launcher's own `TEST_LAUNCH_EXE_EXEC`
mode — with the variable set and `RUN_METHOD=srun`, the emitted command is still
exactly `srun <exe> configuration.nml`.

Still ours on the placement axis: `RUN_METHOD = srun` instead of `mpiexec`, because
srun is what binds cray-mpich to Slingshot's `cxi` provider through the Cray PMI and
pins one rank per core — and the cray environment ships no `mpiexec` at all.

Two other Slurm fixes, in tasks that are not the model:

- `build`: `--ntasks=6 --mem-per-cpu=10G` → `--nodes=1 --ntasks=1 --cpus-per-task=6
  --mem=40G`. `make -j6` is six *threads in one task*; as six tasks Slurm may scatter
  them over six nodes and confine each to one core. `--export=NON` (sic) → `NONE`.
- `generate_mesh`: `--ntasks=6` → 1. The command is a single-rank mesh generator.

### Version — vn3.1 → vn3.2

This repo's environment is built against LFRic `2026.07.1` (apps vn3.2); the suite was
written for `2026.03.1` (vn3.1). **This is not in the patch file** — the staging script
*runs* the native tool, `rose app-upgrade -C <app> vn3.2`, over the submodule. Carrying
its ~2000-line mechanical diff would have drowned the reviewable part, and it is not
upstreamable anyway: Denis is on vn3.1 and does not want a vn3.2 config. Bump
`SUITE_META_VN` in the patch script when the `vendor/lfric_apps` pin moves.

The upgrade ran clean on both apps:

- `app/lfric_atm`: renames (`pc2ini`→`pc2_init_method`, `i_bm_ez_opt`→`bm_ez_opt`,
  `i_update_precfrac`→`update_precfrac_opt`, …), the new vn3.2 members at their macro
  defaults, `jules_pftparm` into its indexed per-PFT form, and the
  `initialization`→`orography` moves. The additions are not cosmetic: LFRic
  initialises new namelist members to RMDI and then range-checks them, so a missing
  one is a hard abort.
- `app/mesh`: `planar_mesh apply_stretch_transform` → `stretch_function`.

`rose macro --validate` then reports four things on `lfric_atm` and three on `mesh`,
none of them applicable to this run and none of them introduced here:

- `partitioner='cubedsphere'` — an artefact of validating outside a job, where
  `TOTAL_RANKS` is not in the environment (the rule is `TOTAL_RANKS % 6 == 0`; 108 is);
- `dl_base > domain_height` in the `l16/l32/l64_3300km` optional configs, which this
  run does not select (`LFRIC_LEVS=''`);
- three `namelist:stretch_transform` members that vn3.2 makes compulsory
  (`n_cells_outer_wsen`, `n_cells_stretch_wsen`, `poly_power`) and the vn3.1→vn3.2
  macro does not add. The section is `[!!namelist:stretch_transform]` — ignored, never
  written to `mesh_generation.nml`, and unused by a cubed-sphere mesh — so the config
  is left exactly as the macro produced it rather than filled in with invented values.
  The mesh task runs.

`dependencies.yaml` moves from `2026.03.1` to `2026.07.1` — **and drops the fork**.
Upstream it pins `lfric_apps` to `tommbendall/lfric_apps@4d8b921`
(`TBendall/deep_hot_jupiter_forcing`), because at vn3.1 the deep hot Jupiter forcing
lived only there. It is in mainline now: `2026.07.1` carries
`deep_hot_jupiter_forcings_mod.F90` and `theta_forcing='deep_hot_jupiter'` in the
`lfric-gungho` vn3.2 metadata, which is what `CASE_SETUP=''` selects.

### Small things

| where | change |
|---|---|
| `app/mesh/rose-app.conf` | `mpiexec -n 1` → `srun --ntasks=1`. Same one rank. |
| `rose-suite.conf` `[file:bin/*]` | `git:localmirrors:` → the github https URL. `localmirrors:` needs a Met Office git alias that does not exist here; the repositories are public, so no token is needed. |
| `app/extract/rose-app.conf` | `patch-sources.sh` appended to each command key — see below. The three command keys themselves are upstream's. |
| `rose-suite.conf` `USE_MIRRORS`/`USE_TOKENS` | `true`/`true` → `false`/`true`. There is no Met Office mirror host here, so the default extract clones from github. |
| `rose-suite.conf` `EXPT_RUNLEN` | `P1200D` → `P10D`. One cycle rather than 120 — the only change to Denis' configuration itself. Same 17280-timestep job. |
| `rose-suite.conf` `VN` | `'3.1'` → `'3.2'`, for consistency. Nothing reads it. |
| `lfric_atm` environment | added `MPICH_ENV_DISPLAY` / `MPICH_OFI_NIC_VERBOSE`, so `job.out` records the OFI provider — `provider: cxi` is the one-line proof the run is on Slingshot. |

### The one thing this repo adds to the extract

`site/patch-sources.sh`, appended to the extract command. It applies this repo's
LFRic-source patch stack (`patches/*-lfric_{core,apps}-*`) to the freshly cloned
tree — the same patches the environment build and the minimal-compile example use.
Two of the four matter here: `30-lfric_apps-local-sources` stops the apps build
re-cloning its own science sources mid-compile, and
`31-lfric_apps-slow-physics-mphys-field` fixes a vn3.2 regression that aborts a
forcing-only configuration.

## What was observed on this environment

Ran end-to-end on the **cray** environment (`lfric-env/v2026.07.21/cray`), one Grace
node, 108 ranks, `--exclusive`:

| step | |
|---|---|
| `extract` | 73 s — six repos cloned from github over https on the compute node, then the patch stack |
| `build_mesh` / `build_lfric_atm` | 1 min 46 s / 14 min 56 s (both from the same `extract`) |
| `generate_mesh` | 3 s — with `equatorial_latitude=36.87` (from `STRETCH_FACTOR=0.5`) and `target_north_pole=-90,0`, i.e. Denis' stretched, rotated mesh |
| `lfric_atm` | **1 h 37 m** for the full 17 280-timestep cycle (dt = 50 s, P10D), `COMPLETED` |

Run twice: once before the suite became a submodule and `--export=NONE` was restored
(1 h 36 m 43 s), once after (1 h 37 m 37 s). The two agree **bit for bit** — same final
dry mass to all 24 printed digits, same final `u_in_w3` to the last decimal, same output
file sizes to the byte — which is the evidence that the refactor changed how the suite is
staged and nothing about what it computes.

The stock Met Office launcher emitted exactly `srun <exe> configuration.nml`, and XIOS
wrote its output attached (no dedicated server), as this suite's `XIOS_SERVER_MODE=False`
asks: `lfric_diag_latlon` (27.6 MB), `lfric_diag_main` (30.1 MB), `lfric_diag_cnsrv`
(8.5 MB) and `lfric_initial` (23.9 MB). Dry mass drifts by 4.7 × 10⁻⁷ relative over the
cycle, and the winds plateau (`u_in_w3` reaches −8.5 / +5.8 km s⁻¹ and stops growing) —
spin-up from rest, not divergence.

**Against Denis' own `sacct` for the same 17 280-timestep cycle at the same 108 ranks —
5 h 07 m to 8 h 59 m — this is 3.2× to 5.6× faster.** Worth being precise about what
that does and does not compare: it is the same suite and the same work, but it is not a
controlled A/B. Three things differ at once — placement (1 node, pinned, exclusive vs 9
to 32 nodes unpinned), MPI (cray-mpich over Slingshot vs a from-source `ch3:nemesis`
MPICH falling back to TCP on a 1 GbE link), and the stack itself (gfortran 14.3 on
vn3.2 vs 12.3 on vn3.1). `staging/dr932-mpi-scaling/` separates the first two by direct
measurement; the third is unquantified here.

### Two things worth reporting back

**1. The energy-conservation diagnostics read `Infinity`, from timestep 1.** A 32-bit
overflow in one kernel's intermediates, not a model blow-up: the solver converges every
step, mass is conserved to 4.7 × 10⁻⁷ over the cycle, and a 64-bit control build gives
finite values. It is an upstream bug, not a misconfiguration, and this suite reproduces
it in ~10 minutes. Written up in full, with the open questions and how to verify a fix,
in [`known-issues/energy-diagnostics-overflow-at-32-bit.md`](known-issues/energy-diagnostics-overflow-at-32-bit.md).
`RDEF_PRECISION` is left at Denis' 32.

**2. The first-step winds are round-off dominated at 32-bit.** Starting from rest,
`u_in_w3` after one 50 s step is ±1.5 m s⁻¹ at `RDEF_PRECISION=32` and ±0.13 m s⁻¹ at
64 — about 10×, in a field whose true value is near zero. Both then spin up. Possibly
the same root cause as (1), possibly not; see that file's open questions.

No comparison against Denis' own output was possible: his `cylc-run` had been cleaned.

## Running it

From the repo root, on a **login node** — the Cylc scheduler lives there and submits
each task to Slurm itself:

```bash
bash examples/science-suites/run-suite.sh u-dr932
cylc tui u-dr932            # watch
```

See [`../README.md`](../README.md) for what `run-suite.sh` does, the equivalent bare
`cylc` commands, and how to drive the run afterwards.

### Regenerating the patch

When Denis moves the submodule pin, or the environment's LFRic version changes:

```bash
. examples/science-suites/site/activate-env.sh
export ROSE_META_PATH=$(find vendor/lfric_{apps,core} -type d -name rose-meta | tr '\n' ':')

# a/ = upstream at the new pin, upgraded; b/ = a/ plus the five site-edited files
git -C vendor/lfric_egp_bench stash            # park the current patch
mkdir -p /tmp/pg/{a,b}/src/suites
cp -r vendor/lfric_egp_bench/src/suites/u-dr932 /tmp/pg/a/src/suites/
(cd /tmp/pg/a/src/suites/u-dr932/app && rose app-upgrade -y -C lfric_atm vn3.2 \
                                     && rose app-upgrade -y -C mesh vn3.2)
cp -r /tmp/pg/a/src/suites/u-dr932 /tmp/pg/b/src/suites/
#   ... re-apply the five site edits to /tmp/pg/b (flow.cylc, rose-suite.conf,
#       dependencies.yaml, app/extract/rose-app.conf, app/mesh/rose-app.conf) ...
(cd /tmp/pg && diff -ruN a b) > patches/40-lfric_egp_bench-u-dr932-isambard3.patch
```

Keep the patch to those five files: anything mechanical belongs in the upgrade step,
not here.

To go back to something closer to upstream behaviour:

```bash
# extract offline from this repo's vendored submodules instead of github
bash examples/science-suites/run-suite.sh u-dr932 \
  -S USE_MIRRORS=true -S "MIRROR_LOC='$PWD/vendor/mirrors'"
# Denis' full 120-cycle campaign
bash examples/science-suites/run-suite.sh u-dr932 -S EXPT_RUNLEN=P1200D
```
