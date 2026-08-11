# The energy-conservation diagnostics overflow to `Infinity` at `RDEF_PRECISION=32`

**Status:** open, upstream. Root cause understood at the level of *which expression*;
not yet isolated to *which factor*. Not yet reported to the Met Office.

**Why this file exists:** u-dr932 reproduces it in about ten minutes, which makes it a
good vehicle both for diagnosing the bug and for verifying a fix. This is the high-level
record. Later sessions should add their specifics beneath, or as sibling files.

---

## 1. What you see

Running u-dr932 as committed (`RDEF_PRECISION=32`, deep hot Jupiter, planet radius
9.44 × 10⁷ m), from the **first timestep** onward:

```
Conservation: total energy                                     Infinity
Conservation: horizontal kinetic energy                        Infinity
Conservation: vertical kinetic energy                          Infinity
Conservation: potential energy       0.243197015194917697310691E+33
Conservation: dry internal energy    0.481478916401063851775958E+31
```

Everything else in that block stays finite and evolves smoothly. At timestep 0 the
kinetic terms are `0.000E+00`, because the model starts from rest — the overflow
appears the moment the wind is nonzero, however small.

## 2. What it is not

**It is not a model blow-up, and it does not affect the integration.** In the same run:

- the mixed solver converges every timestep;
- dry mass is conserved to 4.7 × 10⁻⁷ relative over a 17 280-step cycle;
- the physical wind diagnostic `u_in_w3` is O(1–10³) m s⁻¹ throughout and plateaus;
- the run completes and XIOS writes all its output.

`Min/max u ≈ 10¹⁶` in the same log is **not** a velocity — it is the raw W2 flux
degree-of-freedom, and it is identical in 32- and 64-bit builds. Do not read it as
evidence of anything.

**It is also not a misconfiguration.** `RDEF_PRECISION=32` is a legitimate,
long-standing choice in this suite (all of `RDEF`/`R_TRAN`/`R_BL`/`R_SOLVER` are 32,
`R_PHYS` is 64), and nothing in the environment this repo builds is implicated: the
failure is pure floating-point arithmetic inside one kernel.

## 3. Why it must be an intermediate, not the answer

This is the step that turns "single precision, shrug" into "there is a bug here".

The single-precision ceiling is 3.4 × 10³⁸. The *physical* kinetic energy of this
configuration is nowhere near it — measured in the 64-bit control below, horizontal
kinetic energy is **3.03 × 10¹⁹ J** at timestep 1 and **2.05 × 10²³ J** at timestep 72.
Potential energy, at 2.4 × 10³², is the largest term in the block and it fits in single
precision comfortably.

So an expression whose *result* is ~10¹⁹ is overflowing a ceiling of ~10³⁸. The
overflow is therefore in the intermediates, which means the kernel is numerically
unsound for large planets rather than merely imprecise.

## 4. The mechanism

`vendor/lfric_apps/science/gungho/source/kernel/diagnostics/compute_energetics_kernel_mod.f90`,
lines 294–297:

```fortran
ke_uv_term = 0.5_r_def*dot_product(matmul(jac(:,:,qp1,qp2),uv_at_quad), &
                                   matmul(jac(:,:,qp1,qp2),uv_at_quad))/(dj(qp1,qp2)**2)
ke_w_term  = 0.5_r_def*dot_product(matmul(jac(:,:,qp1,qp2),w_at_quad),  &
                                   matmul(jac(:,:,qp1,qp2),w_at_quad))/(dj(qp1,qp2)**2)
```

It forms a **ratio of two very large numbers**: `uv_at_quad` is the W2 (flux-like)
wind, `jac` the coordinate Jacobian, `dj` its determinant. Everything is `r_def`.

Order of magnitude for this configuration — planet radius r = 9.44 × 10⁷ m, C48
(cell edge ~3 × 10⁶ m), 66 layers:

