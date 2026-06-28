# T3 feature validation — should the re-estimating features be trusted?

The MARTIN feature layer (`packages/martin/R/model_features.R`) has four **T3**
features that change an *estimated* behavioural equation. Unlike the T0/T1
diagnostic layer (which is baseline-neutral and enabled in the live round —
`docs/martin_enhancements_plan.md`, `_targets.R:model_features`), a T3 feature
moves the forecast, so it must be validated before being switched on. **All four
are OFF by default.**

This note records a first-pass validation and the verdict. Reproduce with:

```sh
Rscript scripts/validate_t3.R
```

## What was tested

Three of the four re-fit a single behavioural; the harness compares the
re-specified equation against the published baseline equation on the same
sample:

| Feature | Equation | Change |
|---|---|---|
| `convex_ptm` | `PTM` | gap term `c7*LURGAP` → `c7*(LURGAP/LUR)` (reciprocal convexity) |
| `inverted_le` | `LE` | error-correction target → inverted production-function `LESTAR` |
| `corporate_accelerator` | `NBRSP` | adds `c4*TSLAG(LEV,1)` (a BGG leverage channel) |

Metrics: in-sample R²/SSR/AIC vs baseline; the added coefficient's significance
where one exists; and a time-ordered **70/30 pseudo-OOS split** (OLS on bimets'
own restricted design matrices, fit on the first 70% of observations, RMSE
scored on the held-out last 30%).

The fourth, `endogenous_household`, **replaces** the `NHOY` ECM with an
accounting identity rebuilt from its components. It is not a re-fit, so it has no
fit to score; it is baseline-neutral by construction (`NHOY_RESID` plugs the gap)
and is validated by the round's `NHOY`/`RC` diff.

## Results (fixture sample)

| Feature | R² base → feature | AIC improves? | OOS RMSE base → feature | OOS improves? | Added-term p |
|---|---|---|---|---|---|
| `convex_ptm` | 0.489 → 0.476 | no | 0.00191 → 0.00159 | **yes** | — |
| `inverted_le` | 0.564 → 0.570 | **yes** | 0.00330 → 0.00265 | **yes** | — |
| `corporate_accelerator` | 0.925 → **−10.4** | no | 0.193 → NA (singular) | — | **1.0** |

## ⚠️ The decisive caveat: this holdout is PRE-COVID

The bundled fixture ends **2019Q3**. The 70/30 split therefore trains on roughly
1993–2012 and tests on roughly 2013–2019 — entirely **before** the COVID /
inflation break. That is exactly the regime in which these re-specifications are
*least* likely to matter (`convex_ptm`'s whole point is a hot, low-slack economy;
the post-2021 episode is the test that counts). **A favourable pre-COVID result
is necessary but not sufficient; a decision to enable any T3 feature needs a live
re-estimation run with `estimation_end` past 2019Q3.** `scripts/validate_t3.R`
runs unchanged on that database — only the data changes.

## Verdict

- **`inverted_le` — promising; keep off pending a post-COVID run.** Improves both
  in-sample fit (R² 0.564 → 0.570, AIC down) and pre-COVID OOS RMSE (0.0033 →
  0.0027). The capital-aware employment target generalises better here. Best T3
  candidate to enable, *after* the live post-COVID check.

- **`convex_ptm` — promising but under-tested here; keep off.** Slightly worse
  in-sample (the linear form is the in-sample MLE by construction) but better
  pre-COVID OOS RMSE (0.0019 → 0.0016). The pre-COVID holdout is the *wrong*
  regime to judge a convexity that exists to bite in a hot economy — this needs
  the post-COVID OOS specifically before any conclusion.

- **`corporate_accelerator` — cannot be validated on the fixture; keep off.** The
  leverage term `c4` is statistically dead (t ≈ 0, **p = 1.0**) and the re-fit is
  degenerate (R² collapses, the OOS solve is singular). This is expected: on the
  fixture `LEV` is a **calibrated proxy** (real ABS `DCORP`, 5232.0 A3427913W, is
  absent), so the BGG channel has no signal to identify. It needs the live
  corporate-debt series before the accelerator can be assessed at all.

- **`endogenous_household` — baseline-neutral identity swap, not a fit.** No OOS
  score applies; it re-baselines `RC` by construction and is validated via the
  round's `NHOY`/`RC` diff.

## Bottom line

The default round keeps all four T3 features off — the validation supports that.
`inverted_le` and `convex_ptm` are the two worth a dedicated **live, post-COVID**
out-of-sample study (re-run this harness with `estimation_end` past 2019Q3 on a
live database); `corporate_accelerator` first needs the real ABS `DCORP` series;
`endogenous_household` is a structural choice to make deliberately, not a fit to
win.
