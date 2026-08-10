# u-dr932 — GungHo Shallow/Deep Hot Jupiter Temperature Forcing, on Isambard 3

This is **Denis Sergeev's suite**, run against this repo's environment. Not a port,
not a rewrite: the files here are
[`dennissergeev/lfric_egp_bench@ffe611e`](https://github.com/dennissergeev/lfric_egp_bench/tree/main/src/suites/u-dr932)
`src/suites/u-dr932`, with his own working configuration in `rose-suite.conf`, and a
short list of changes confined to the `isambard3-gnu` branch. Every change is marked
`[isambard3]` in a comment at the point it applies, saying what it replaced and why.
This file is the index of them.

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

### Placement — the fix from `staging/dr932-mpi-scaling/`

The `lfric_atm` directives were `--mem-per-cpu=8G --ntasks=N --cpus-per-task=1
--export=NONE`, with **no node count**. On a busy machine Slurm satisfied 108 ranks
out of whatever had room — 9 to 32 nodes, 1–13 ranks each, 5 h to 9 h on identical
work. Now:

- `--nodes` + `--ntasks-per-node` (108 ranks fit on one 144-core Grace node);
- `--mem=0`, so a memory request can never cap ranks-per-node and fan the job out
  (measured peak for this configuration is 8–35 GB for the *whole* job, against
  225 GB on a node);
- `--exclusive`, because `SelectType=select/cons_tres` hands out cores, not machines;
- `RUN_METHOD = srun` instead of `mpiexec` — srun binds cray-mpich to Slingshot's
  `cxi` provider through the Cray PMI and pins one rank per core. The cray
  environment ships no `mpiexec` at all;
- `NUMA_REGIONS_PER_NODE` 0 → 2, and `CORES_PER_NODE` was already 144 here.

**`--export=NONE` removed** — this one is a trap rather than a tuning choice.
`sbatch --export=NONE` also sets `SLURM_EXPORT_ENV=NONE` inside the job, which every
`srun` in that job inherits: the model would start with none of the environment the
`module load` just set up. Harmless under Hydra, fatal under srun.

Two other Slurm fixes, in tasks that are not the model:

- `build`: `--ntasks=6 --mem-per-cpu=10G` → `--nodes=1 --ntasks=1 --cpus-per-task=6
  --mem=40G`. `make -j6` is six *threads in one task*; as six tasks Slurm may scatter
  them over six nodes and confine each to one core. `--export=NON` (sic) went with it.
- `generate_mesh`: `--ntasks=6` → 1. The command is a single-rank mesh generator.

### Version — vn3.1 → vn3.2

This repo's environment is built against LFRic `2026.07.1` (apps vn3.2); the suite was
written for `2026.03.1` (vn3.1). The app configs were upgraded with the **native tool**,
`rose app-upgrade -C <app> vn3.2`, which ran clean on both:

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
| `app/extract/rose-app.conf` | `patch-sources.sh` appended to each command key — see below. `--mirror_loc` now points at this repo's vendored submodules. |
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
| `lfric_atm` | see the timing note below |

The stock Met Office launcher emitted exactly `srun <exe> configuration.nml`, and XIOS
wrote its output attached (no dedicated server), as this suite's `XIOS_SERVER_MODE=False`
asks.

### Two things worth reporting back

**1. The energy-conservation diagnostics read `Infinity`, from timestep 1.** This is a
32-bit overflow, not a model blow-up. `conservation_algorithm_mod` accumulates the
totals in `r_def`, and this suite builds `RDEF_PRECISION=32`; the kinetic-energy sum
over a 9.44 × 10⁷ m planet exceeds the single-precision ceiling of 3.4 × 10³⁸. Verified
by rebuilding the same suite at `RDEF_PRECISION=64` and running 72 steps: horizontal
kinetic energy comes out finite at 3.03 × 10¹⁹ J and total energy at 2.48 × 10³² J.
Nothing else is affected — the solver converges every step, the prognostic fields stay
finite, and `Min/max u ≈ 10¹⁴` is the raw W2 flux dof (`u_in_w3`, the physical wind, is
O(1–10³) m/s), which is identical in both builds. The precision is Denis' own build
setting and is left as he has it; raising it is the fix if those diagnostics are wanted.

**2. The first-step winds are round-off dominated at 32-bit.** Starting from rest,
`u_in_w3` after one 50 s step is ±1.5 m/s at `RDEF_PRECISION=32` and ±0.13 m/s at 64 —
about 10×, in a field whose true value is near zero. Both then spin up.

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

To go back to something closer to upstream behaviour:

```bash
# extract offline from this repo's vendored submodules instead of github
bash examples/science-suites/run-suite.sh u-dr932 -S USE_MIRRORS=true
# Denis' full 120-cycle campaign
bash examples/science-suites/run-suite.sh u-dr932 -S EXPT_RUNLEN=P1200D
```