| quantity | rough size |
|---|---|
| `uv_at_quad` (W2 dof) | 10¹³–10¹⁶ |
| `matmul(jac, uv_at_quad)` ~ r · u_W2 | 10²¹–10²⁴ |
| `dot_product(...)` — **the numerator** | **10⁴²–10⁴⁸** |
| `dj**2` | comparably large |
| the quotient `ke_uv_term` | small, physical |

The numerator alone exceeds 3.4 × 10³⁸ and saturates to `+Infinity`; `Infinity /
finite` stays `Infinity`, and `sum_X` over the field propagates it to the total. In
64-bit the same intermediate is ~10⁴² against a ceiling of 1.8 × 10³⁰⁸, so the division
recovers the correct answer — which is exactly what the control shows.

## 5. Evidence in hand

One controlled pair, same suite, same source, same environment
(`lfric-env/v2026.07.21/cray`), differing only in build precision:

| | `RDEF_PRECISION=32` (as committed) | `RDEF_PRECISION=64` (control) |
|---|---|---|
| horizontal kinetic energy, S1 | `Infinity` | 3.03 × 10¹⁹ J |
| horizontal kinetic energy, S72 | `Infinity` | 2.05 × 10²³ J |
| total energy | `Infinity` | 2.48 × 10³² J |
| `Min/max u` (W2 dof) | ~10¹³ at S1 | ~10¹³ at S1 — **unchanged** |
| `u_in_w3` at S1 | ±1.5 m s⁻¹ | ±0.13 m s⁻¹ — **10× smaller** |
| run completes | yes | yes |

The control was produced with `cylc broadcast` rather than a config edit, so nothing in
the repo carries it — see §7.

## 6. What is NOT established — the work for a future session

In rough order of what a fix needs:

1. **Which factor overflows first.** §4 argues the numerator does, from magnitudes, but
   nobody has measured `dj` and `|J·uv|` for this configuration. `dj**2` may overflow
   too, independently. Instrument the kernel (print at one quadrature point on rank 0),
   or reproduce the arithmetic standalone from a dumped Jacobian.
2. **Where the tipping point is.** Earth radius is 15× smaller, so the numerator is
   ~200× smaller — likely just inside the ceiling, which would explain why this has
   never been noticed. Establish the radius (or the radius × resolution combination) at
   which single precision fails. That number is what makes the upstream case concrete,
   and it decides whether this is "hot Jupiters only" or a latent risk at high
   resolution on Earth too.
3. **Whether the same shape appears elsewhere.** `matmul(jac, ...)` with a `dj` divisor
   is a common LFRic idiom — `grep -rln "matmul(jac" vendor/lfric_apps/science/gungho/source/kernel/`
   returns eight further kernels, including `kinetic_energy_gradient_kernel_mod.F90`
   and `vorticity_advection_kernel_mod.F90`, which are **prognostic**, not diagnostic.
   If any of those overflow, the consequence is far more serious than a wrong log line.
   **This is the highest-value open question in this file.** Nothing observed so far
   suggests it is happening (the run is stable and conservative), but it has not been
   checked.
4. **The 10× first-step wind difference.** `u_in_w3` after one 50 s step from rest is
   ±1.5 m s⁻¹ at 32-bit and ±0.13 m s⁻¹ at 64-bit. Probably round-off in a field whose
   true value is near zero, and unrelated; but it is unexplained, and it was measured at
   different rank counts (108 vs 24), so it is not even a clean comparison yet. Redo it
   at equal rank count before drawing any conclusion.
5. **Whether upstream knows.** Not searched. Check the LFRic trac/GitHub issues for
   `compute_energetics` and for single-precision conservation diagnostics before
   writing anything up.

## 7. How to reproduce, and how to verify a fix

The reproduction is cheap: the overflow is visible at **timestep 1**, so a 72-step
cycle is enough. Roughly ten minutes once the environment is built, plus the compile.
String template variables must be quoted for `-S`, or cylc rejects them with
`Invalid template variable`.

