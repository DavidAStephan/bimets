# Scope: V/U (tightness) dynamics and a floor in the unemployment equation

Two requested extensions to the `LUR` (Okun) equation:
1. add labour-market tightness (V/U) or other dynamics;
2. a mechanism to stop the unemployment rate going negative / too low.

Both are designed as **opt-in model features** (like `elb_floor`, `convex_ptm`):
baseline-neutral when off, so `extdata/model_af/` and the frozen default stay
bit-identical to the bimets reference. The job-vacancy series `JV`/`VR` added
earlier supply the data.

## Current equation

`extdata/model_af/04_labour.txt`:
```
EQ> TSDELTA(LUR,1) = c1*( LOKLAG*TSDELTA(TSLAG(LUR,1)) - LUR_DUM*0.025*(TSLAG(LUR,2)-TSLAG(TLUR,1)) )  [c1=1: persistence + NAIRU reversion]
                   + c2*( (LOG(Y)-LOG(TSLAG(Y,2)))/2 - TY )                                            [Okun: output gap]
                   + c3*( (LOG(TSLAG(RULC,2))-LOG(TSLAG(RULC,4)))/2 )                                  [real unit labour costs]
RESTRICT> c1=1
```
The output-gap term `c2` is the workhorse (frozen: −24.2, t=−8.8) and there is
already a NAIRU-reversion term (pulls LUR back toward `TLUR`).

## 1. Tightness (V/U)

`VR/LUR` is exactly the vacancy-to-unemployment ratio (both are rates over the
labour force, so `LF` cancels: `VR/LUR = JV/U`). Re-estimating `LUR` over
1979Q4–2019Q3 (vacancies start 1979; the GFC survey gap 2008Q3–2009Q3 is
log-linearly interpolated so the regressor has no interior NA):

| spec | V/U term | coef | t | sign | R² |
|---|---|--:|--:|---|--:|
| A | Okun + **level** `log(V/U)₋₁` | +0.018 | **+2.10** | wrong (+) | 0.541 |
| B | Okun + **flow** `Δlog(V/U)₋₁` | −0.29 | −1.64 | right (−) | 0.536 |
| C | **level**, replacing output gap | −0.006 | −0.56 | right, weak | 0.292 |
| D | **flow**, replacing output gap | −0.85 | **−4.66** | right (−) | 0.376 |

**Reading.** Tightness drives unemployment the right way (a rising V/U lowers
unemployment) **only as a flow** — strongly so when it stands in for the output
gap (D, t=−4.66). But the output gap is collinear with tightness and explains
more (R² 0.52 vs 0.38), so *alongside* the output gap the flow term is correctly
signed but weak (B, t=−1.64), and the *level* even flips to the wrong sign (A) —
the output gap has already done the cyclical work and the residual V/U level
picks up mean-reversion.

**Options.**
- **(i) Add the flow to the existing Okun equation** (`vu_okun`): keeps the
  robust output gap, adds `+c4·Δlog(V/U)₋₁`. Correctly signed, modest. Honest
  about the collinearity.
- **(ii) Tightness as the cyclical driver** (matching form): replace the output
  gap with `Δlog(V/U)` (spec D). Theoretically cleaner (a search/matching
  channel) and strongly significant, but fits less well than Okun and is a
  bigger departure.
- **(iii) Don't add it.** V/U does not beat the output gap; keep it as the
  Beveridge-curve report only.

Data caveat for (i)/(ii): using `VR` shortens the estimation sample to 1979Q4+
and needs the GFC gap filled — so a `vu_okun` feature implies re-estimation
(`estimation_end`), not the frozen default.

## 2. Floor on the unemployment rate

The model solves `ΔLUR`; nothing stops a strong-demand forecast driving `LUR`
below any frictional minimum, or negative. The repo already floors the cash rate
this way (`elb_floor`), and the same mechanism applies:

```
rename  BEHAVIORAL> LUR   ->   BEHAVIORAL> LUR_RULE      (keeps estimating + add-factor handover)
add     IDENTITY> LUR = LUR_RULE                IF> LUR_RULE >  floor
        IDENTITY> LUR = floor                   IF> LUR_RULE <= floor
```
The rule's lag terms keep referencing the *floored* `LUR`, so the dynamics react
to the actual rate (as `elb_floor` does for `NCR`). **Baseline-neutral:** in
sample `LUR_RULE` is always above the floor, so `LUR == LUR_RULE` and the solve
is unchanged; the floor only bites in a forecast that pushes unemployment to the
bound. `elb_floor` already validates this `IF>`-branch mechanism in this model.

**Options.**
- **(a) Hard floor** (`lur_floor`, recommended): the `max(LUR_RULE, floor)`
  identity above. Floor level is a parameter — default **2.5%** (below Australia's
  record low of ~3.4% in 2022, so it never distorts plausible ranges but blocks
  the absurd). Set lower (e.g. 0.5%) if you only want to stop *negative* values.
- **(b) Soft floor**: instead of a hard cap, add a convex restoring term to
  `ΔLUR` that grows as `LUR` approaches the floor (e.g. `+c5·(floor/LUR_₁ − 1)`),
  so the level asymptotes smoothly. No kink (nicer for the solver / IRFs), but it
  changes the in-sample equation, so it needs re-estimation and isn't
  baseline-neutral.

## Recommendation

- **Floor:** implement **(a) the hard floor** as `lur_floor` — clean, proven
  pattern, baseline-neutral, default 2.5%. This is the clearly-valuable, low-risk
  piece.
- **V/U:** implement **(i) the flow term** as an opt-in `vu_okun` feature, used
  with `estimation_end` (re-estimation), and keep the matching form (ii)
  available as a variant. Be explicit that V/U is a modest add to the output gap;
  it is not a free lunch over the existing Okun term.

Both are opt-in; with neither feature on, the model is unchanged.

## Decision & implementation

- **V/U: not added to the equation** (kept as the Beveridge-curve report only).
  The evidence above stands if it's revisited: tightness works the right way only
  as a flow, and it doesn't beat the output-gap Okun term.
- **Floor: implemented as the `lur_floor` feature** — hard floor, default
  **2.5%**, via the `elb_floor` construction (rename `LUR` → `LUR_RULE`, floored
  `LUR` identity through `IF>` branches). Override with
  `feature_params = list(lur_floor_value = ...)`. `solve_martin()` re-routes `LUR`
  add-factors to `LUR_RULE` automatically.

  Verified: estimates identically to baseline (coef diff 0), **baseline-neutral
  in sample (max |diff| = 0)**, and under a stress add-factor that drives
  unemployment to ~0.5% the floored solve holds `LUR` at exactly 2.5%. Tests in
  `tests/testthat/test-lur-floor.R`.

  Usage:
  ```r
  solve_martin(db, horizon = h, features = "lur_floor")                       # default 2.5%
  solve_martin(db, horizon = h, features = "lur_floor",
               feature_params = list(lur_floor_value = 3.0))                  # custom floor
  ```
