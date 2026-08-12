# u-dt000 — LFRic Atm, Uranus/Neptune (ice giant) temperature forcing, on Isambard 3

This suite is **not a copy in this repo**, and not a vendored one either. It is Denis
Sergeev's Met Office rose suite, checked out from where it actually lives:

```
https://code.metoffice.gov.uk/svn/roses-u/d/t/0/0/0/trunk   @ r348703
```

plus a patch — the same treatment [`u-dr932`](../u-dr932/README.md) gets, and the same
treatment Stage 1 gives its LFRic sources.

```
~/roses/u-dt000                                      the suite (rosie checkout, pinned by revision)
patches/suites/41-roses-u-u-dt000-patch.sh           stages it: rose app-upgrade, then...
patches/suites/41-roses-u-u-dt000-isambard3.patch    ...this — the site diff, 434 lines
patches/optional/32-lfric_apps-ice-giants-forcing*   the science: Denis' branch, forward-ported
examples/science-suites/u-dt000/                     only what this repo owns: this file
                                                     and known-issues notes
```

`svn revert -R ~/roses/u-dt000` gives the upstream suite back; `svn diff` in the checkout
shows exactly what we changed. Every hunk carries an `[isambard3]` comment saying what it
replaced and why; this file is the index of them.

> **An earlier version of this branch had this suite wrong.** It pinned
> UniExeterRSE's repository as the upstream. That repository does contain the suite —
> as an `svn checkout`, `.svn` metadata and all — but what it holds is upstream *plus
> UniExeterRSE's own Isambard 3 port, and their bespoke `git_extract_lfric` in place of
> the Met Office extract. Treating it as upstream meant carrying a third party's
> porting decisions as if they were the Met Office's. Since then upstream has moved on
> (r348703, 2026-03-05): it now has `app/extract` with `merge_sources.py`, a
> `dependencies.yaml`, and no `fcm_make_extract_lfric` — i.e. the Met Office did most
> of what our patch was doing by hand.