```bash
# the failing arm — as committed
bash examples/science-suites/run-suite.sh u-dr932 \
     -S "EXPT_RESUB='PT1H'" -S "EXPT_RUNLEN='PT1H'" -S TOTAL_RANKS_REQ=24
```

For the 64-bit control, launch paused, override the build precision by broadcast, then
release — this keeps the repo's committed configuration untouched:

```bash
. examples/science-suites/site/activate-env.sh
bash patches/40-lfric_egp_bench-u-dr932-patch.sh          # stage the suite
cylc vip vendor/lfric_egp_bench/src/suites/u-dr932 --workflow-name u-dr932-r64 --pause \
  -S "REPO_ROOT='$PWD'" -S "LFRIC_STACK='cray'" \
  -S "LFRIC_PREFIX='<unversioned PREFIX>'" -S "LFRIC_ENV_VERSION='<./VERSION>'" \
  -S "ACTIVATE_ENV='$PWD/examples/science-suites/site/activate-env.sh'" \
  -S "EXPT_RESUB='PT1H'" -S "EXPT_RUNLEN='PT1H'" -S TOTAL_RANKS_REQ=24
cylc broadcast u-dr932-r64 -n build_lfric_atm \
  -s '[environment]RDEF_PRECISION=64' -s '[environment]R_TRAN_PRECISION=64' \
  -s '[environment]R_BL_PRECISION=64'  -s '[environment]R_PHYS_PRECISION=64'
cylc play u-dr932-r64
```

Read the result out of the model log, not `job.out`:

```bash
grep -E "Conservation: (total energy|horizontal kinetic energy)" \
  ~/cylc-run/<workflow>/run1/work/20000101T0000Z/lfric_atm/PET*.lfric_atm.Log | head
```

**A fix is verified when the 32-bit arm prints the same finite numbers as the 64-bit
arm**, to within single-precision round-off, and the 64-bit arm is unchanged from the
values in §5. Iterating on the kernel does not need a fresh workflow — edit the source
under `share/source/`, then `cylc trigger <wf>//20000101T0000Z/build_lfric_atm` and let
`lfric_atm` follow.

## 8. Candidate fixes, untested

Both are hypotheses. Neither has been tried.

- **Divide before squaring.** `|J·uv|²/dj²` is `|J·uv/dj|²`. Forming `J·uv/dj` first —
  a physical velocity, O(10³) — and then taking `dot_product` of that with itself keeps
  every intermediate small and needs no precision change. Two lines, and it would fix
  the kernel at any radius rather than buying headroom. This looks like the right fix.
- **Accumulate the diagnostics in `r_second`.** Narrower, and it leaves the same
  fragility in place for whoever raises the radius or the resolution again.

Prefer the first unless measurement says otherwise; if it works, it is a small, clearly
motivated upstream pull request, and this suite is the regression test for it.

## 9. Provenance

- Observed 2026-08-10 on Isambard 3, `lfric-env/v2026.07.21/cray`,
  LFRic `2026.07.1` (apps vn3.2), gfortran 14.3 behind `ftn`.
- Suite: `dennissergeev/lfric_egp_bench@e6ee57a` `src/suites/u-dr932`, as staged by
  `patches/40-lfric_egp_bench-u-dr932-patch.sh`; `CASE_SETUP=''` (deep hot Jupiter),
  `LFRIC_RES=C48_MG`, `LFRIC_LEVS=''` (l66/4000 km), `STRETCH_FACTOR=0.5`,
  `TARGET_LONLAT=-90,0`, `EXPT_DT=50`.
- Kernel: `science/gungho/source/kernel/diagnostics/compute_energetics_kernel_mod.f90`
  lines 294–297; totals summed in
  `science/gungho/source/algorithm/diagnostics/conservation_algorithm_mod.x90`
  (`real(kind=r_def) :: total_kinetic_uv`, line 91).
