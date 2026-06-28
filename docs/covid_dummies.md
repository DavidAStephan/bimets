# COVID dummy variables for re-estimation

Re-estimating MARTIN to the latest quarter (2026Q1) across the COVID break
degrades the behavioural equations (see the audit and `docs/equation_diagnostics.md`).
The 2020–21 lockdown quarters are extreme one-off outliers that distort OLS. This
note plans a set of **pulse dummy variables** (=1 in one quarter, 0 elsewhere) to
absorb them, and reports what re-estimating with them does.

Reproduce with `scripts/reestimate_covid.R`. `extdata/MARTINMOD_AF.txt` is **not**
modified — the frozen default stays bit-identical to the bimets reference; the
dummies are injected at runtime only when re-estimating past 2019.

## Which quarters — the evidence

Standardised residuals (`residual / regression-SE`) from the 2026Q1-estimated
model, counted across the genuinely-estimated equations, |z| ≥ 2.5:

| Quarter | # equations blown out | Nature |
|---|--:|---|
| **2020Q2** | **17** | Great Lockdown collapse (`RC` z = −9.3) |
| 2020Q3 | 7 | rebound / Vic 2nd wave |
| 2021Q3 | 5 | Delta lockdowns |
| 2022Q1 | 7 | *inflation surge* (not lockdown) |
| 2022Q2 | 6 | *inflation surge* (not lockdown) |
| 2020Q1, 2021Q1/Q2/Q4 | 1–2 each | edges of the lockdown cycle |

## The plan

- **Candidate lockdown quarters:** `2020Q1, 2020Q2, 2020Q3, 2020Q4, 2021Q3, 2021Q4`.
- **Targeted, not blanket:** a dummy is added to an equation only where *that*
  equation has |z| ≥ 2.5 in that quarter. Equations with no lockdown outlier get
  none. (A blanket set made several equations singular — e.g. `M` — and adds
  parameters that don't earn their keep.)
- **The 2022 inflation quarters are deliberately excluded.** The 2022–23 inflation
  surge was a genuine economic development, not a measurement outlier; the model
  should fit it, not dummy it away.
- Singular-equation guard: if an equation still can't invert with a dummy, the
  script drops that equation's dummies and continues.

Result: dummies land on **19 equations**, using `2020Q1, 2020Q2, 2020Q3, 2021Q3,
2021Q4` (2020Q4 turned out not to be a |z|≥2.5 outlier anywhere).

## What it does — re-estimated to 2026Q1, no dummies vs with dummies

| Equation | role | no dummies | with dummies | R² | dummies |
|---|---|---|---|---|---|
| `RC` consumption | EC term | −0.136 [t −3.9] | **−0.151 [t −9.2]** | **0.21 → 0.87** | 20Q2/20Q3/21Q3 |
| `LE` employment | dynamics | 0.197 [t 3.1] | **0.429 [t 7.8]** | 0.61 → 0.77 | 20Q2/20Q3 |
| `M` imports | EC term | −0.080 [t −2.0] | **−0.112 [t −3.0]** | 0.17 → 0.33 | 20Q2 |
| `XS` services exp. | EC term | −0.042 [t −1.5] | −0.045 [t −1.9] | 0.29 → 0.56 | 20Q1/20Q2/21Q3 |
| `XM` mfg exports | EC term | −0.155 [t −3.7] | −0.148 [t −3.7] | 0.18 → 0.26 | 20Q2 |
| `LUR` Okun | output gap | −21.2 [t −11.1] | −20.5 [t −10.5] | 0.47 → 0.54 | 20Q2/20Q3 |
| `PTM` inflation | u-gap | −0.00017 [t −1.2] | −0.00016 [t −1.1] | 0.56 → 0.58 | 20Q2 |
| `PW` wages | u-gap | −0.0014 [t −1.8] | −0.0014 [t −1.8] | 0.98 → 0.98 | (none) |
| `GC` govt cons. | EC term | +0.024 [t +1.7] | +0.024 [t +1.7] | 0.02 → 0.02 | (none) |

## Conclusion

The lockdown dummies do exactly what pulse dummies should:

- **They fix the activity/quantity equations.** `RC` is the headline — absorbing
  the 2020Q2 collapse lifts its R² from 0.21 to 0.87 and sharpens the
  error-correction term (t −3.9 → −9.2). Employment, imports, and exports
  similarly recover.
- **They do *not* fix the supply-side price equations — correctly.** `PTM` and
  `PW` barely move, and `GC`'s error-correction stays the wrong (post-COVID)
  sign. Their degradation comes from the **2022–23 inflation surge and the fiscal
  regime shift** — sustained level changes, not one-quarter outliers — which
  pulse dummies cannot and should not absorb.

**Takeaway:** pulse dummies make a naive 2026Q1 re-estimation usable for the
*demand side*, but the Phillips/wage-curve flattening and the fiscal break are
structural and need a different treatment (e.g. a level/regime shift, an
inflation-expectations re-anchoring, or simply retaining the frozen supply-side
coefficients). The model's frozen default remains the right baseline; these
dummies are a tool for a considered re-estimation, not an automatic fix.
