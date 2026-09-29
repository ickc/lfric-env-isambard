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
included, and `git apply -R` takes it out again. It applies to 2026.07.1 and to
`main` as of 2026-09-28.

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

## Validated

`group=scripts` on 2026-09-28, lfric_apps `main` @ `801edbfa`, env v2026.09.28/cray.
The group is the Met Office's own `scripts` list minus `local_build_test`, which
needs the Met Office Intel build family. The model groups are copied from `uoe`
and have not been run here.

## Upstream

Both changes are meant for MetOffice/lfric_apps. Once they land, delete this
directory and the `[rose-stem]` section of `stage1/site/rose.conf` stays.
