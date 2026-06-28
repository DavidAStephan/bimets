# Re-specification proposals: XS (services exports) and GC (government consumption)

These two equations surfaced in the model audit as the weakest *core* behavioural
relationships — in both, the error-correction mechanism (the economic heart of the
equation) is statistically insignificant. This note diagnoses why and proposes
drop-in re-specifications, each tested by re-estimating through the same bimets
pipeline (`ESTIMATE`, restrictions intact, frozen 2019Q3 sample, bundled fixture).

**These are proposals, not applied changes.** `extdata/MARTINMOD_AF.txt` is left
untouched so the baseline stays bit-identical to the bimets reference. To adopt one,
replace the block in that file and re-run `scripts/equation_diagnostics.R` and the
regression test.

---

## XS — services exports

### Current
```
EQ> TSDELTALOG(XS,1)=c1+c2*(LOG(TSLAG(XS,1))-LOG(TSLAG(WY,1)))
                      +c3*LOG(TSLAG(REWI,1))
                      +c4*D_OLYX
                      +c5*(LOG(WY)-LOG(TSLAG(WY,4)))/4
                      +c6*TSDELTALOG(REWI)
                      +c7*(TSLAG(TDLLPOP,1) + TSLAG(TDLLPOP,1) + TSLAG(TDLLA,1))
                      +c8*XS_TREND
COEFF> c1 c2 c3 c4 c5 c6 c7 c8
RESTRICT>c6+c7=1
```

### Three problems
1. **Trend term is malformed (likely an upstream typo).** `c7*(TDLLPOP(-1) + TDLLPOP(-1) + TDLLA(-1))` **double-counts `TDLLPOP` and omits `TDLLHPP`**. Every other potential-output trend in the model (e.g. `GC`, `IBN`, `IBRE`) uses the three distinct components `TDLLA + TDLLHPP + TDLLPOP` (trend productivity + hours-per-person + population). This is almost certainly meant to be the same.
2. **A level inside a growth equation.** `c3*LOG(REWI(-1))` puts the *level* of the real export-weighted index into a `TSDELTALOG` (growth) equation; it is insignificant (t = −0.08).
3. **Redundant trend.** `c8*XS_TREND` is collinear with the `c7` trend term and insignificant (t = −0.10).

The net effect: 4 of 8 coefficients are insignificant, and the error-correction term `c2` (services exports reverting to world income) is swamped — t = −0.37.

### Proposed
```
EQ> TSDELTALOG(XS,1)=c1+c2*(LOG(TSLAG(XS,1))-LOG(TSLAG(WY,1)))
                      +c3*D_OLYX
                      +c4*(LOG(WY)-LOG(TSLAG(WY,4)))/4
                      +c5*TSDELTALOG(REWI)
                      +c6*(TSLAG(TDLLA,1)+TSLAG(TDLLHPP,1)+TSLAG(TDLLPOP,1))
COEFF> c1 c2 c3 c4 c5 c6
RESTRICT>c5+c6=1
```
Fix the trend, drop the two dead terms (`REWI` level, `XS_TREND`), keep the long-run
homogeneity restriction (`c5+c6=1`).

| | coef | R² | adjR² | DW | AIC | insig | EC-term t |
|---|--:|--:|--:|--:|--:|--:|--:|
| current | 8 | 0.451 | 0.423 | 2.40 | −553.1 | 4 | −0.37 |
| **proposed** | **6** | 0.450 | 0.432 | 2.39 | **−556.9** | **2** | **−1.34** |

Same fit with two fewer parameters (lower AIC, higher adj-R²), the trend bug removed,
and the error-correction term roughly four times better determined. The EC term is
still short of the 5% bar — services exports (tourism, education) have genuinely
out-grown world GDP, so the `XS/WY` ratio trends and pure one-for-one reversion is
weak. A further step would let the long-run elasticity on `WY` be free, or add a
deterministic trend to the cointegrating target; the change above is the conservative,
bug-fixing version.

---

## GC — government consumption

### Current
```
EQ> TSDELTALOG(GC,1) = c1+c2*(LOG(TSLAG(GC,1))-LOG(TSLAG(Y,1)/(1-2*TSLAG(LURGAP,1)/100)))
                      +c3*TSLAG(TSDELTALOG(GC,1),1) + c4*(TDLLA + TDLLHPP + TDLLPOP)
COEFF> c1 c2 c3 c4
RESTRICT> c3+c4=1
```

### Problem
The error-correction target is output scaled by an **ad-hoc cyclical adjustment**,
`Y/(1 − 2·LURGAP/100)` — government consumption is assumed to rise relative to output
when there is labour-market slack. The mechanism is insignificant (EC term t = −1.54)
and the whole equation explains almost nothing (R² = 0.07). The `(1 − 2·LURGAP/100)`
factor is a non-standard functional form doing no measurable work.

### Proposed
```
EQ> TSDELTALOG(GC,1) = c1+c2*(LOG(TSLAG(GC,1))-LOG(TSLAG(Y,1)))
                      +c3*TSLAG(TSDELTALOG(GC,1),1) + c4*(TDLLA + TDLLHPP + TDLLPOP)
COEFF> c1 c2 c3 c4
RESTRICT> c3+c4=1
```
Replace the cyclically-adjusted target with a plain error-correction to output.

| | R² | adjR² | DW | AIC | insig | EC-term t |
|---|--:|--:|--:|--:|--:|--:|
| current (cyclical-adj) | 0.074 | 0.060 | 2.09 | −799.3 | 2 | −1.54 |
| **proposed (plain EC)** | **0.084** | — | 2.11 | **−800.8** | **1** | **−1.96** |

Simpler, slightly better fit, and the error-correction term reaches significance
(t = −1.96). The ad-hoc cyclical adjustment was hurting, not helping.

Caveat: even re-specified, GC explains little (R² ≈ 0.08). Real government consumption
is largely a discretionary policy series; in a forecast round its add-factor is the
right lever, and no behavioural form will fit it tightly. The re-spec makes the
equation cleaner and its long-run anchor significant, not predictive.

---

## How to adopt

1. Replace the `XS` and/or `GC` block in `extdata/MARTINMOD_AF.txt`.
2. `Rscript scripts/equation_diagnostics.R` to refresh `docs/equation_diagnostics.md`.
3. `Rscript tests/run_tests.R` — note the regression-against-bimets test pins the
   *current* coefficients, so adopting a re-spec will require updating that test's
   expected values (it is comparing to the unchanged upstream model).
