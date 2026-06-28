# PLAN — Stage-3 follow-ups (next)

Open work after the per-suite **offline source mechanism** and the **Stage→examples
rename** landed. Branch `stage3-science-suites`, PR #8.

## Done so far (context, don't redo)

- **u-dr932** runs end-to-end on the built env (`spack`), re-verified after the shared
  `HDF5_USE_FILE_LOCKING=FALSE` change. Now also validated through the new offline-extract
  path (`run7`).
- **u-dn704** builds + meshes; its NWP `um_aux` ctldata + ancils + C12 start dump are now
  staged under the default `BIG_DATA_DIR=/projects/u35v/sw/lfricdata` (matches its C12
  config), so it is **no longer data-gated** — only a confirming end-to-end run is
  outstanding (see follow-up 3).
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
- **dn704 data — DECIDED (staged).** The NWP ancils/start-dump/`um_aux` are staged at the
  default `BIG_DATA_DIR=/projects/u35v/sw/lfricdata` and match dn704's C12 config
  (`start_dumps/nwp-gal9/apps1.1/nwp-gal9_N320L70_C12L70.nc`, `ancils/basic-gal/yak/C12`,
  `um_aux/spectral/ga7_1`, `um_aux/UKCA/radaer/ga7_1`); `flow.cylc` already defaults to
  that path. dn704 is **no longer data-gated**. Remaining: a confirming end-to-end run
  (heavy/scheduler-gated — run when ready).
