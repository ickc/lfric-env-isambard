# PLAN — Stage-3 follow-ups (next)

Open work after the per-suite **offline source mechanism** and the **Stage→examples
rename** landed. Branch `stage3-science-suites`, PR #8.

## Done so far (context, don't redo)

- **u-dr932** runs end-to-end on the **cray environment** (`run8`): cray-mpich + `srun`
  (attached XIOS, lat-lon output), 24 ranks on one node, succeeded. Ported off mpiexec like
  dn704 (mesh→`srun`, `LAUNCH_SCRIPT`→`site/bin`); `TOTAL_RANKS_REQ` 64→24 (valid C48
  decomposition). Single-node, so it uses on-node shared memory — the interconnect is the
  multi-node case (dn704). (Earlier spack `run7` superseded.)
- **u-dn704** runs **end-to-end, genuinely multi-node, on the `cray` variant** (`run3`):
  24 model ranks + 1 dedicated XIOS server across **2 nodes** over the **Slingshot (cxi)**
  interconnect; full UGRID + NAME diagnostics written by the XIOS server
  (lfric_gal_diagnostics.nc ~62 MB). NWP `um_aux`/ancils/C12 start dump staged at default
  `BIG_DATA_DIR=/projects/u35v/sw/lfricdata`.
  - **Use the cray variant, not spack, for real runs.** spack `mpich` is `ch4:ofi` over
    spack `libfabric@2.5.1` whose providers are tcp/sockets/udp only (no `cxi`) → inter-node
    MPI over TCP; and it's built `~slurm` so srun can't PMI it (hence Hydra/mpiexec). The
    `cray` variant links cray-mpich + system `libfabric` (cxi) + srun = Slingshot RDMA.
    Verified on a 2-node MPI micro-test: `MPICH_OFI_USE_PROVIDER=cxi`, NIC `cxi0`, ~7 µs
    round-trip (RDMA-class, not TCP), cross-node allreduce/pingpong OK.
  - **Launcher (`examples/science-suites/site/bin/launch-exe`, new):** srun for the model;
    when `XIOS_SERVER_MODE=True`, launches model + `xios_server.exe` via `srun --multi-prog`
    → client+server in ONE `MPI_COMM_WORLD` (validated on a 2-node job). The MO meto
    launch-exe only wires the XIOS-server MPMD for mpiexec, not srun. dn704 flow.cylc points
    `LAUNCH_SCRIPT` at it.
  - **Forcing the model across nodes:** `--nodes=2 --ntasks=25 --ntasks-per-node=13` → model
    ranks 0-12 on node 1, 13-23 on node 2 (server rank 24 on node 2). Without
    `--ntasks-per-node`, Slurm block-packs all 24 model ranks on node 1 (only the server on
    node 2) — a weak demo. `MPICH_ENV_DISPLAY` is on so job.out self-documents cxi.
  - **Other fixes:** `HDF5_USE_FILE_LOCKING=FALSE` in app `[env]` (Lustre nc_create);
    `using_server2=false` in `iodef_gal_nwp.xml` (2-level server tripped an MPICH yaksa
    assertion); mesh app uses `srun --ntasks=1` (cray-mpich has no `mpiexec`).
  - dn704 now **targets the cray variant** (the srun launcher won't drive spack mpich).
    Earlier spack/mpiexec runs (`run2`, single-node TCP) are superseded. dr932 is now also
    cray/srun (single-node); both could be scaled multi-node by raising the rank count.
- **All suites run on the cray environment now** (mesh→`srun`, `LAUNCH_SCRIPT`→`site/bin/launch-exe`,
  no mpiexec). dn704 = multi-node + XIOS server; dr932 = single-node attached; dt000 = config
  ported (mirrors dn704) but NOT run (ice-giant blocked, follow-up 1).
- **u-dt000** config ported to cray/srun (validates) but still **blocked on its missing science**
  (see follow-up 1) — not run. Infra fixes in place (`env-script = eval $(rose task-env)` for
  `ROSE_DATA`; `--mem=0`).
- **Mechanism (b) — per-suite offline source** (commit `09ca75a`): each suite has a
  `dependencies.yaml`; `examples/science-suites/site/extract-sources.sh` extracts each
  declared `repo@ref` OFFLINE from the vendored local mirrors (`git archive`, no network)
  into `SOURCE_ROOT/{lfric_apps,lfric_core,physics/*}`, then applies the LFRic-source
  patch stack (`patches/{10,11,30}` honour `LFRIC_SRC_ROOT`, default `vendor/`). Strict
  offline: a ref absent from the mirror is a hard error naming what to stage.
- **Rename** (commit `bedd813`): Stage 2/3 reframed as sibling *examples* on the one
  prerequisite build (Stage 1); `examples/lfric-atm → examples/minimal-compile`.

**Run a suite (cray, the default):** `bash examples/science-suites/run-suite.sh <id>`.
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
  done (`run3`, cray variant); runs **multi-node** (2 nodes, Slingshot/cxi) with a
  dedicated XIOS server + parallel-HDF5 output — see "Done so far" for the full story.
