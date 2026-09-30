# u-dz791 — LFRic idealised CRM, hydrogen atmosphere, on Isambard 3

The suite the **LFRic Atmosphere training course** uses for its idealised practicals
(`source/modelling/idealised_practical_exercises/`): a dynamics-only cloud-resolving
model of a hydrogen-dominated atmosphere on a bi-periodic Cartesian domain. With no
rotation, the gas constants set to H₂ (`cp=14300`, `rd=4124`) and a step in water vapour
aloft, it is built to study compositional convection.

It is **not a copy in this repo**. It is Denis Sergeev's Met Office rose suite, checked
out from where it lives:

```
https://code.metoffice.gov.uk/svn/roses-u/d/z/7/9/1/trunk   @ r368986
```

plus a patch, the same treatment [`u-dt000`](../u-dt000/README.md) gets.

```
~/roses/u-dz791                                      the suite (rosie checkout, pinned by revision)
patches/suites/43-roses-u-u-dz791-patch.sh           stages it: rose app-upgrade, then...
patches/suites/43-roses-u-u-dz791-isambard3.patch    ...this — the site diff
patches/optional/33-lfric_apps-dz791-profile-init*   the science: Alex Corbett's branches, forward-ported
examples/science-suites/u-dz791/                     only what this repo owns: this file
```

`svn revert -R ~/roses/u-dz791` gives the upstream suite back. Every hunk carries an
`[isambard3]` comment saying what it replaced and why; this file is the index of them.

Getting it needs a MOSRS account, with the password cached on the login node you are
on:

```bash
module load lfric-env/<version>/cray
mosrs-cache-password
rosie checkout u-dz791 && svn update -r 368986 ~/roses/u-dz791
```

## The science lives in two branches — and why they are a patch here

Upstream's `dependencies.yaml` merges two `lfric_apps` branches onto 2026.03.1, from
`/home/users/alexander.corbett.ext/local_lfric/lfric_apps`: a clone on a Met Office
machine that nobody else can read. They are the suite's science, and the practicals rely
on them ("Initial temperature profile: isothermal (uses a branch for a corrected
procedure - see `dependencies.yaml`)"):

- **`t_and_rh_init_clean`** adds `profile_variable` to `namelist:initial_temperature`
  (`'potential'`|`'absolute'`) and `namelist:initial_vapour` (`'mr'`|`'rh'`), plus a
  new `vert_balance_kernel` that builds a hydrostatically balanced theta, mixing ratio
  and exner from an absolute temperature or relative-humidity profile. u-dz791 sets
  `profile_variable='absolute'`.
- **`qsaturation-use-epsilon`** makes `physics_common_mod`'s saturation function use
  ε = Rd/Rv, not the Earth-air value, which matters for an H₂ atmosphere.

Both are public in Alex Corbett's fork, `corbopy/lfric_apps`, the first published as
`vn3.1-feat/t-and-rh-init-clean`. Declaring those two public branches in place of the
private path was the first attempt, and it **does not work on this environment**:

1. **The environment's toolchain cannot build 2026.03.1.** Its PSyclone 3.3 no longer
   has the `Dynamo0p3*` transformations that 2026.03.1's optimisation scripts import:
   `ImportError: cannot import name 'Dynamo0p3RedundantComputationTrans'`, at the very
   first PSyclone step of `build_lfric_atm`. The environment supplies a toolchain, but
   that toolchain is tied to the LFRic release it was built for. An older release does
   **not** build on it unchanged.
2. **The branches do not merge onto 2026.07.1.** `t-and-rh-init-clean` conflicts in 22
   files, and `merge_sources.py` resolves conflicts only under `rose-stem/`.

So the suite moves to 2026.07.1 like the others. The two branches are forward-ported
once and carried as
[`patches/optional/33-lfric_apps-dz791-profile-init-patch.sh`](../../../patches/optional/33-lfric_apps-dz791-profile-init-patch.sh),
which the staged extract task applies. That script's header records exactly how each
conflict was resolved, and how to regenerate it. All of the conflicts were API drift
between 2026.03.1 and 2026.07.1, not science. 2026.07.1 passes `config` and a `mesh`
pointer where the branch had `mesh_id`; the branch adds `exner`, W3 heights and the
`profile_variable` imports. The resolution is the union of the two. The branches'
unit-test, rose-stem and KGO changes are not carried, since a suite build reads none of
them.

When Alex's branches are rebased onto a current LFRic, `dependencies.yaml` goes back to
declaring them and patch 33 is deleted.

## What was NOT changed

The science configuration: every namelist value, the resolution
(`BiP128x128-2000x2000_MG`, 128 × 128 columns at 2 km), the levels
(`uniform_l200_900km`), `PHYSICS_CONF='gungho'`, `EXPT_DT=10`, and the run length and
resubmission (`PT1H` in two `PT30M` cycles, restarting between them). The task graph,
the launcher (Met Office `launch-exe`, whose `RUN_METHOD=srun` path is right for this
single-node, XIOS-attached run), and the `ex` / ex1a branches of `flow.cylc`, which still
render as upstream when `EX_HOST` is not `isambard3`.

