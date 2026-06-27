# Stage 3 — run real LFRic science suites (Rose/Cylc)

This directory holds **worked examples of Stage 3**: running real LFRic
**Rose/Cylc science suites** on the environment that Stage 1 built. Scientists run
LFRic this way — `cylc` schedules the suite's task graph (extract → build → mesh →
run) and submits each task to Slurm; `rose` materialises each task's namelist
config. So Stage 3 runs the suites *that* way, rather than reinventing it.

> The reproducible **core** of this repo is the environment (Stage 1,
> `scripts/build.sh`). These suites are **not** that core — they are things you do
> *with* it. Treat them as templates to copy and adapt. They are ported from the
> upstream [Isambard3-LFRic-Env-Science-Suites](https://github.com/UniExeterRSE/Isambard3-LFRic-Env-Science-Suites).

The environment Stage 1 builds already ships `cylc`, `rose` and `rose_picker` in
its view (dependencies of `lfric-apps-isambard`), so there is nothing extra to
install — `run-suite.sh` activates the env and the suite tasks use that same
`cylc`/`rose`.

## The suites

| Suite | Science case | Status on this env |
|-------|--------------|--------------------|
| **u-dr932** | GungHo Shallow/Deep Hot Jupiter temperature forcing (C48 multigrid, idealised) | ✅ **builds + runs end-to-end** — self-contained (radiation off, analytic init; no external data). Validated on a Grace compute node (`lfric_atm` ran 72 steps to completion). |
| **u-dn704** | LFRic Atm NWP GAL9 @ C12 | ⚠️ **builds + meshes** (validated on a compute node); run is **data-gated** — at run time it fetches Met-Office `um_aux` ctldata (UKCA radaer + spectral files) over SSH and reads ancillaries + a start dump under `BIG_DATA_DIR`, none of which are in this repo / accessible without MO SSO |
| **u-dt000** | LFRic Atm Uranus/Neptune temperature forcing | ⚠️ **builds + meshes + launches the model** (validated on a Grace node: 108 ranks via `srun`, namelists read); run is **blocked on a missing upstream LFRic fork**, not config or version. The suite's core science is `theta_forcing='ice_giants_obs_like'` in `namelist:external_forcing`, which is **absent from both this repo's vendored vn3.1.1 AND the suite's own declared mainline `lfric_apps@vn2.2`** (verified by extracting both: no `ice_giants_obs_like`; `held_suarez_sigma_b` isn't a namelist field in either — `SIGMA_B=0.7` is a hardcoded `parameter`). The upstream suite's extract points only at MetOffice mainline vn2.2, which lacks this science, so the ice-giant forcing lives in an **unidentified fork the suite does not reference**. The model aborts at `Cannot match namelist object name held_suarez_sigma_b` / `STOP 1`. No namelist forward-port can fix this; running dt000's science needs that fork located + staged. See `PLAN.md`. |

### Version alignment (forward-porting suite configs)

This repo's vendored LFRic is **newer** (vn3.1.1) than the upstream suites pin
(vn3.0 / vn2.2), and Stage 3 builds `lfric_atm` from the vendored source (see
below). So a suite's namelists must match **vn3.1.1**, not the version it was
written for. These are mechanical, non-science edits — e.g. u-dr932/u-dn704's
`finite_element` namelist gained `coord_space='Wchi'` and `coord_order_nonprime=1`
(required by vn3.1.1, absent in vn3.0). This is the legitimate adaptation: a
scientist running on *this* env writes vn3.1.1 configs. The deeper a suite's
version lag, the more such edits its run needs.

There is a limit to forward-porting, though: it can only reshape *run config* for
science the model already implements. When a suite's science needs **code** that the
model lacks, no namelist edit can bridge the gap — that's a *source* / build-time
divergence. The clean way to express it is the upstream-native per-suite
`dependencies.yaml` (each LFRic-source repo with `source:`+`ref:`, which can even merge
a fork onto a tag); see `PLAN.md` for the offline-extract design. u-dt000 is the hard
case: its `ice_giants_obs_like` forcing is in **neither** the vendored vn3.1.1 **nor**
its own declared mainline vn2.2 — it needs a fork the suite doesn't reference, which
must be located upstream first. See `PLAN.md`.

## How it works here (what was adapted)

