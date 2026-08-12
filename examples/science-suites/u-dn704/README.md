# u-dn704 — LFRic Atm NWP GAL9 at C12, on Isambard 3

This is the **Met Office EX example workflow**, run against this repo's environment.
It is the **multi-node** one of the three science-suite examples: 24 model ranks split
across two Grace nodes over Slingshot, plus a dedicated XIOS server.

It is **not a copy in this repo**, and not a vendored one either. It is the Met Office's
suite, checked out from where it actually lives, plus a patch — the same treatment
[`u-dr932`](../u-dr932/README.md) and [`u-dt000`](../u-dt000/README.md) get, and the same
treatment Stage 1 gives its LFRic sources.

```
~/roses/u-dn704                                     the suite (rosie checkout, pinned by revision)
patches/suites/42-roses-u-u-dn704-patch.sh          stages it: the site patch, and nothing else
patches/suites/42-roses-u-u-dn704-isambard3.patch   ...that — the site diff, 455 lines
examples/science-suites/u-dn704/                    only what this repo owns: this file
```

`svn revert -R ~/roses/u-dn704` gives the upstream suite back; `svn diff` in the checkout
shows exactly what we changed — the patch file *is* that `svn diff`. Every hunk carries
an `[isambard3]` comment saying what it replaced and why; this file is the index of
them.

## Where upstream is

Worth writing down, because it took some finding — and because the first answer was
wrong.

u-dn704 is a **Met Office rose suite**, and its home is MOSRS **subversion**:

```
https://code.metoffice.gov.uk/svn/roses-u/d/n/7/0/4/trunk   @ r361458
browse: https://code.metoffice.gov.uk/trac/roses-u/browser/d/n/7/0/4/trunk
```

`vendor/lfric_apps/README.md` links it as the "MetOffice EX HPC" example suite (its
sibling `u-dn674` is the Azure SPICE one), and `MetOffice/simulation-systems`'
`standard_suites.rst` tells reviewers to `rosie co u-dn704`. `rose-suite.info` —
`owner=jamesbruten`, an access list of Met Office names — confirms whose it is.

