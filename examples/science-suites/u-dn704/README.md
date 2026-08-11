# u-dn704 — LFRic Atm NWP GAL9 at C12, on Isambard 3

This is the **Met Office EX example workflow**, run against this repo's environment.
It is the **multi-node** one of the three science-suite examples: 24 model ranks split
across two Grace nodes over Slingshot, plus a dedicated XIOS server.

It is **not a copy in this repo** — it is a pinned submodule plus a patch, the same
treatment [`u-dr932`](../u-dr932/README.md) and [`u-dt000`](../u-dt000/README.md) get,
and the same treatment Stage 1 gives its LFRic sources.

```
vendor/uoe_science_suites/suites/u-dn704              the suite (submodule, pinned)
patches/42-uoe_science_suites-u-dn704-patch.sh        stages it: rose app-upgrade, then...
patches/42-uoe_science_suites-u-dn704-isambard3.patch ...this — the site diff, 389 lines
examples/science-suites/u-dn704/                      only what this repo owns: this file
```

`git apply -R` (or `pixi run unpatch`) gives the upstream suite back; `git diff` in the
submodule shows exactly what we changed. Every hunk carries an `[isambard3]` comment
saying what it replaced and why; this file is the index of them.

## Where upstream is

Worth writing down, because it took some finding.

u-dn704 is a **Met Office rose suite**, and its home is MOSRS **subversion**:

```
https://code.metoffice.gov.uk/svn/roses-u/d/n/7/0/4/trunk
browse: https://code.metoffice.gov.uk/trac/roses-u/browser/d/n/7/0/4/trunk
```

`vendor/lfric_apps/README.md` links it as the "MetOffice EX HPC" example suite (its
sibling `u-dn674` is the Azure SPICE one). That repository is SSO-gated and is not git,
so it cannot be a submodule, and `rose-suite.info` — `owner=jamesbruten`, an access
list of Met Office names — confirms whose it is.

What *can* be pinned is the **UniExeterRSE port** this repo already carries for
u-dt000. That repository holds an `svn checkout` of the suite, `.svn` metadata and all,
committed alongside it — which records exactly what it was taken from:

```console
$ python3 -c "import sqlite3;d=sqlite3.connect('vendor/uoe_science_suites/suites/u-dn704/.svn/wc.db');\
print(list(d.execute('select root from repository')));\
print(list(d.execute(\"select repos_path,revision,changed_revision from nodes where local_relpath=''\")))"
[('https://code.metoffice.gov.uk/svn/roses-u',)]
[('d/n/7/0/4/trunk', 345586, 345479)]
```

So: **git upstream = `vendor/uoe_science_suites` (pinned at `8fc5bc8`); provenance =
roses-u `d/n/7/0/4/trunk` @ r345586**, last changed at r345479. u-dt000 sits in the
same repository and carries the same evidence (`d/t/0/0/0/trunk` @ r344841).

> **That upstream is archived.** The UniExeter repository has been superseded by
> `MetOffice/mo-spack-packages` + `MetOffice/csc-environments`, so there is no live
> repository for this site diff to be sent back to as a pull request. It is still
> carried as a patch rather than a copy, because that is what keeps the delta
> reviewable — and because the patch is still the right artefact to hand to whoever
> owns `d/n/7/0/4/trunk` if the platform is ever added there.

## What was NOT changed

Worth stating first, because it is most of the suite:

- **The science.** NWP GAL9 NoMG at C12, the N320L70 start dump, the GAL ancillaries,
  the timestep, the diagnostic set and its XIOS file definitions — the Met Office
  suite's, unedited.
- **The task graph.** `extract → build_{mesh,lfric_atm} → generate_mesh → lfric_atm`.
- **The extract mechanism.** Still `merge_sources.py` reading `dependencies.yaml`, with
  upstream's three command keys and its `USE_MIRRORS`/`USE_TOKENS`/`MIRROR_LOC`
  controls. Changing what gets built is the same edit you would make at the Met Office.
  (This suite used to be the one exception in this repo — it ran a bespoke offline
  extract, `site/extract-sources.sh`. That is retired with this move.)
- **The EX1A branches.** Every `{% if EX_HOST == 'isambard3' %}` guard is honoured, so
  the file still renders as upstream on the Met Office EX.
- **The build precisions**, `PSYCLONE_TRANSFORMATION`, `LFRIC_TARGET_PLATFORM`,
  `MAKE_THREADS`, the `[[BUILD]]` directives, `execution time limit`s.

## The changes

### Version — vn3.0 → vn3.2

This repo's environment is built against LFRic `2026.07.1` (apps vn3.2); the suite is
written for vn3.0. **This is not in the patch file** — the staging script *runs* the
native tool, `rose app-upgrade -y -C <app> vn3.2`, over the submodule's app configs.
The vn3.0 → vn3.1 → vn3.2 macro chain applies cleanly: ~700 lines of namelist churn for
`lfric_atm` (renames such as `pc2ini`→`pc2_init_method` and `i_bm_ez_opt`→`bm_ez_opt`,
`jules_pftparm` into its indexed per-PFT form, new vn3.2 members at their macro
defaults) and three settings for `mesh` (`apply_stretch_transform`→`stretch_function`).