Each suite is the upstream Rose/Cylc suite with three site-specific changes, so it
runs offline against *our* env on Isambard 3:

1. **Sources → per-suite offline extract (`dependencies.yaml`).** Each suite
   declares the LFRic-source refs it builds in a **`dependencies.yaml`** (the
   upstream-native shape: `lfric_apps`, `lfric_core`, `casim`, `jules`, `socrates`,
   `ukca`, each with `source:` + `ref:`). The suite's `extract` /
   `git_extract_lfric` task runs `site/extract-sources.sh`, which materialises each
   declared ref **offline** from this repo's vendored **local mirrors** — `git
   archive` from `vendor/lfric_apps` / `vendor/lfric_core` / `vendor/physics/*`, no
   network — into the suite's `SOURCE_ROOT`, then applies the LFRic-source **patch
   stack** (the same `patches/*-lfric_*` used by Stage 1/2, retargeted via
   `LFRIC_SRC_ROOT`). The build reads that per-suite extracted tree
   (`APPS_ROOT_DIR`/`CORE_ROOT_DIR`/`PHYSICS_ROOT` → `$SOURCE_ROOT/*`). This is the
   **per-suite source axis**: a suite can build a *different* ref (its science)
   just by editing `dependencies.yaml`. **Offline contract:** a ref is extractable
   iff it is already in the local mirror (the mirrors are full clones, carrying all
   fetched tags/branches); a missing or *fork* ref must be staged once, online,
   into the mirror first (`git -C vendor/<repo> remote add <fork> <url> && git
   fetch <fork>`), after which it is offline. Strict-offline by default: a missing
   ref is a hard error naming what to stage. (Merging a fork branch *onto* a tag,
   as upstream `dependencies.yaml` allows, is not yet supported here.)
2. **Env activation → our modulefile.** `site/activate-env.sh` (passed as the
   suite's `ACTIVATE_ENV`) `module load`s `lfric-env/$LFRIC_STACK` and sets the
   variant's MPI/IO compiler wrappers + the view's include/lib — the Stage-3
   analogue of upstream's `env_lfric/activate.sh`.
3. **Cylc platform → Slurm.** `run-suite.sh` runs the repo's opt-in
   `scripts/setup-cylc.sh`, which writes the `isambard3` platform
   (`job runner = slurm`, on `localhost`) and a roomy `cylc-run` dir into
   `~/.cylc/flow/` (idempotent; the same setup `pixi run setup-cylc` does).

## Prerequisites

- **Stage 1 built** for the variant you want (`scripts/build.sbatch`). The
  proven variant for these suites is **`spack`** (the suites' build hard-codes
  `FC=mpif90`, the spack variant's native wrapper).
- **Physics submodules initialised** (as for Stage 2):
  `git submodule update --init --jobs 4 -- vendor/physics/{casim,jules,socrates,ukca}`
  (or `pixi run init-physics`).

## Run it

From the repo root, on a **login node** (the Cylc scheduler runs here and submits
the heavy tasks to Slurm — do **not** wrap this in `sbatch`):

```bash
LFRIC_STACK=spack bash examples/science-suites/run-suite.sh u-dr932
```

Watch it:

```bash
cylc tui u-dr932                 # interactive
cylc workflow-state u-dr932      # one-shot task states
```

`run-suite.sh` activates the env, installs the Cylc site config, and runs
`cylc vip` (validate-install-play) with the right template variables. A successful
run ends with the `lfric_atm` task `succeeded`; output lands under
`$CYLC_RUN_BASE/<suite>/runN/share/output`.

To re-run cleanly: `cylc stop --now <suite>; cylc clean <suite> -y`.

## Adapting this for your own suite

Drop your Rose/Cylc suite in a new directory here and make the same three changes:
point `APPS_ROOT_DIR`/`CORE_ROOT_DIR`/`PHYSICS_ROOT` at `{{ REPO_ROOT }}/vendor/…`,
reduce the extract task to a vendored-source check, and let `run-suite.sh` inject
`ACTIVATE_ENV`/`LFRIC_STACK`/`LFRIC_PREFIX`/`REPO_ROOT`. The `site/activate-env.sh`
glue (plus `scripts/setup-cylc.sh`) is reusable as-is — that is the contract
between the built environment and a science suite.
