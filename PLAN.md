# PLAN — Stage-3 science-suite follow-ups

Follow-up work after u-dn704 (NWP GAL9) reached a full end-to-end run on the built
env (commit `dc94bf2`, PR #8). Two items:

1. **Re-verify u-dr932** still runs after the shared `activate-env.sh` change (quick).
2. **Forward-port u-dt000** (Uranus/Neptune, vn2.2) to run end-to-end (larger).

The root cause for both is the same as u-dn704: the suites pin **older LFRic** than this
repo vendors (env is **vn3.1.1**), so their Rose/Cylc configs use an older namelist
schema that the built model rejects. The fix is to forward-port each suite's config to
the env's schema, verifying every change against the env's own model source and
canonical configs — never guessing science values.

---

## Shared context / methodology (read first)

**Run a suite (spack variant):**
```bash
cd <repo>
LFRIC_STACK=spack bash examples/science-suites/run-suite.sh <suite-id>
```

**Fast iteration on the run task** (build + mesh are cached after the first run, so you
only re-run the model — minutes, not a rebuild):
```bash
. scripts/common.sh; . examples/science-suites/site/activate-env.sh   # gets cylc/rose on PATH
# edit examples/science-suites/<suite>/app/lfric_atm/rose-app.conf (or flow.cylc)
cylc reinstall <suite>/run1            # app/rose-app.conf changes
cylc reload   <suite>/run1             # ONLY if flow.cylc changed (directives/graph)
cylc trigger  <suite>//1/lfric_atm     # re-run just the model task
# if the scheduler has stopped:  cylc play <suite>/run1   then trigger
cylc workflow-state <suite>//1/lfric_atm        # poll: submitted/running/succeeded/failed
```
Read failures in `~/cylc-run/<suite>/run1/log/job/1/lfric_atm/NN/job.{err,out}` (NN =
latest attempt). `activate-env.sh` is sourced by tasks via an absolute repo path, so
edits to it are live without reinstall.

**The reference configs (env's own, known-good for vn3.1.1) — diff against these:**
- `vendor/lfric_apps/rose-stem/app/ngarch/rose-app.conf` — the **canonical GAL atmosphere**
  config. Best match for NWP/GAL science (u-dn704's params matched it with zero conflicts).
- `vendor/lfric_apps/applications/lfric_atm/example/configuration.nml` — a known-good
  **generated** namelist (shows the exact field set + string-enum forms the model accepts).
  NOTE: agrees with ngarch on most namelists but **differs on jules_pftparm tunings** —
  prefer ngarch for PFT science.
- `vendor/lfric_apps/rose-stem/app/gungho_model/rose-app.conf` — idealised; useful for
  cross-checking structure but not for GAL science values.

**The classes of gap seen in u-dn704 (expect the same families):**
| Symptom in job.err | Cause | Fix pattern |
|---|---|---|
| `Cannot match namelist object name ...` | old array-namelist vs new indexed/per-instance schema | reshape; check the reader in `vendor/lfric_apps/interfaces/.../*_init_mod.f90` for how instances are keyed |
| `skip missing optional source: namelist:X` (WARN) | `[file:configuration.nml]` source list doesn't match a renamed/indexed namelist | fix the `source=(...)` entry (e.g. `name` -> `name(:)`) |
| `Parent model not set to LFRic` | missing `jules_model_environment_lfric` | add it, `l_jules_parent='lfric'` |
| `... should be 0 or 1` / `Invalid value given for X` | compulsory field unset -> defaults to imdi, hits a `check_*` range test | set it from ngarch/example |
| build/run init `*_config_mod` aborts | LFRic hard-forces some flags in `jules_physics_init` -> consistency checks | grep the forcing + the `check_*` routine, set the dependent flag |
| `Out Of Memory` / OOM-killed | Slurm `--mem` unset -> ~1G/task default | add `--mem` to the task `[[[directives]]]` in flow.cylc |
| `nc_create ... Permission denied` (NetCDF-4) | HDF5 flock() on Lustre | already fixed globally in `activate-env.sh` (`HDF5_USE_FILE_LOCKING=FALSE`) |

**How to find the authoritative fix for a check failure:** grep the error string under
`vendor/physics/jules/src` and `vendor/lfric_apps/interfaces/`, read the guard condition
and any LFRic-side forcing, then take the value from ngarch/example. Reading the source
to anticipate the *next* failure is worth it (queue waits can be hours — see below).

**Queue reality:** the `grace` partition can be saturated; a 15-min job may pend for
hours (account is limited to QOS `normal`, no debug lane). Iterate in batches — read the
whole `check_*` routine and fix every field it will trip, not one per cycle. Poll with a
background watcher loop on `cylc workflow-state`.

**Invariant — do not touch:** Stage-1/Stage-2 build paths and the `cray`/`spack`
concretize assertions. These are run-task config changes only. Don't commit the
`vendor/*` submodule working-tree changes (expected from `patch-all.sh`).

---

## Item 1 — Re-verify u-dr932 (Hot Jupiter) — quick

**Why:** u-dr932 already ran end-to-end (PR #8), but the new
`HDF5_USE_FILE_LOCKING=FALSE` in `site/activate-env.sh` is shared by all suites. It
should only help (or be a no-op), but confirm no regression.

**Steps:**
1. `LFRIC_STACK=spack bash examples/science-suites/run-suite.sh u-dr932`
   (or, if a `run1` exists: `cylc reinstall` is unnecessary for the activate-env change —
   just `cylc play u-dr932/run1 && cylc trigger u-dr932//1/<run-task>`).
2. Watch to terminal state; confirm `lfric_atm` (or u-dr932's run task) still `succeeded`
   and writes its diagnostics.
3. If green: note it in PR #8. If it regresses: inspect job.err — most likely unrelated
   to HDF5 (the var is guarded with `:-FALSE`, honouring any pre-set value).

**Expected effort:** one run + check. Main risk is queue wait, not correctness.

---

## Item 2 — Forward-port u-dt000 (Uranus/Neptune, vn2.2) — larger

**Why it's harder than u-dn704:** u-dt000 declares an even older metadata version
(`vn2.2` vs u-dn704's `vn3.0`); the env ships `vn2.2`, `vn3.0`, `vn3.1`, `HEAD` metadata,
so the gap to vn3.1.1 is wider. Expect *more* of the same schema/consistency gaps, plus
possibly version-specific renames between vn2.2->vn3.x.

**It is a giant-planet (not GAL/Earth) config** — so DO NOT blindly copy ngarch science.
Many JULES/surface/aerosol namelists that matter for GAL may be absent or different here.
Forward-port the **schema** (structure, compulsory infra fields, forced-flag
consistency) and only touch science values where (a) the model demands a valid value and
(b) you can source it from the suite's own intent or a defensible reference. Where the
suite deliberately omits Earth physics, keep it omitted.

**Recommended sequence:**
1. **Baseline run** to confirm build+mesh still pass and capture the first run-task error:
   `LFRIC_STACK=spack bash examples/science-suites/run-suite.sh u-dt000`.
2. **Bump the metadata pointer** if helpful: the app's `meta=lfric-lfric_atm/vn2.2`. The
   env has vn3.0/vn3.1 meta; consider whether the suite should target vn3.1 (closest to
   the built model). Investigate `rose app-upgrade` — its version-to-version macros
   (`vendor/lfric_apps/.../rose-meta/.../version*.py`) may mechanically migrate
   vn2.2->vn3.x and do a chunk of the work. (Static `rose macro --validate` was a dead
   end for u-dn704 because the metadata is import-distributed across repos and needs an
   assembled tree the build doesn't leave behind — so don't sink time there unless an
   assembled tree is available.)
3. **Iterate the run task** using the methodology above. Anticipate (from u-dn704):
   - jules_pftparm reshape/keying + pft_name_io, IF u-dt000 uses JULES land — a giant-gas
     planet may not, in which case skip the whole JULES land stack.
   - jules_model_environment_lfric / l_jules_parent='lfric' (if JULES is active).
   - compulsory jules_surface / jules_radiation / jules_vegetation fields + forced-flag
     consistency (l_spec_albedo, all_tiles, etc.) — only if those namelists are in play.
   - `--mem` on the run task (almost certainly needed; resolution may be larger than C12).
   - HDF5 locking is already handled globally.
4. **Data:** check what inputs u-dt000 needs (start dump / ancils / spectra). Unlike
   u-dn704, the Uranus/Neptune data may NOT be staged on `/projects/u35v/sw/lfricdata`.
   If `[file:*]` sources point at MetOffice clones or missing paths, find or stage the
   data first (this could be the real blocker — flag to the maintainer early if so).
5. **Science sign-off:** because giant-planet config is further from the env's GAL
   reference, surface any value choices to the maintainer rather than adopting Earth
   defaults silently. Document each forward-port edit with a `# Stage-3 (this repo): ...`
   comment citing the source (as in u-dn704).

**Definition of done:** u-dt000 either (a) runs end-to-end and writes diagnostics, or
(b) is blocked only by something outside the env (missing giant-planet input data behind
access we don't have), clearly documented in PR #8 with the exact gap.

**Open question for the maintainer:** is aligning the *vendored* LFRic pin with the
suites' pinned versions ever preferable to per-suite forward-porting? Forward-porting is
the right call for demonstrating the env runs real suites; pin-alignment would be the
fix if these suites must run *unmodified*. Out of scope here, but worth a decision.

---

## OUTCOMES (2026-06-27)

### Item 1 — u-dr932: ✅ DONE
Re-ran on the `spack` variant after the shared `HDF5_USE_FILE_LOCKING=FALSE` change
(`run6`). `lfric_atm` **succeeded** — no regression. The HDF5 var is guarded
(`:-FALSE`) and only helps NetCDF-4 writes on Lustre.

### Item 2 — u-dt000: ⚠️ BLOCKED-BY-MODEL (DoD case b), not config
Two infra fixes were applied to `u-dt000/flow.cylc` and they work — the run now gets
all the way onto a Grace node and into the model:
- `[runtime][[root]] env-script = eval $(rose task-env)` — sets `ROSE_DATA` et al. for
  the inline `mkdir $ROSE_DATA/History_Data` that runs under `set -u` before
  `rose task-run` (the previous run died here with `ROSE_DATA: unbound variable`).
- `--mem=0` on the `lfric_atm` task directives — full node memory (matches u-dr932).

With those, `lfric_atm` launches 108 ranks via `srun`, reads the namelists, and the
**model** aborts: `Cannot match namelist object name held_suarez_sigma_b` / `STOP 1`.

**Root cause (verified by extracting BOTH refs from the local mirrors, not guessed):**
u-dt000's whole science is `theta_forcing='ice_giants_obs_like'` in
`namelist:external_forcing` — a Uranus/Neptune forcing that is **absent from BOTH this
repo's vendored vn3.1.1 AND the suite's own declared mainline `lfric_apps@vn2.2`**.
Critically, the upstream `git_extract_lfric` points only at `MetOffice/lfric_apps@vn2.2`
+ `lfric_core@core2.2` (mainline, no fork merge) — and that mainline vn2.2 does NOT
contain the forcing either. So the ice-giant scheme lives in an **unidentified fork the
suite does not reference**; it must be located upstream before dt000 can run its science.
(An earlier note here claimed vn2.2 mainline had it and vn3.1.1 dropped it — WRONG;
re-verified by `git archive vn2.2 | grep ice_giants_obs_like` → empty.) Evidence:
- `external_forcing_config_mod.f90` accepts only `theta_forcing ∈ {deep_hot_jupiter,
  earth_like, held_suarez, none, shallow_hot_jupiter, temp_tend, tidally_locked_earth}`.
- `grep -rin ice_giant vendor/` (excluding the build dir) → empty.
- The vn3.1.1 `external_forcing` reader has no `held_suarez_sigma_b`,
  `theta_relax_time_scale`, or `wind_relax_time_scale` (vn2.2 fields, removed); its
  Held-Suarez forcing hardcodes Earth-tuned `parameter`s (`SIGMA_B=0.7`, `KA/KS/KF`,
  `T_SURF`, `DT_EQ_POLE`) in `held_suarez_forcings_mod.F90` — not namelist-configurable.

So this is **not** fixable by forward-porting run config: the science needs *code* the
env's model doesn't have. JULES land stack is inactive here (`surface='none'`), so none
of u-dn704's JULES forward-ports apply; and the suite dodges data-gating (`radiation=
'none'`, so its `sp_*_gj1214b` spectral refs are never read). The single gap is the
missing forcing scheme.

### Design discussion — enabling source-divergent suites (Stage 3)

Triggered by the question "do we need a different LFRic *binary* per suite?". Findings:

1. **Stage 1 is deps-only.** `lfric-apps-isambard`'s `install()` just `touch`es a marker;
   the env is compilers + MPI/HDF5/netCDF + XIOS@2252 + **py-psyclone@3.2.2** + shumlib/
   fparser + rose/cylc. It compiles no LFRic.
2. **Stage 2 ⟂ Stage 3.** Both depend only on the Stage-1 env. Stage 3's `flow.cylc` has
   its **own** `build_lfric_atm` that compiles from `vendor/lfric_apps` into the suite's
   share dir — it does *not* consume Stage 2's binary. So a divergent suite needs *its*
   build pointed at different source, **not** "another Stage 2".
3. **Variability is layered:** L0 run config (namelists — dn704/dr932 ✅) · L1 source/
   branch compiled vs the **same** env · L2 source **+** a second env (only if the branch
   pins a different PSyclone/XIOS/fparser) · L3 data (spectra/ancils, orthogonal). Today
   Stage 2 + all suites compile the *same* source with the *same* build config → same
   binary; they differ only at L0. u-dt000 is the first L1/L2 case.
4. **The decisive unknown for u-dt000:** does the ice-giant branch build against PSyclone
   3.2.2 / XIOS 2252 (→ L1, point at a 2nd source root) or pin different versions (→ L2,
   a 2nd spack env)? Checkable from the branch's `dependencies.yaml` / fcm-make config.
5. **Keep it declarative** (repo rule: pinned/offline, no build-time `git checkout`).
   Mechanism options: (a) per-branch pinned submodule; (b) one submodule + suite-declared
   *ref* + offline worktree extract, patches carried as a re-appliable stack; (c) a full
   second variant (env+source). Upstream already models this via the suites' own
   `dependencies.yaml` (declares git sources+refs, can merge a branch onto a tag) + the
   `git_extract_lfric` task the repo currently stubs out for offline — i.e. (b) is the
   upstream-native shape. **Generality caveat:** a branch is necessary but not provably
   sufficient (data/env coupling can also differ), so the right abstraction is a
   declarative per-suite `{source-set, env-variant, data-set}` mapping where almost every
   suite uses the defaults and a divergent suite overrides one axis explicitly.

**Upstream evidence (checked 2026-06-27, the two repos the user pointed to):**
- `UniExeterRSE/lfric-spack` — pure **env-only** model: build deps with Spack, then
  "a manual build of LFRic performed" against them. Confirms env ⊥ source.
- `UniExeterRSE/Isambard3-LFRic-Env-Science-Suites` — one env per toolchain
  (`env_lfric_gcc`/`nvhpc`, both pinning **py-psyclone@3.2.2 + xios@2252, identical to
  ours**) + **per-suite source declaration**: dn704/dr932 via `dependencies.yaml`
  (`lfric_apps/lfric_core/jules/socrates/casim/ukca`, each `source:`+`ref:`, *can merge a
  fork onto a tag*); dt000 via `git_extract_lfric` env (`LFRIC_APPS_REF=vn2.2`,
  `LFRIC_CORE_REF=core2.2`, MetOffice mainline, dep revs from `lfric_apps/dependencies.sh`).
  → The per-experiment unit of variation IS the suite's `dependencies.yaml` (source+ref).

So the abstraction the user sketched (per-suite: tweak/select source → PSyclone/PSyKAl
build → binary + config + data → product) is exactly upstream's. This repo's offline
invariant collapsed that source axis to ONE vendored pin (vn3.1.1) + a stubbed
`git_extract_lfric`; that's why config-only forward-port works for dn704/dr932 (near
vn3.1.1) but not dt000 (vn2.2). The fix that honours BOTH the user's model and offline:
**adopt `dependencies.yaml` as the per-suite source-of-truth and make `git_extract_lfric`
resolve each ref from a LOCAL clone/object store** (no MetOffice network), build there;
the vendored submodules become the offline cache of the common/default refs.

**Offline cache — what's guaranteed (verified 2026-06-27):** the vendored LFRic-source
submodules are **full clones** (not shallow): `lfric_apps` 847 commits / 25 tags / 5
branches, carrying every release tag vn1.0→vn3.1.1. Extracting an arbitrary cached ref
offline works — proved `git -C vendor/lfric_apps archive vn2.2 | tar -x` with **no
network**. Of dt000's declared vn2.2 dep set (`core2.2`, `casim/socrates/ukca@apps2.2`,
`jules@apps2.2`), **5 of 6 are present locally**; only `jules@apps2.2` is missing (the
jules clone lacks that tag — jules tags differently; upstream's own config carries
`JULES_FALLBACK=stable`, which IS present). So the honest guarantee is **"offline after an
explicit, declared pre-fetch"** (same model as `scripts/fetch.sh`): a ref in the mirror →
offline-extractable; a missing or *fork* ref → one online fetch into the mirror (add the
remote), then offline. We CANNOT promise "any ref offline"; we CAN promise "declared refs,
staged once, then offline" — with strict-offline = error-if-missing.

**dt000 is NOT an L1/L2 question after all.** Extracting its OWN declared vn2.2 source
showed `ice_giants_obs_like` / `held_suarez_sigma_b` are absent from mainline vn2.2 too
(SIGMA_B is a hardcoded `parameter` there as in vn3.1.1). So there is no mainline ref to
build that makes dt000's science work — it needs an **unidentified fork** the suite
doesn't reference. dt000 is blocked on *locating that fork upstream*, not on a PSyclone
version question. (The PSyclone-compat question is still real for any genuinely
old-but-mainline suite — just not the blocker here.)

**Terminology (user point, 2026-06-27):** Stage 2 is really a *minimal compilation
example* (compiles a target, runs no science = the smallest L1), and Stage 3 suites are
*full science examples* (compile + run via Cylc). They're not sequential "stages" but
sibling **examples** on top of the one prerequisite (Stage 1 = the env build). Proposed
reframe: keep Stage 1 as "the environment build (core)"; rename 2/3 as
`examples/{minimal-compile, science-suites}`. Scope (dirs/pixi tasks/CLAUDE.md invariant
wording vs docs-only) TBD with maintainer.

**Decision:** PLAN closed — Item 1 ✅, u-dt000 documented as blocked on a missing
upstream fork (not config/version). Follow-ups (separate, scoped, maintainer-approved
direction): (1) implement the `dependencies.yaml`-driven **offline per-suite source**
mechanism (b) — vendored LFRic-source submodules become local mirrors, each suite's
`dependencies.yaml` declares refs, `git_extract_lfric` extracts them offline (+ patches as
a stack); (2) **full rename** Stage 2/3 → `examples/{minimal-compile, science-suites}`
(dirs + pixi tasks + CLAUDE.md invariant wording + markers), Stage 1 stays the core env
build; (3) for dt000, ask upstream (Exeter RSE) where the `ice_giants_obs_like` fork
lives, then stage it as a declared source.

---

## IMPLEMENTATION — mechanism (b), offline per-suite source (in progress)

Maintainer chose: **mechanism (b) first, validate on dr932**; **re-appliable, per-ref
tolerant patch stack**; **full rename** (dirs + tasks). Built so far:

- `examples/science-suites/site/extract-sources.sh` — reads a suite's
  `dependencies.yaml`, extracts each declared repo@ref OFFLINE from the vendored mirror
  (`git archive`, no network) into `SOURCE_ROOT/{lfric_apps,lfric_core,physics/*}`, then
  applies the LFRic-source patch stack. Strict-offline: a ref not in the mirror is a hard
  error naming what to stage. (Merging fork branches onto a tag = future work.)
- `patches/{10,11,30}-*` — `WORKING_DIR` now honours `LFRIC_SRC_ROOT` (default `vendor/`),
  so the SAME patches apply to the per-suite extracted tree. Stage 1/2 unaffected. (Patch
  10 is a no-op on the current core ref — its `stop_timing` hunk isn't needed there; the
  vendored tree that builds today also lacks it. Cosmetic: it still logs "Patched".)
- `u-dr932/dependencies.yaml` — declares the exact commits the submodules are pinned at,
  so the extracted build reproduces the validated run byte-for-byte (verified:
  `diff vendor/lfric_core extracted` → IDENTICAL).
- `u-dr932/app/extract/rose-app.conf` — now calls `extract-sources.sh`.
- `u-dr932/flow.cylc` — `APPS_ROOT_DIR/CORE_ROOT_DIR/PHYSICS_ROOT` repointed from
  `vendor/*` to `$SOURCE_ROOT/*`; added `REPO_ROOT` + `DEPENDENCIES_FILE` to `[[root]]`.

**Validation:** dr932 `run7` — **end-to-end GREEN** ✅ (`extract → build_lfric_atm →
lfric_atm` all succeeded) with the new offline extract: 6 repos materialised from the
mirrors via `git archive` + patch stack, no network, then a normal build+run. Mechanism
(b) proven. All three suites (dr932/dn704/dt000) converted + `cylc validate` clean.
**Committed** as `09ca75a`.

### Full rename — DONE ✅
Stage 2/3 reframed as **examples** on the one prerequisite build (Stage 1, kept as the
core env build). `git mv examples/lfric-atm → examples/minimal-compile`; all path refs,
pixi task comments, CLAUDE.md/README/MAINTAINER framing, the example READMEs, `.gitignore`,
and the per-suite provenance comments updated. Artifact names kept (they name *what*
compiles, not a stage): `BUILD_OK`, `LFRIC_ATM_OK`, the `build-lfric-atm` pixi task.
Invariant re-checked after the rename: **both `cray` and `spack` `CONCRETIZE_OK`** (solve
inputs untouched). `bash -n` + `cylc validate` (all 3 suites) clean.