That churn used to be carried as a **hand port** in this repo's copy of the suite, item
by item, each with a comment explaining which LFRic check it satisfied. Every one of
those is now the macro's output instead. Bump `SUITE_META_VN` in the patch script when
the `vendor/lfric_apps` pin moves.

`dependencies.yaml` moves from `2025.12.1` to `2026.07.1` to match.

### Placement — the multi-node case

| where | change |
|---|---|
| `lfric_atm [[[directives]]]` | `--nodes=1 --ntasks=6` → `--nodes=2 --ntasks=25 --ntasks-per-node=13`. 24 model ranks + 1 XIOS server. `--ntasks-per-node=13` is what **splits the model across both nodes** (ranks 0–12 / 13–23) instead of letting the block layout pack all 24 onto node 1 with only the server on node 2 — which would make this a single-node run wearing a two-node hat. |
| same | **added** `--exclusive` and `--mem=64G`. SelectType here is `select/cons_tres`, so without `--exclusive` the job lands on partially-occupied nodes and competes for memory bandwidth — see [`staging/dr932-mpi-scaling/`](../../../staging/dr932-mpi-scaling/). |
| `[[ISAMBARD3]]` | `CORES_PER_NODE` 128 → 144. A Grace node is 2 × 72 cores; 128 is the Met Office EX1A number. |
| `lfric_atm [[[environment]]]` | **added** `MPICH_ENV_DISPLAY` / `MPICH_OFI_NIC_VERBOSE`, so `job.out` records the OFI provider — `provider: cxi` is the one-line proof the run is on Slingshot rather than falling back to TCP. |

### The launcher — the one component this repo substitutes

`LAUNCH_SCRIPT` moves off the Met Office `rose-stem/site/meto/common/bin` launcher onto
[`site/bin/launch-exe`](../site/bin/launch-exe). This is the only place in the three
suites where an upstream *component* is replaced rather than configured, and it is
forced: the MO launcher wires the dedicated-XIOS-server MPMD up only under
`RUN_METHOD=mpiexec` (Hydra colon syntax); its `srun` path emits a bare `srun <exe>`
with no server at all. This case needs both — srun (for cray-mpich over Slingshot) and
a dedicated server. `site/bin/launch-exe` does it with `srun --multi-prog`, which is
what puts client and server in a single `MPI_COMM_WORLD`, and it honours the same
environment contract (`BIN_DIR`, `EXEC_NAME`, `TOTAL_RANKS`, `XIOS_SERVER_*`) so it
stays a drop-in.

u-dr932 and u-dt000 do **not** use it: single-node with XIOS attached, where upstream's
`srun` path is exactly right.

### XIOS

| where | change |
|---|---|
| `app/lfric_atm` `[env]` | `TOTAL_RANKS` 1 → 24, `XIOS_SERVER_MODE` False → True. |
| `app/lfric_atm/file/iodef_gal_nwp.xml` | `using_server2` true → false (and `ratio_server2` / `number_pools_server2` dropped with it). The 2-level server crashes here: with one server rank there are no secondary servers to make 4 pools from, and that path then trips an MPICH yaksa assertion (`memcpy ranges overlap`). One primary server writing the `one_file` UGRID output is plenty at C12. |
| `app/lfric_atm` `[env]` | **added** `HDF5_USE_FILE_LOCKING=FALSE`. `cylc-run` is on Lustre, which rejects the `flock()` HDF5 1.10+ takes on files it creates; XIOS's `nc_create()` otherwise aborts with "Permission denied" after leaving a 0-byte file. |

### Environment — the Stage-1 contract

| where | change |
|---|---|
| `[[root]] init-script` | **added.** Cylc runs each job under `bash -l`, which resets Lmod and purges the module the scheduler had loaded — the job then dies with `rose: command not found` before any family `pre-script` runs. `init-script` is the only hook early enough, and it is also before the task `[[[environment]]]` block, so the module selection is exported there. |
| `[[BUILD]]` | `FC`/`LDMPI` = `mpif90`, `FPP` = `"cpp -traditional-cpp"` → `$FC`/`$LDMPI`/`$FPP`. Inherit the toolchain from the loaded module instead of naming a compiler, so `LFRIC_STACK=cray\|spack` needs no edit here. This is the Stage-1 contract. |
| `rose-suite.conf` | `ISAMBARD3_SPACK_SETUP` and `ACTIVATE_ENV` emptied — they pointed at the UniExeter port's own in-tree spack. `run-suite.sh` injects `ACTIVATE_ENV` via `cylc vip -S`, and emptying `SPACK_SETUP` is what makes the `ISAMBARD3` pre-script take that branch instead of `spack env activate`. |

### Data — `um_aux` is private

