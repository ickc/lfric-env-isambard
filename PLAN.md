# PLAN — Stage-3 follow-ups (next)

Open work after the per-suite **offline source mechanism** and the **Stage→examples
rename** landed. Branch `stage3-science-suites`, PR #8.

## Done so far (context, don't redo)

- **u-dr932** runs end-to-end on the built env (`spack`), re-verified after the shared
  `HDF5_USE_FILE_LOCKING=FALSE` change. Now also validated through the new offline-extract
  path (`run7`).
- **u-dn704** runs **end-to-end** on the built env (`spack`, `run2`): extract → build_mesh →
  generate_mesh → build_lfric_atm → lfric_atm all succeeded; 144 timesteps, "gungho
  finalised", full UGRID + NAME diagnostics written by the XIOS server (lfric_gal_diagnostics.nc
  ~62 MB). NWP `um_aux`/ancils/C12 start dump staged at default
  `BIG_DATA_DIR=/projects/u35v/sw/lfricdata`. **Runs genuinely multi-rank with a dedicated
  XIOS server** (6 model ranks + 1 server, parallel-HDF5 one_file write — the point of XIOS).
  Three fixes, all in the suite:
  1. `HDF5_USE_FILE_LOCKING=FALSE` in `app/lfric_atm/rose-app.conf [env]` — without it
     XIOS `nc_create` aborts with "Permission denied" creating the NetCDF-4 output on
     Lustre (the activate-env.sh export didn't reach the XIOS process; matches dr932).
  2. Dedicated XIOS server launch. iodef.xml declares `using_server=true`, but the suite
     launched plain `srun` with **no** server process (meto `launch-exe` only wires the
     XIOS-server MPMD under `RUN_METHOD=mpiexec`, not `srun`). Set `RUN_METHOD=mpiexec` +
     `TARGET_PLATFORM=generic` + `XIOS_SERVER_MODE=True` in app `[env]` (authoritative,
     overriding flow.cylc/family like dr932) → `launch-exe` emits Hydra MPMD
     `mpiexec -n 6 lfric_atm … : -n 1 xios_server.exe`. `--ntasks=7` (= model+server).
  3. `using_server2=false` in `iodef_gal_nwp.xml` — the 2-level server tripped an MPICH
     yaksa assertion ("memcpy ranges overlap") on its secondary rank; single-level server
     is plenty for C12.
  NB both suites were *effectively serial before* (dr932 also launches `mpiexec -n 1`); dn704
  is now the real multi-rank/parallel-HDF5 reference. Applying the same to dr932 is an open
  option (it works at -n 1; not done to avoid an unprompted regression risk).
- **u-dt000** builds + meshes + launches the model, then aborts on its missing science
  (see follow-up 1). Infra fixes in place (`env-script = eval $(rose task-env)` for
  `ROSE_DATA`; `--mem=0`).
- **Mechanism (b) — per-suite offline source** (commit `09ca75a`): each suite has a
  `dependencies.yaml`; `examples/science-suites/site/extract-sources.sh` extracts each
  declared `repo@ref` OFFLINE from the vendored local mirrors (`git archive`, no network)
  into `SOURCE_ROOT/{lfric_apps,lfric_core,physics/*}`, then applies the LFRic-source
  patch stack (`patches/{10,11,30}` honour `LFRIC_SRC_ROOT`, default `vendor/`). Strict
  offline: a ref absent from the mirror is a hard error naming what to stage.
- **Rename** (commit `bedd813`): Stage 2/3 reframed as sibling *examples* on the one
  prerequisite build (Stage 1); `examples/lfric-atm → examples/minimal-compile`.

**Run a suite (spack):** `LFRIC_STACK=spack bash examples/science-suites/run-suite.sh <id>`.
**Fast iterate:** `. scripts/common.sh; . examples/science-suites/site/activate-env.sh`
then `cylc reinstall <id>/run1 && cylc trigger <id>//<cycle>/lfric_atm` (build+mesh cached;
extract re-runs from the mirror). Logs: `~/cylc-run/<id>/run1/log/job/<cycle>/<task>/NN/`.
**Invariant (don't break):** Stage-1 build + the `cray`/`spack` concretize assertions.

---

## Follow-up 1 — Locate + stage the u-dt000 ice-giant LFRic fork (BLOCKER)

**Why:** u-dt000's science is `theta_forcing='ice_giants_obs_like'` (namelist
`external_forcing`). Verified absent from **both** the vendored vn3.1.1 **and** the
suite's own declared mainline `lfric_apps@vn2.2` (`git archive vn2.2 | grep` → empty;
`held_suarez_sigma_b` is a hardcoded `parameter` in both, not a namelist field). The
upstream suite's extract points only at MetOffice mainline, which lacks the science — so
the forcing lives in a **fork the suite never references**.