> **Getting it needs a MOSRS account.** `roses-u` is not anonymously readable, and rose
> workflows are staying in subversion —
> [simulation-systems#566](https://github.com/MetOffice/simulation-systems/discussions/566)
> moved the *source* extraction to git, explicitly *"not where the workflows themselves
> reside"*. `rosie checkout u-dt000` is the fetch; see
> [`../README.md`](../README.md), "Getting a suite from MOSRS".

## The blocker, and what actually fixed it

For a long time this suite got as far as `build_lfric_atm` and then died on the first
line of its own science:

```
Cannot match namelist object name held_suarez_sigma_b
STOP 1
```

The suite's science is `theta_forcing='ice_giants_obs_like'` in
`namelist:external_forcing`. That value exists in **no MetOffice tag** — not in the
`vn2.2` this suite declared, and not in the `2026.07.1` (vn3.2) this environment
builds. It lives on one branch, and Denis told us which:

> This brings me to the question about `theta_forcing='ice_giants_obs_like'`. This
> option requires my lfric_apps branch:
> [dennissergeev/lfric_apps at ice_giants_tf](https://github.com/dennissergeev/lfric_apps/tree/ice_giants_tf).
> The slight problem is that the branch is still at vn3.0 and I haven't found time to
> upgrade it yet.

Two commits on that branch are the science — `b57ddcc9` (the forcing) and `1d4b42b8`
(the metadata) — and between them they do three things:

1. add `ice_giants_forcings_mod.F90` + `ice_giants_kernel_mod.F90` and the
   `ice_giants_obs_like` case in `external_forcing_alg_mod.X90`;
2. add `ice_giants_obs_like` to the `theta_forcing` metadata;
3. **turn `SIGMA_B` and the Held-Suarez relaxation rates from hardcoded Fortran
   `parameter`s into namelist items** — `held_suarez_sigma_b`,
   `wind_relax_time_scale`, `theta_relax_time_scale`.

(3) is the error above, exactly: the suite sets `held_suarez_sigma_b=0.97`, and on any
mainline LFRic that name is a compile-time constant, not a namelist field. No amount of
namelist forward-porting could ever have fixed it — which is why the earlier diagnosis
("blocked on an unidentified fork") was right about the shape and could not close it.

### Why the branch is a patch here, not a `dependencies.yaml` entry

The Met Office `dependencies.yaml` supports exactly this case — list mainline, then
list your fork, and `merge_sources.py` merges them:

```yaml
lfric_apps:
    - source: git@github.com:MetOffice/lfric_apps.git
      ref: 2026.07.1
    - source: git@github.com:dennissergeev/lfric_apps.git
      ref: ice_giants_tf
```

That is what this suite *should* say, and it is what it will say once Denis has had
time to rebase. It does not work today: his branch is still based on `vn3.0`, and
merging it onto `2026.07.1` conflicts in
`science/gungho/rose-meta/lfric-gungho/HEAD/rose-meta.conf`, where mainline has since
added a `'nudging'` option to the same two `values=`/`value-titles=` lines his branch
adds `'ice_giants_obs_like'` to. `merge_sources.py` auto-accepts conflicts only under
`rose-stem/` and in `dependencies.yaml`; anything else is a hard error, so the extract
task would fail before the build ever started.

So the merge is done here instead, once, and carried as
[`patches/optional/32-lfric_apps-ice-giants-forcing.patch`](../../../patches/optional/32-lfric_apps-ice-giants-forcing.patch)
— 312 lines over five files, applied to the extracted tree by the suite's own
`git_extract_lfric` task. The conflict resolution is the union of the two: his
`ice_giants_obs_like` inserted where he put it (after `deep_hot_jupiter`), mainline's
`nudging` kept last, and his `held_suarez_sigma_b` trigger appended to mainline's
`wind_forcing` trigger list. The regeneration recipe is in the header of
`32-lfric_apps-ice-giants-forcing-patch.sh`, and that `.patch` file is directly what to
hand back to Denis.

**It is opt-in, and has to be.** The three new metadata items are `compulsory=true`, so
the moment that metadata is in the tree every gungho app config must set them —
u-dr932 and u-dn704 do not, and would start aborting on their own namelists. That is
why the patch lives in `patches/optional/` outside the shared stack, and why this
suite invokes it by path from its extract task rather than inheriting it. See
[`patches/optional/README.md`](../../../patches/optional/README.md).

**One defect in it is known and unfixed**, in Denis' code rather than our forward-port:
making the Held-Suarez relaxation rates namelist-driven left the *temperature*
relaxation reading `wind_relax_time_scale`, so `theta_relax_time_scale` has no effect on
`theta_forcing='held_suarez'` or `'tidally_locked_earth'`. It is inert for this suite —
our theta path is `ice_giants_obs_like`, and the two timescales are equal anyway — but
it is a trap for the next configuration, and it should go back to Denis with the patch.
Written up in
[`known-issues/held-suarez-theta-relaxation-uses-the-wind-timescale.md`](known-issues/held-suarez-theta-relaxation-uses-the-wind-timescale.md).

## What was NOT changed

Worth stating first, because it is most of the suite:

- **The science.** `theta_forcing='ice_giants_obs_like'`, `held_suarez_sigma_b=0.97`,
  `theta_relax_time_scale=100.0`, `wind_relax_time_scale=100.0`, C48 multigrid, 50
  levels over a 3.0 × 10⁵ m domain at a 2.527 × 10⁷ m planet radius, dt = 120 s,
  108 ranks, analytic initialisation, gnu. All the suite's own values.
- **The task graph** (`git_extract_lfric → build_* → generate_mesh → lfric_atm`), the
  task names, and every other platform's branch (`ex`, Met Office ex1a). The file still
  renders unchanged off Isambard 3; nothing here is conditional on being in this repo.
- **`launch-exe`.** `LAUNCH_SCRIPT` is still
  `$APPS_ROOT_DIR/rose-stem/site/meto/common/bin` — the stock Met Office launcher out
  of the extracted source. With `RUN_METHOD=srun` it emits exactly
  `srun $BIN_DIR/lfric_atm configuration.nml`, so there is nothing to replace.
- **XIOS attached** (`XIOS_SERVER_MODE=False`, upstream's value). Same as u-dr932; no
  dedicated server, no `srun --multi-prog`.
- **The build precisions**, `PSYCLONE_TRANSFORMATION`, the XIOS XML, `TOTAL_RANKS_REQ=108`.

## The changes

### Source — upstream's own extract, extended

**This used to be the largest hunk in the patch and is now not in it at all.** The
version of this suite in UniExeterRSE's repository had a bespoke `app/git_extract_lfric`
— a ~60-line inline shell script that cloned `lfric_apps@vn2.2` and `lfric_core@core2.2`
over SSH and read the physics revisions out of `lfric_apps/dependencies.sh` — and our
patch replaced it with the Met Office extract. Real upstream (r348703, 2026-03-05) has
since done that itself: `app/extract` runs `merge_sources.py` over a `dependencies.yaml`,
with `USE_MIRRORS` / `USE_TOKENS` / `MIRROR_LOC` wired through `ROSE_APP_COMMAND_KEY`,
exactly as u-dr932 and u-dn704 do. Basing on the real upstream deleted ~160 lines of our
own diff.

Two `[isambard3]` steps are appended to the clone rather than replacing it:
`site/patch-sources.sh` (this repo's LFRic-source patch stack), then this suite's
ice-giants forcing patch. The `[file:bin/*]` sources move off `git:localmirrors:` to
https — `localmirrors:` is a git alias a Met Office site configures, and there is no
mirror host here.

### Environment — the Stage-1 contract

| where | change |
|---|---|
| `[[root]] init-script` | **added.** Cylc runs each job under `bash -l`, which resets Lmod and purges the module the scheduler had loaded — the job then dies with `cylc: command not found` before any `pre-script` runs. `init-script` is the only hook early enough, and it is also before the task `[[[environment]]]` block, so the module selection is exported there. |
| `[[root]] env-script` | **added** `eval $(rose task-env)`, so `ROSE_DATA` exists for the `lfric_atm` task's inline `mkdir` (which runs under `set -u`, before `rose task-run`). |
| `[[BUILD]]` | `FC`/`LDMPI` `= mpif90` and `FPP = "cpp -traditional-cpp"` → `= $FC` / `$LDMPI` / `$FPP`. Inherit the compiler from the loaded module instead of naming one, so `LFRIC_STACK=cray\|spack` needs no edit here. |
| `rose-suite.conf` `EX_HOST` | `'ex'` (Monsoon) → `'isambard3'`, the switch that selects the new `ISAMBARD3` family; `ISAMBARD3_RUN_PARTITION` / `ISAMBARD3_SHARED_PARTITION` / `ACTIVATE_ENV` added alongside it. `run-suite.sh` injects the real `ACTIVATE_ENV` path via `cylc vip -S`. |
| `[[ISAMBARD3]]` | **added**, alongside upstream's `[[EX1A]]` — `platform = isambard3`, `RUN_METHOD = srun`, and no module loads of its own, because the root `init-script` has already loaded ours. Every `EX1A` branch is untouched, so the file still renders as upstream elsewhere. |
| `[[root]] [[[environment]]]` | **added** `REPO_ROOT`, `LFRIC_STACK`, `LFRIC_PREFIX`. |

### Placement

`LPPN` 128 → **144**: an Isambard 3 Grace node is 2 sockets × 72 cores; 128 is the Met
Office EX1A number, and under-counting it inflates `LFRIC_NODES` and splits the job
over the fabric for no reason. From that, `LFRIC_PPN` is derived and the `lfric_atm`
directives gain `--ntasks-per-node`, `--exclusive` and `--mem=0` — the conclusion of
[`staging/dr932-mpi-scaling/`](../../../staging/dr932-mpi-scaling/), which measured a
5 h-to-9 h spread on identical work when Slurm was left to place the ranks itself.
`--mem=0` is needed *alongside* `--exclusive`: exclusive gives all the CPUs but memory
still follows `DefMemPerCPU`, and ~1 GB/rank OOM-kills `lfric_atm`.

At `TOTAL_RANKS_REQ=108` that is one node, 108 ranks, exclusive — the same shape
u-dr932 runs.

### Version — vn3.0 → vn3.2

Upstream is at `vn3.0`; this environment builds `2026.07.1` (vn3.2). **This is not in
the patch file** — the staging script *runs* the native tool,
`rose app-upgrade -C <app> vn3.2`, over the checkout. Bump `SUITE_META_VN` in the patch
script when the `vendor/lfric_apps` pin moves.

(The gap used to be `vn2.2 → vn3.2`, when this suite was taken from UniExeterRSE's
older copy. Upstream has since done the vn2.2 → vn3.0 leg itself. Sister suite u-dn704
now needs no upgrade step at all, for the same reason.)

The upgrade needs `vendor/physics` on `ROSE_META_PATH` as well as
`vendor/lfric_{apps,core}` — the macros reach for `jules-lfric` metadata, which lives in
the jules submodule. Use ABSOLUTE paths: `rose` runs from inside the app directory, and
a relative entry fails with the unhelpful `[FAIL] Error: could not find meta flag`.

That this works at all is worth recording, because the previous state of this suite in
this repo was a **hand** forward-port that got as far as it could by fixing whatever the
model complained about next. The tool's output and that hand port differ by ~1100 lines.
The lesson is u-dr932's, again: run the native tool on a config that is genuinely at the
version it claims, and it is fine.

`dependencies.yaml` declares `2026.07.1` for all six repositories, which is what this
environment was built and validated against — so the `mirrors` extract path can serve
them offline from `vendor/mirrors/`.

### Small things

| where | change |
|---|---|
| `app/build_lfric_atm/rose-app.conf` | `local_build.py -a lfric_atm … -u ${LFRIC_TARGET_PLATFORM}` → the vn3.x CLI: project positional, `-p ${PSYCLONE_TRANSFORMATION}`. Version alignment the namelist upgrade does not cover, because this file is a command, not a config. |
| `app/mesh/rose-app.conf` | `mpiexec -n 1` → `srun --ntasks=1`. The cray environment is cray-mpich and ships no `mpiexec`. Same one rank. |
| `[scheduler]` | **added** `install = dependencies.yaml` — not one of the paths `cylc install` copies by default, and `merge_sources.py` reads it out of the installed run directory. |
| `lfric_atm` environment | **added** `MPICH_ENV_DISPLAY` / `MPICH_OFI_NIC_VERBOSE`, so `job.out` records the OFI provider — `provider: cxi` is the one-line proof the run is on Slingshot rather than TCP. |
| `rose-suite.conf` `EXPT_RUNLEN` | `P10000D` → `P100D`. One cycle rather than 100 — the only change to the run itself. Same 72 000-timestep job. |
| `rose-suite.conf` `LFRIC_CPU` | `PT2H` → `PT12H`, the Slurm `--time`. One cycle is 72 000 timesteps; u-dr932's 17 280 timesteps of comparable work take 1 h 37 m on the same node count, so `PT2H` was never going to be enough. |
| `rose-suite.conf` `VN` | `'2.2'` → `'3.2'`, matching `dependencies.yaml` and the app `meta=`. Nothing reads it. |
| `rose-suite.conf` `[file:bin/tweak_iodef]` | `::core2.2` over ssh → `::main` over https. Clones anonymously, no SSO. |

## What was observed on this environment

**It runs end-to-end.** First time this suite has got past its own namelists.
Validated on the **cray** environment (`lfric-env/v2026.07.21/cray`), one Grace node,
108 ranks `--exclusive`:

| step | |
|---|---|
| `git_extract_lfric` | 32 s — six repositories cloned from github over https on the login node, then the patch stack, then the ice-giants forcing patch |
| `build_mesh` / `generate_mesh` | 2 m 39 s / 5 s |
| `build_lfric_atm` | 15 m 18 s |
| `lfric_atm` | **3 h 56 m 20 s** for the full 72 000-timestep cycle (100 days at dt = 120 s), `COMPLETED` |

The forcing is demonstrably the one we came for: `slow_physics: Running Ice Giants
obs-like theta forcing` appears at **every** timestep, from 1 to 72 000. Before this
work the same suite stopped at `Cannot match namelist object name
held_suarez_sigma_b` / `STOP 1` while reading its namelists, having never taken a step.

Health of the integration, over the whole cycle:

- **Dry mass conserved to 1 × 10⁻¹³ relative** — `0.902491049911896637E+21` at
  initialisation against `0.902491049911807902E+21` at timestep 72 000.
- **No `NaN`, no `Infinity`, no `ERROR` or `WARNING`** anywhere in the 4.5 M-line
  model log. Worth noting against
  [u-dr932's open issue](../u-dr932/known-issues/energy-diagnostics-overflow-at-32-bit.md):
  this suite runs at `RDEF_PRECISION=64` and its conservation block prints finite
  values throughout, which is consistent with that overflow being a 32-bit
  intermediates problem rather than a model blow-up.
- **Bounded, not diverging.** The W2 wind dofs rise from ~7 × 10⁸ at timestep 1 and
  plateau at ~6 × 10¹² by ~timestep 2 000, then stay there for the remaining 70 000
  steps; `theta` stays in 171–1550 K. Transport Courant numbers stay ~10⁻³ and the
  BLOCK_GCR solver converges every step.
- **XIOS wrote everything, attached, on Lustre**: 20 diagnostic files, one native-grid
  and one lat-lon per 10-day chunk (~29 MB and ~26 MB each), plus `lfric_initial.nc`
  (18 MB) — 3.4 GB in total — and the end-of-cycle checkpoint.

**What this does not establish is the science.** The run is numerically healthy and the
forcing is active, but nobody has compared these fields against Guendelman & Kaspi
(2025) or against Denis' own output, and the wind magnitudes above are raw W2 degrees of
freedom (fluxes scaled by face area at a 2.527 × 10⁷ m planet radius), not velocities in
m s⁻¹. Treat this as "the suite now runs its intended forcing on this environment", not
as a validation of the result.

The environment reaches the `srun` step — `MPICH_ENV_DISPLAY` output appears in the
step's stderr, and nothing in the binary or its RPATH supplies that. There is no
`provider: cxi` line to point at, and there should not be: this is a single-node job, so
cray-mpich never brings up the OFI netmod for inter-node traffic. u-dn704 is where the
Slingshot path is exercised.

### Two build failures on the way, both worth recording

**1. `chi2llr` gained four arguments between vn3.0 and vn3.2.** Denis' kernel called the
old 7-argument form and would not compile:

```
ice_giants_kernel_mod.F90:135:
  call chi2llr(coords(1), coords(2), coords(3), ipanel, lon, lat, radius)
Error: Type mismatch in argument 'geometry'; passed REAL(8) to INTEGER(4)
```

Mainline updated all of its own external_forcing kernels for that (`vn3.0`'s
`deep_hot_jupiter_kernel_mod` has the identical old call; `vn3.2`'s has the new one).
**Git cannot see this class of breakage** — the change is in a file the branch never
touched, so the merge is clean and the compile is not. It is now part of the
forward-port patch, and its header says to diff the branch's call sites against the
sibling kernels first when regenerating.

**2. `$CYLC_TASK_WORK_DIR` is shared across retries**, so the second attempt found both
the PSyclone-generated `jules_extra_kernel_mod.f90` and the source `.F90` and died with
`More than one match for kernel file`. A re-run artefact only — a fresh run never sees
it — but if you `cylc trigger` a failed `build_lfric_atm`, delete
`work/<cycle>/build_lfric_atm/` first.

## Running it

From the repo root, on a **login node** — the Cylc scheduler lives there and submits
each task to Slurm itself:

```bash
bash examples/science-suites/run-suite.sh u-dt000
cylc tui u-dt000            # watch
```

See [`../README.md`](../README.md) for what `run-suite.sh` does, the equivalent bare
`cylc` commands, and how to drive the run afterwards.

To go back to something closer to upstream behaviour:

```bash
# extract offline from this repo's vendored submodules instead of github
bash examples/science-suites/run-suite.sh u-dt000 \
  -S USE_MIRRORS=true -S "MIRROR_LOC='$PWD/vendor/mirrors'"
# the full 100-cycle campaign
bash examples/science-suites/run-suite.sh u-dt000 -S "EXPT_RUNLEN='P10000D'"
# Neptune instead of Uranus
bash examples/science-suites/run-suite.sh u-dt000 -S "CASE_SETUP='neptune'"
```

### Regenerating the site patch

When the pinned revision moves, or the environment's LFRic version changes. The patch is
diffed against the **upgraded** tree, so the upgrade must be re-run first and snapshotted:

```bash
. examples/science-suites/site/activate-env.sh
# ABSOLUTE paths: rose runs from inside the app dir, and a relative entry fails with
# "[FAIL] Error: could not find meta flag".
export ROSE_META_PATH=$(find $PWD/vendor/lfric_{apps,core} $PWD/vendor/physics \
                          -type d -name rose-meta | tr '\n' ':')
W=~/roses/u-dt000; T=$(mktemp -d)

# 1. upstream at the pinned revision, upgraded -- the BASE the patch is diffed against
svn revert -R $W && svn update -r <the revision> $W
(cd $W/app && rose app-upgrade -y -C lfric_atm vn3.2 && rose app-upgrade -y -C mesh vn3.2)
mkdir -p $T/a $T/b && tar -C $W --exclude=.svn -cf - . | tar -C $T/a -xf -

# 2. re-apply the site edits on top of that, then diff a/ against b/
git apply -p1 --directory=. -C $W patches/suites/41-roses-u-u-dt000-isambard3.patch
#   ... adjust ...
tar -C $W --exclude=.svn -cf - . | tar -C $T/b -xf -
(cd $T && diff -ruN a b) > patches/suites/41-roses-u-u-dt000-isambard3.patch

# 3. back to a clean checkout at the pin
svn revert -R $W
```

Note the asymmetry with [u-dn704](../u-dn704/README.md), which has no upgrade step and so
can use `svn diff` directly (and applies with `-p0`, not `-p1`). Each stager encapsulates
its own convention.

Keep the patch to those five files: anything mechanical belongs in the upgrade step, not
here, and anything to do with the ice-giant forcing belongs in `patches/optional/32-*`.
`patches/optional/32-*`, not here.