`[file:lut]` and `[file:precalc]` fetched the ga7_1 lookup tables and spectral files
from `git@github.com:MetOffice/um_aux.git`. **That repository is private** (404
anonymously) — unlike `lfric_apps`, `lfric_core`, `casim`, `jules`, `socrates` and
`ukca`, which the extract clones over https with no credentials. So both read from the
copies staged on the project filesystem instead, under the same `BIG_DATA_DIR` as the
ancillaries and the start dump.

`BIG_DATA_DIR` itself moves from `$CYLC_WORKFLOW_SHARE_DIR/data` (which nothing
populates) to `/projects/u35v/sw/lfricdata`, a Jinja default you can override with
`-S BIG_DATA_DIR=...`. Staged there:

```
ancils/basic-gal/yak/C12                              GAL ancillaries
start_dumps/nwp-gal9/apps1.1/nwp-gal9_N320L70_C12L70.nc
um_aux/spectral/ga7_1  um_aux/UKCA/radaer/ga7_1       the two private-repo installs
```

A user with access to `um_aux` can put the two upstream lines back.

### Small things

| where | change |
|---|---|
| `app/mesh/rose-app.conf` | `mpiexec -n 1` → `srun --ntasks=1`. Same one rank; the cray environment is cray-mpich and ships no `mpiexec`. |
| `rose-suite.conf` `[file:bin/*]` | the two SimSys_Scripts sources ssh → https. Public repository; the ssh form needs a key registered with the Met Office org. The `tweak_iodef` line above them already used https upstream. |
| `rose-suite.conf` `USE_TOKENS` | `false` → `true`, i.e. https clones rather than ssh. `USE_MIRRORS` stays `false` — there is no Met Office mirror host here. |
| `app/extract/rose-app.conf` | `site/patch-sources.sh` appended to each of the three command keys, with `&&` not `;` so a failed clone fails the task. The keys themselves are upstream's. |

### The one thing this repo adds to the extract

`site/patch-sources.sh` applies this repo's LFRic-source patch stack
(`patches/*-lfric_{core,apps}-*`) to the freshly cloned tree — the same patches the
environment build and the minimal-compile example use. The one that matters most here
is `30-lfric_apps-local-sources`, which stops the apps build from re-cloning its own
science sources mid-compile and undoing the pin `dependencies.yaml` just declared.

## What was observed on this environment

Ran end-to-end on the **cray** environment (`lfric-env/v2026.07.21/cray`):

<!-- RUN4-RESULTS -->

## Running it

From the repo root, on a **login node** — the Cylc scheduler lives there and submits
each task to Slurm itself:

```bash
bash examples/science-suites/run-suite.sh u-dn704
cylc tui u-dn704            # watch
```

See [`../README.md`](../README.md) for what `run-suite.sh` does, the equivalent bare
`cylc` commands, and how to drive the run afterwards.

To go back to something closer to upstream behaviour:

```bash
# extract offline from this repo's vendored submodules instead of github
bash examples/science-suites/run-suite.sh u-dn704 \
  -S USE_MIRRORS=true -S "MIRROR_LOC='$PWD/vendor/mirrors'"
# put the data somewhere else
bash examples/science-suites/run-suite.sh u-dn704 -S "BIG_DATA_DIR='/path/to/data'"
```

### Regenerating the site patch

When the submodule pin moves, or the environment's LFRic version changes:

```bash
. examples/science-suites/site/activate-env.sh
# ABSOLUTE paths: rose runs from inside the app dir, and a relative entry here fails
# with the unhelpful "[FAIL] Error: could not find meta flag".
export ROSE_META_PATH=$(find $PWD/vendor/lfric_{apps,core} $PWD/vendor/physics \
                          -type d -name rose-meta | tr '\n' ':')
S=vendor/uoe_science_suites

# 1. upstream at the pin, upgraded — this is the BASE the patch is diffed against
git -C $S checkout -B tmp-upgraded <the pin>
(cd $S/suites/u-dn704/app && rose app-upgrade -y -C lfric_atm vn3.2 \
                          && rose app-upgrade -y -C mesh vn3.2)
git -C $S commit -am 'rose app-upgrade u-dn704 vn3.0 -> vn3.2'

# 2. re-apply the site edits, then diff. --no-ext-diff is not optional: the redirect
#    truncates the patch BEFORE git runs, so a configured external differ (difft
#    aborts on aarch64 here) leaves you with a zero-byte patch and nothing to reapply.
git -C $S apply patches/42-uoe_science_suites-u-dn704-isambard3.patch
#   ... adjust ...
git -C $S diff --no-ext-diff > patches/42-uoe_science_suites-u-dn704-isambard3.patch

# 3. back to the pin
git -C $S checkout --detach <the pin> && git -C $S reset --hard <the pin>
git -C $S clean -fd && git -C $S branch -D tmp-upgraded
```

Keep the patch to those seven files: anything mechanical belongs in the upgrade step,
not here.