**Steps:**
1. Ask upstream (UniExeter RSE — the suites repo maintainers) **where the ice-giant
   forcing branch lives** (likely an Exeter fork of `lfric_apps`, or a MOSRS branch not
   migrated to git). Get the remote URL + ref.
2. Stage it ONCE into the local mirror (online, then offline thereafter):
   `git -C vendor/lfric_apps remote add <fork> <url> && git -C vendor/lfric_apps fetch <fork>`
   (+ any matching `lfric_core`/physics refs the fork needs — check its `dependencies.sh`).
3. Point `examples/science-suites/u-dt000/dependencies.yaml` `lfric_apps` (and deps) at
   that ref. If the fork is a *branch on top of a tag*, see follow-up 2.
4. Run u-dt000; iterate the run task on any remaining vn-schema gaps (methodology above).
5. If the fork needs a different PSyclone/XIOS than the env pins (`py-psyclone@3.2.2`,
   `xios@2252`) → it's an L2 case needing a second env; flag to maintainer before building.

**Done when:** u-dt000 runs end-to-end with its real ice-giant forcing, **or** the fork is
confirmed unavailable/inaccessible (documented in PR #8 with whom was asked).

## Follow-up 2 — Merge-fork-onto-tag support in extract-sources.sh

**Why:** upstream `dependencies.yaml` lets a repo list **multiple** sources (clone a
tag, then merge a fork branch on top — like fcm_extract). `extract-sources.sh` currently
takes only the FIRST entry (single ref). Follow-up 1 may need a fork merged onto a tag.

**Steps:**
- Extend the parser to handle a list per repo; after extracting the base ref, apply the
  additional ref(s) as a merge/overlay into `SOURCE_ROOT/<repo>`. Keep it OFFLINE (all
  refs must be in the mirror) and deterministic; error clearly on conflicts.
- Decide the overlay mechanism: a real `git merge` in a throwaway worktree vs a
  `git archive` of each ref layered in order. A worktree merge matches upstream semantics
  (conflicts surface) but needs a writable clone, not just `git archive`.

**Done when:** a suite can declare `[tag, fork-branch]` for a repo and the extracted tree
is the merged source, offline.

## Follow-up 3 — Minor cleanups (DONE)

- **Dead upstream extract Jinja — DONE.** Removed `MIRROR_LOC`/`USE_MIRRORS`/
  `USE_TOKENS` + the `ROSE_APP_COMMAND_KEY` Jinja branch from the `[[extract]]` task
  in u-dn704 + u-dr932 `flow.cylc`, the matching `rose-suite.conf` vars, their
  `meta/rose-meta.conf` schema sections, and the now-inaccurate mirror/`get_git_sources`
  text in both READMEs (replaced with the offline `extract-sources.sh` description).
  u-dt000 had none of these. `grep -rn MIRROR_LOC|USE_MIRRORS|USE_TOKENS|ROSE_APP_COMMAND_KEY
  examples/science-suites/` → empty.
- **patch-10 cosmetic log — DONE.** `10-lfric_core-stop-timing-patch.sh` now re-greps for
  `optional :: timing_section_name` after the perl `s///` and only logs "Patched
  stop_timing signature" when the substitution actually applied (perl `s///` exits 0
  even on no-match).
- **dn704 data — DONE (staged + runs end-to-end).** The NWP ancils/start-dump/`um_aux` are
  staged at the default `BIG_DATA_DIR=/projects/u35v/sw/lfricdata` and match dn704's C12
  config (`start_dumps/nwp-gal9/apps1.1/nwp-gal9_N320L70_C12L70.nc`, `ancils/basic-gal/yak/C12`,
  `um_aux/spectral/ga7_1`, `um_aux/UKCA/radaer/ga7_1`). The confirming end-to-end run is
  done (`run2`, see "Done so far"); the run fixes (HDF5 locking + dedicated XIOS server
  MPMD + single-level server) are committed — runs multi-rank with parallel-HDF5 output.
