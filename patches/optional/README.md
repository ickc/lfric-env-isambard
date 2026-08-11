# `patches/optional/` — per-suite LFRic-source patches

Patches in `patches/` (top level) are the **stack**: `patch-all.sh` applies every
`*-patch.sh` there to `vendor/` for the Stage-1 build, and
`examples/science-suites/site/patch-sources.sh` applies the `*-lfric_{core,apps}-*`
subset to each science-suite's freshly extracted source tree. Everything in that
stack has to be safe for *every* consumer.

This directory holds the ones that are **not**: source patches a single suite opts
into, because applying them everywhere would change the contract for suites that
did not ask for them. They are deliberately outside the glob — nothing applies them
automatically. The suite that wants one invokes it by path from its own `extract`
task, with `LFRIC_SRC_ROOT` pointed at the extracted tree:

```
LFRIC_SRC_ROOT="$SOURCE_ROOT" \
  bash "$REPO_ROOT/patches/optional/32-lfric_apps-ice-giants-forcing-patch.sh"
```

so the opt-in is visible in the suite's own reviewable diff rather than hidden in
shared machinery.

| Patch | Opted into by | Why it cannot be in the shared stack |
|---|---|---|
| `32-lfric_apps-ice-giants-forcing` | `u-dt000` | It adds three **compulsory** `namelist:external_forcing` items (`theta_relax_time_scale`, `wind_relax_time_scale`, `held_suarez_sigma_b`). Every gungho app config would then have to set them, so u-dr932 and u-dn704 would abort reading their namelists. |

Numbering continues the top-level series (`3x` = `lfric_apps`), so the family a
patch belongs to is still readable at a glance.
