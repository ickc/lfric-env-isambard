# `patches/rose-stem/` — run lfric_apps rose-stem on Isambard 3

A patch to **your own `lfric_apps` clone** (not to anything in this repo), so that
the standard developer command works here:

```bash
module use /projects/u35v/khcheung.u35v/opt/Linux-aarch64/modulefiles
module load lfric-env/v2026.09.28/cray          # cylc 8.6, stylist, fortitude, pytest

cd <your lfric_apps clone>
git apply <lfric-env-isambard>/patches/rose-stem/lfric_apps-isambard3-site.patch
cylc vip -z group=scripts -n myfeature.scripts ./rose-stem
```

`SITE=isambard3` comes from the module's Rose site config
(`rose config rose-stem automatic-options`), so no `-S SITE=...` is needed. Leave
the patch uncommitted: rose-stem copies your working tree, uncommitted changes
included, and `git apply -R` takes it out again.

**It is for `main`, not 2026.07.1.** rose-stem is the developer tool, run on a branch
of `main`, and the site follows `main`'s rose-stem templates. After 2026.07.1 those
changed `set_task_resources` to take a family name, inherit list and wallclock. On a
2026.07.1 checkout the patch applies, but validation fails with `parameter 'wallclock'
was not provided`. Validated against `main` @ `801edbfa` (2026-09-28).

## What it changes, and why

1. **`rose-stem/site/isambard3/`, a new site** (#19). Built from `site/uoe`, with
   one platform, `isambard3`. Every job loads the environment the workflow was
   launched with, using `LFRIC_ENV_MODULEPATH`/`LFRIC_ENV_MODULE` from the module;
   launching without the module loaded fails at validation and says so. The
   script checks run on the login node, alongside the scheduler. Build, mesh and
   model jobs go to Slurm (`--partition=grace`), and `launch-exe` is the srun
   launcher from `examples/science-suites/site/bin/`.
2. **`rose-stem/lib/python/read_sources.py`, read the source by path when it is
   visible** (#20). rose-stem names your clone `ROSE_ORIG_HOST:<path>` and fetches
   it with `scp`, and the export step rsyncs it with `ssh`. Isambard 3 login nodes
   refuse SSH, even to themselves (`authorized_keys` is not honoured). When
   `<path>` exists on this filesystem, which it always does here, the patch uses
   the plain path, so neither step needs SSH. On a site where the path is not
   local, nothing changes.

3. **`mpiexec` for the things that call it directly** (`site/isambard3/common/bin/
   mpiexec`, on every job's PATH). The mesh apps run `mpiexec -n 1 <generator>`, and
   lfric_core's test framework launches its MPI tests as `mpiexec -n 6`. The cray
   environment has no `mpiexec`: cray-mpich's launcher is `srun`. The shim turns
   `mpiexec -n N cmd` into `srun --ntasks=N cmd` inside the job's allocation.
   `tech-tests_cpus` is 6 for the same reason.
4. **`applications/*/optimisation/isambard3-isambard3` → `meto-ex1a`**, 13 symlinks.
   A rose-stem build uses the PSyclone transformation directory `<SITE>-<platform>`,
   and every application needs one. This follows `uoe-epic`, which links to
   `meto-ex1a` in the same way: the Met Office's Cray EX set, which the science suites
   here already build with.
5. **`USE_TOKENS`** (#40). rose-stem's `export-source` clones the `dependencies.yaml`
   sources, which are `git@github.com:` URLs, and rewrites them to https only when the
   site sets `USE_TOKENS`. A trainee has no GitHub SSH key here, and every repository
   is public, so the site sets it.
6. **No KGO checks.** There are no Isambard 3 known-good answers yet
   (`site/isambard3/kgos/`). A first validated run's checksums can seed them.

## Validated

On lfric_apps `main` @ `801edbfa`, env v2026.09.28/cray, 2026-09-29:

| Group | Result |
|---|---|
| `scripts` (Practical 3) | all 11 tasks pass. The Met Office's own list minus `local_build_test`, which needs the Met Office Intel build family. |
| `gungho_isambard3_unitandintegration_tests` | the gungho build and **integration tests pass**. The **unit tests are left out**: they need pFUnit, which the environment does not ship yet (#37). |
| `lfric_atm_isambard3_exoplanets`, `gungho_model_isambard3_exoplanet` | the `lfric_atm`, `gungho_model` and mesh builds pass, all four meshes generate, and the single-column `scm_hd209458b` model runs. **The four 3D model runs crash in XIOS** during the UGRID header write (#38). |

So Practical 3's `scripts` group works. The Met Office `developer` group is not defined
for this site, because it would inherit both gaps above.

## Upstream

Both changes are meant for MetOffice/lfric_apps. Once they land, delete this
directory and the `[rose-stem]` section of `stage1/site/rose.conf` stays.
