# Held-Suarez theta relaxation is driven by `wind_relax_time_scale`, not `theta_relax_time_scale`

**Status:** open, upstream — in `dennissergeev/lfric_apps@ice_giants_tf`, not in
MetOffice mainline. Not yet reported. **Inert for u-dt000 as configured** (see §4), so
nothing here blocks this suite; it is recorded because the patch we carry is what gets
handed back to Denis, and this should go with it.

**Where it lives:** `patches/optional/32-lfric_apps-ice-giants-forcing.patch`, the hunk
against `science/gungho/source/kernel/external_forcing/held_suarez_forcings_mod.F90`.
Denis' code, not our forward-port — we changed only the `chi2llr` call signature in
`ice_giants_kernel_mod.F90`. Independently flagged by a Codex review, quoted in §5.

---

## 1. What the branch changes

Mainline holds the three Held-Suarez relaxation rates as module `parameter`s — the
canonical Held & Suarez (1994) set:

```fortran
real(kind=r_def), parameter :: KF = 1._r_def/86400._r_def ! 1 day-1
real(kind=r_def), parameter :: KA = KF/40.0_r_def         ! 1/40 day-1
real(kind=r_def), parameter :: KS = KF/4.0_r_def          ! 1/4 day-1
```

The branch makes them namelist-driven, recomputed inside each function. In
`held_suarez_damping` (the **wind** drag):

```fortran
KF = 1.0_r_def / (wind_relax_time_scale * 86400.0_r_def)
```

and in `held_suarez_newton_frequency` (the **temperature** relaxation):

```fortran
KF = 1.0_r_def / (wind_relax_time_scale * 86400.0_r_def)
KA = KF / 40.0_r_def
KS = KF / 4.0_r_def
```

The module `use`s only `held_suarez_sigma_b, wind_relax_time_scale` from
`external_forcing_config_mod`. `theta_relax_time_scale` — added by the same branch, in
the same namelist, `compulsory=true`, described as "Temperature relaxation time scale in
days" — is never read here. Its only consumer is `ice_giants_forcings_mod`.

## 2. Two defects, not one

**(a) Wrong variable.** The thermal relaxation reads the wind timescale. Any
configuration that sets the two differently gets a thermal tendency that silently
ignores `theta_relax_time_scale`. This is the Codex finding.

**(b) `KA` and `KS` should not scale with a timescale at all.** In canonical
Held-Suarez the three rates are independent physical constants: k_a = 1/40 day⁻¹,
k_s = 1/4 day⁻¹, k_f = 1 day⁻¹. `KA = KF/40` and `KS = KF/4` hold in mainline *only*
because k_f happens to be exactly 1 day⁻¹ there — it is an arithmetic coincidence of
the standard parameter set, not a physical relation. The moment k_f becomes
configurable the identity breaks, and the derived rates inherit a factor they have no
business inheriting.

So fixing (a) alone — swapping `wind_relax_time_scale` for `theta_relax_time_scale` in
`held_suarez_newton_frequency` — removes the cross-talk but leaves the thermal
relaxation scaled by a timescale, i.e. `theta_relax_time_scale`× slower than canonical
Held-Suarez rather than `wind_relax_time_scale`× slower. That is defensible as a
deliberate generalisation, but it is a change in meaning that should be stated, not
inherited from a refactor.

**Concrete size of it.** With `wind_relax_time_scale=100.0` (u-dt000's value) a
`theta_forcing='held_suarez'` run gets

| rate | canonical | on this branch |
|---|---|---|
| k_a (free atmosphere) | 1/40 day⁻¹ | 1/4000 day⁻¹ |
| k_s (surface, equator) | 1/4 day⁻¹ | 1/400 day⁻¹ |

— a 100× weaker Newtonian cooling, with no namelist item able to correct it.

## 3. Who is affected

`held_suarez_newton_frequency` has two callers in the vn3.2 tree:

- `held_suarez_fv_kernel_mod.F90` → `theta_forcing='held_suarez'`
- `tidally_locked_earth_kernel_mod.F90` → `theta_forcing='tidally_locked_earth'`

Both take the defect. `held_suarez_damping` (`held_suarez_fv_wind_kernel_mod.F90`,
`wind_forcing='held_suarez'`) is **correct** — k_f *is* the wind drag rate, and
generalising it to `wind_relax_time_scale` is exactly what that item is for.

Scope is limited to trees carrying this patch: `patches/optional/` is outside the
shared stack, and u-dt000's extract task is the only thing that applies it. u-dr932 and
u-dn704 build from unpatched sources and are unaffected.

## 4. Why u-dt000 does not hit it

Its `namelist:external_forcing` is:

```
theta_forcing='ice_giants_obs_like'
wind_forcing='held_suarez'
held_suarez_sigma_b=0.97
theta_relax_time_scale=100.0
wind_relax_time_scale=100.0
```

- The theta path goes to `ice_giants_forcings_mod`, which reads
  `theta_relax_time_scale` correctly and never calls
  `held_suarez_newton_frequency`.
- The wind path uses `held_suarez_damping`, which is the correct function.
- And the two timescales are equal anyway, so even defect (a) would be numerically
  invisible here.

The 72 000-step run recorded in [`../README.md`](../README.md) is therefore unaffected.
This is a latent trap for the *next* configuration, not a correction to that result.

## 5. The Codex wording

Kept verbatim because it is the crisper statement of defect (a), and names the fix:

> When a configuration uses Held–Suarez temperature forcing and assigns different
> temperature and wind relaxation timescales, this temperature-relaxation function
> derives KF, KA, and KS from wind_relax_time_scale, so changing theta_relax_time_scale
> has no effect on that forcing and the resulting thermal tendency is silently wrong.
> Use theta_relax_time_scale here, while retaining wind_relax_time_scale in
> held_suarez_damping.

## 6. What to report, and to whom

To **Denis Sergeev**, against `ice_giants_tf`, since this is his branch and the patch we
carry is the diff to hand him (see the header of
`patches/optional/32-lfric_apps-ice-giants-forcing-patch.sh`). It only becomes a Met
Office mainline concern if the branch is merged as-is.

Minimal fix for (a):

```fortran
use external_forcing_config_mod, only: held_suarez_sigma_b,    &
                                       wind_relax_time_scale,  &
                                       theta_relax_time_scale
...
! in held_suarez_newton_frequency only:
KF = 1.0_r_def / (theta_relax_time_scale * 86400.0_r_def)
```

leaving `held_suarez_damping` on `wind_relax_time_scale`. Worth asking at the same time
whether (b) is intended — i.e. whether `theta_relax_time_scale` is meant to rescale k_a
and k_s at all, or whether those should stay at their canonical 40-day and 4-day values
with only k_f configurable.

Any fix has to be reflected in `32-lfric_apps-ice-giants-forcing.patch` — regenerate it
with the recipe in that script's header, and re-verify u-dt000 still reproduces the run
in [`../README.md`](../README.md).