## The changes

### Version — vn3.1 → vn3.2

The stager runs `rose app-upgrade -C lfric_atm vn3.2` and `-C mesh vn3.2` before the site
patch, against the vendored LFRic rose-meta. The patch is diffed against that upgraded
tree. The upgrade also rewrites each opt config as a minimal diff against the upgraded
main config, and normalises trigger states: for example, `namelist:blayer` becomes
trigger-ignored where `boundary_layer='none'`. Checked by loading every opt config, and
the default combination, with Rose's own `load_with_opts` before and after. The only
differences are that trigger normalisation, line wrapping and `n*value` repeat notation,
and the main config's own `jules_pftparm` migration. `VN` in `rose-suite.conf` follows
(`'3.1'` → `'3.2'`); nothing reads it.

### Source — upstream's own extract, extended

- `dependencies.yaml`: every ref 2026.03.1 → 2026.07.1, and `lfric_apps` is mainline
  2026.07.1 instead of the two private-path branches (see above).
- `app/extract`: upstream's `merge_sources.py`, with two steps appended by `&&`: this
  repo's LFRic-source patch stack (`site/patch-sources.sh`), then patch 33.
- `rose-suite.conf`: the three `git:localmirrors:` file sources go to public HTTPS, and
  `USE_MIRRORS` becomes `false`, so the extract uses `--tokens`: anonymous HTTPS clones
  from GitHub.

### Environment — the Stage-1 contract

`EX_HOST='isambard3'` selects an `ISAMBARD3` family in `flow.cylc`, in place of
`EX1A`'s Monsoon and ex1a module loads:
- the root `init-script` sources `ACTIVATE_ENV`, i.e. `module load`s the environment;
- `[[BUILD]]` takes `FC`/`LDMPI`/`FPP` from it;
- `COMPILER` goes from `'cce'` to `'gnu'`, since the environment is GCC 14.3.

The extract runs on the scheduler host (`platform = localhost`), because it is a git
clone and needs no compute node.

### Output — four initial diagnostics dropped (XIOS)

`file_def_initial_diags.xml` loses `init_u_in_w2h`, `init_v_in_w2h`,
`init_height_w2h` and `init_height_w0`. Writing any **edge-located (W2H) or node-located
(W0)** field to a UGRID file segfaults XIOS r2701 in this environment, in
`CMesh::createMeshEpsilon` during the file header write. It does so on 1 rank as on 128,
so the model died at its initial output. Bisecting that file found it: dropping the W2H
fields alone, or the W0 field alone, still crashes; dropping both runs. Cell-located fields write normally,
and the science file, `lfric_crm_diag`, has none of the four (its winds are
`u_in_w3`/`v_in_w3`). Tracked in
[#38](https://github.com/ickc/lfric-env-isambard/issues/38). Restore the four fields
once it is fixed.

### Small things

- `BUILD_ROOT` is the task's work directory, not `${TMPDIR}`. On a Grace node `TMPDIR`
  is `/local/user/<uid>`, which outlives the job. A later run on the same node found an
  earlier run's build tree, and the dependency analyser aborted on a module that the
  old source had at another path (`UNIQUE constraint failed:
  fortran_program_unit.unit`).
- `[file:spec]` reads the GA9 spectra from `$SOURCE_ROOT/socrates`, not through the
  `fcm:socrates.xm_tr` keyword into MOSRS, as upstream u-dn704 already does. Rose
  installs every `[file:]` entry, so this is needed even with radiation off.

### Placement

`LPPN` is 144, a Grace node, not the Met Office EX's 128. `lfric_atm` gets
`--nodes`/`--ntasks`/`--ntasks-per-node` from `TOTAL_RANKS_REQ=128` (one node),
`--exclusive` and `--mem=0`. The build and mesh jobs get Slurm directives that mirror
upstream's PBS ones. The mesh app's `mpiexec -n 1` becomes `srun --ntasks=1`: there is
no `mpiexec` in the cray environment.

## What was observed on this environment

_Filled in from the validating run._

## Running it

From the repo root, on a login node:

```bash
bash examples/science-suites/run-suite.sh u-dz791
cylc tui u-dz791            # watch
```

The practicals change `PHYSICS_CONF`, `LFRIC_LEVS`, `LFRIC_RES` and the namelists. All of
that works as the training describes, because the configs are upstream's apart from the
upgrade. Pass template variables with `-S`, e.g.
`-S "PHYSICS_CONF='gungho_evap_cond'"`.

### Regenerating the site patch

The same recipe as [u-dt000's](../u-dt000/README.md#regenerating-the-site-patch), with
`W=~/roses/u-dz791`, the `43-*` file names, and `rose app-upgrade` of `lfric_atm` and
`mesh` to vn3.2.
