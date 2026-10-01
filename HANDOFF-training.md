# Handoff: lfric-env-isambard → the training-site agent

From the agent maintaining `lfric-env-isambard`. Last updated 2026-09-30 23:35 UTC.
Environment: **`lfric-env/v2026.09.28`**. It is not yet announced, and it is being
updated **in place**, not re-released under a new date.

```bash
module use /projects/u35v/khcheung.u35v/opt/Linux-aarch64/modulefiles
module load lfric-env/v2026.09.28/cray
```

(That path spells a personal username. Moving it is tracked in
[#46](https://github.com/ickc/lfric-env-isambard/issues/46); until then, keep using it.)

---

## Done, and safe to rely on in the training material

| What | Issue / PR | What the training can now say |
|---|---|---|
| **rose-stem site sets `USE_TOKENS`** | #40 / PR #43 | Drop the manual "append `USE_TOKENS` to `variables.cylc`" step. `git apply <repo>/patches/rose-stem/lfric_apps-isambard3-site.patch` is enough. Verified with SSH disabled for git: 11/11. |
| **Cylc site config ships in the module** | #31 / PR #44, #45 | No `~/.cylc` needed, and no `setup-cylc.sh`. The module sets `CYLC_SITE_CONF_PATH`, which gives the `isambard3` Slurm platform and run dirs at `$PROJECTDIR/$USER/cylc-run/<workflow>` (each user's own). A user's `~/.cylc/flow/global.cylc` still overrides it. Verified as a fresh user (empty `HOME`, no SSH): Practical 3 `scripts` group 12/12. Check with `cylc config -i '[platforms][isambard3]'`. |
| **u-dz791 (idealised practicals) runs** | #26 / PR #42 | See "How a trainee runs u-dz791" below. Validated end-to-end, 2 cycles with a restart, about 1 min 40 s each on one node. |
| **rose-stem model groups on Slurm** | PR #39, #47, #48 | Builds, meshes, **unit tests (265 OK)**, integration tests, the SCM run and all four **3D exoplanet runs** pass. Only the `plot_*` tasks fail (#49). |

### How a trainee runs u-dz791

Not bare `rosie copy u-dz791 && cylc vip`: upstream still points at a private Met
Office path and at LFRic 2026.03.1, which this environment cannot build. The
supported path:

```bash
mosrs-cache-password                                  # once per login node
rosie checkout u-dz791 && svn update -r 368986 ~/roses/u-dz791
cd <lfric-env-isambard clone>
bash examples/science-suites/run-suite.sh u-dz791     # stages the port, then cylc vip
```

No `git submodule update` is needed: the clone alone is enough (verified as a fresh user
on a clone with no submodules). The rose-meta the upgrade needs comes from the module.
For `rose edit` on the staged suite, `export ROSE_META_PATH=$LFRIC_ROSE_META_PATH` first.

`run-suite.sh` runs `rose app-upgrade` (vn3.1→vn3.2) and applies the site patch to
`~/roses/u-dz791`. The extract task applies the science forward-port
(`patches/optional/33-*`). Output: `lfric_crm_diag_*.nc` (UGRID), 10-minute files.
Practical edits (`PHYSICS_CONF`, levels, namelists) work as the training describes;
pass template variables with `-S`.

Known differences from upstream, all marked `[isambard3]` in the suite: LFRic is
2026.07.1, with Alex Corbett's two branches forward-ported. The output is upstream's
(the XIOS fix restored the four initial diagnostics an earlier version dropped).

### Practical 3 (rose-stem)

- The patch targets lfric_apps **`main`**. On a 2026.07.1 checkout it applies but fails
  validation (`parameter 'wallclock' was not provided`), because `main` changed the
  rose-stem template API.
- `group=scripts` works (11/11). The `developer` group is **not** defined for this site.

---

> **Second in-place rebuild done (2026-09-30, finished 21:07:50 UTC).** It added the
> release's rose-meta to the module (`LFRIC_ROSE_META_PATH`, PR #51). Only a metadata
> package and the modulefile changed; the compilers and libraries did not, so nothing
> needs re-running. `BUILD_OK` cray + spack, `LFRIC_ATM_OK` cray + spack.

> **Rebuild done (2026-09-30 19:40 UTC).** v2026.09.28 was rebuilt in place with the
> XIOS fix: `BUILD_OK` cray + spack, `LFRIC_ATM_OK` cray + spack. It is safe to run
> again. Workflows launched before 19:30 linked the old XIOS; re-run anything that
> writes W2H/W0 UGRID output.

## Recently finished

1. **pFUnit (#37): DONE, live in v2026.09.28.** The module exports `PFUNIT`, and puts
   the pFUnit/fargparse/gftl-shared flags on `FFLAGS`/`LDFLAGS`. The rose-stem site
   patch includes the gungho unit tests again: **265 unit tests OK**, integration tests
   pass (`gungho_isambard3_unitandintegration_tests`). Re-apply the patch from the repo
   to pick up the group change.
2. **XIOS crash (#38): FIXED, live in v2026.09.28** (rebuilt in place, 19:40 UTC).
   The cause was an XIOS r2701 bug that only aarch64 exposes: node coordinates were
   hashed through a double→`size_t` conversion that saturates negative values to 0, so
   any edge-located (W2H) or node-located (W0) field in UGRID output segfaulted.
   Verified after the rebuild:
   - rose-stem's four 3D exoplanet runs, which used to segfault, **succeed, restarts
     included**;
   - u-dz791 writes its full upstream initial diagnostics again (PR #50);
   - the build invariant is green: `BUILD_OK` and `LFRIC_ATM_OK` on cray and spack.

   Still open for a full `developer`-style group: rose-stem's **`plot_*` tasks** now run
   and fail on `import matplotlib`. They need an iris/matplotlib env, as the Met Office
   uses scitools
   ([#49](https://github.com/ickc/lfric-env-isambard/issues/49)). The training's own
   Python env for Iris is probably the answer.

## Not done / blocked

| What | Status |
|---|---|
| u-dz612 (global practicals, #24) | **Blocked on Met Office data.** It is the coupled GC6 model (UM + NEMO/SI3 + OASIS, via `fcm make`), needing Monsoon-only training data. Not a site port. For the global practicals, use **u-dn704** (GAL9 C12), which runs here. |
| u-by395 (regional practicals, #25) | **Blocked on Met Office data** (UK 1.5 km ancils, N1280 analyses from MASS). No real-data LAM runs here. |
| Upstream the rose-stem patch (#32) | Not started. It needs a PR to MetOffice/lfric_apps; the maintainer is to say go. Until then `patches/rose-stem/` tracks lfric_apps `main` and can drift. |
| Shared, non-personal release prefix (#46) | Filed. Access is fine: trainees are u35v members, who can read it. Only the path (it names a person) is the issue. |

## If something breaks

File an issue on `ickc/lfric-env-isambard` with the exact command, the environment
(`echo $LFRIC_ENV_MODULE`), and the failing job's `job.err`. Do not edit
`/projects/u35v/khcheung.u35v/opt/...` directly.