**There is no git upstream, and there will not be one soon.**
[simulation-systems#566](https://github.com/MetOffice/simulation-systems/discussions/566)
moved the *source* extraction to git and says so explicitly: *"This changes where the
Source code for the models is extracted from, **not** where the workflows themselves
reside … we recommend keeping them in the roses repository for the time being."*
`MetOffice/roses` and `roses-u` are 404, and a GitHub code search finds `u-dn704` only
as a trac link. So the suite is **checked out**, not vendored — see
[`../README.md`](../README.md), "Getting a suite from MOSRS".

### The wrong answer, and how it was caught

An earlier version of this branch pinned
[`UniExeterRSE/Isambard3-LFRic-Env-Science-Suites`](https://github.com/UniExeterRSE/Isambard3-LFRic-Env-Science-Suites)
as the upstream, because that (now archived) repository contains the suite — as a
committed `svn checkout`, `.svn` metadata and all, which is how the MOSRS URL and
revision were found in the first place:

```console
$ python3 -c "import sqlite3;d=sqlite3.connect('suites/u-dn704/.svn/wc.db');\
print(list(d.execute('select root from repository')));\
print(list(d.execute(\"select repos_path,revision,changed_revision from nodes where local_relpath=''\")))"
[('https://code.metoffice.gov.uk/svn/roses-u',)]
[('d/n/7/0/4/trunk', 345586, 345479)]
```

That was a useful clue and a bad baseline. Diffing that tree against MOSRS r345586
shows it is upstream **plus UniExeterRSE's own Isambard 3 port** — +161/−27 lines over
7 files (the `ISAMBARD3` family, the `EX_HOST` switch, `ISAMBARD3_*` variables and
their metadata, `ACTIVATE_ENV`, a spack-activate branch, github URLs replacing
`localmirrors:`, the suite title). Pinning it meant carrying a third party's porting
decisions as if they were the Met Office's — and it meant two of our own `[isambard3]`
hunks were quietly *reverting* them: MOSRS already reads `[file:lut]` and
`[file:precalc]` from `$BIG_DATA_DIR/um_aux`, and UniExeter was the one who pointed
them at the private `um_aux` git repo.

This repo supersedes that one. It should not have been pinning it as an upstream.

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

### Version — nothing to do

**This suite needs no version alignment at all**, and that is the clearest dividend of
basing on the real upstream. On 2026-07-17 (r361457–r361458) the Met Office took
u-dn704 to `meta=lfric-lfric_atm/vn3.2`, `meta=lfric-mesh_tools/vn3.2` and
`dependencies.yaml ref: 2026.07.1` — **the same release this environment builds** — and
even bumped its EX1A module loads to `2026.7.1/ngms` + `lfric-gnu/12.2.0/3.2`.

So unlike [u-dr932](../u-dr932/README.md) (vn3.1) and [u-dt000](../u-dt000/README.md)
(vn3.0), this suite's stager has **no `rose app-upgrade` step**, and the patch carries no
`dependencies.yaml` hunk. Their `app/mesh` diff is byte-for-byte what our upgrade macro
used to produce (`apply_stretch_transform` → `stretch_function='uniform'`, three
`stretch_transform` members trigger-ignored) — the same tool, run by the owners.

The stager asserts `meta=…/vn3.2` anyway. If a future revision moves off it, that
assertion fails loudly rather than letting the suite build namelists the model rejects,
and the upgrade step comes back.

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

### Data — `BIG_DATA_DIR`

Upstream already reads the ga7_1 lookup tables and spectral files from
`$BIG_DATA_DIR/um_aux/...`, so there is **nothing to change** there. (The UniExeter copy
had pointed them at `git@github.com:MetOffice/um_aux.git`, which is private — 404
anonymously — so our patch used to carry a hunk undoing that. Basing on real upstream
deleted it.)

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

Ran end-to-end on the **cray** environment (`lfric-env/v2026.07.21/cray`), `run5`,
from the MOSRS checkout at r361458:

| step | |
|---|---|
| `extract` | 33 s — six repos cloned from github over https by `merge_sources.py`, then this repo's patch stack (`PATCH_SOURCES_OK`) |
| `build_mesh` / `build_lfric_atm` | 1 m 52 s / 10 m 18 s (both from the same `extract`) |
| `generate_mesh` | 2 s |
| `lfric_atm` | **41 s**, 2 nodes, `COMPLETED` |

The multi-node arrangement is in the job's own output, not inferred:

```
launch-exe: srun --ntasks=25 --multi-prog .../lfric_xios_mpmd.conf  (model=24 xios_server=1)
0-23  .../bin/lfric_atm/lfric_atm configuration.nml
24-24 .../view/bin/xios_server.exe
-> info : intercommCreate::server (classical mode) 24 intraCommSize : 1 ... clientLeader 0
-> info : intercommCreate::client 15 intraCommSize : 24 intraCommRank :15 ... clientLeader 24
MPICH Slingshot Network Summary: 0 network timeouts
```

— one XIOS server rank with 24 clients in a single `MPI_COMM_WORLD`, a client on node 2
joining the same communicator as rank 0 on node 1, and cray-mpich reporting a clean
Slingshot run. 29 NetCDF files, 197.3 MB, including `lfric_gal_diagnostics.nc` — the
native-UGRID parallel-HDF5 write the dedicated server exists to do.

**The number that matters for this refactor is that file's size: 62 473 341 bytes.** The
same run against the previous baseline — UniExeterRSE's tree with our own
`rose app-upgrade` applied — produced a file of exactly that size, as did the original
hand-ported copy before either. Three different routes to the suite configuration, one
result. What changed is where the suite comes from and how much of the adaptation is
ours; not what it computes.

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

When the pinned revision moves, or the environment's LFRic version changes. There is no
upgrade step to work around here, so the checkout's own `svn diff` **is** the patch:

```bash
W=~/roses/u-dn704

# 1. clean checkout at the revision you want to base on
svn revert -R $W && svn update -r <the revision> $W

# 2. re-apply the site edits, adjust, and dump the diff
git apply -p0 -C $W patches/suites/42-roses-u-u-dn704-isambard3.patch
#   ... adjust ...
(cd $W && svn diff .) > patches/suites/42-roses-u-u-dn704-isambard3.patch

# 3. update SUITE_REV in patches/suites/42-roses-u-u-dn704-patch.sh to match
```

`svn diff` needs no credentials — it compares against the pristine copies in `.svn`. Do
check what upstream changed between revisions first (`svn diff -r A:B <url>`, which does
need them): if a revision moves the app configs off vn3.2, the stager's assertion fires
and a `rose app-upgrade` step has to come back, as
[u-dt000](../u-dt000/README.md)'s stager still has.

Note the asymmetry with the other two suites, whose patches are diffed against an
*upgraded* tree and so apply with `-p1`. Each stager encapsulates its own convention.

Keep the patch to those seven files: anything mechanical belongs upstream or in an
upgrade step, not here.
