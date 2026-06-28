# CLAUDE.md — context for sessions

This file is loaded automatically by Claude Code. Keep it current as the
project evolves.

## What this is

A pure-R implementation of the RBA's **MARTIN** macroeconometric model, built on
the `bimets` simultaneous-equation engine. It does the full workflow: download
data, build the model database, estimate the equations, simulate impulse
responses, and forecast (unconditional, conditional, stochastic). There is **no
LLM layer, no `targets`, no `renv`, and no R package to install** — it is a flat
set of R scripts you `source()`.

(History: this repo was previously "SIBYL", an LLM wrapper around MARTIN across
four R packages. It was stripped down to the pure model. If you find lingering
"SIBYL"/"judgement"/"sibyldata" references in comments or `docs/`, they are
stale — clean them up when you touch the file.)

## How it loads

`source("setup.R")` from the repo root:
1. records the repo root via `here::here()` (the `.here` marker / `.git`) as
   `options(martin.root=)`;
2. attaches runtime dependencies (notably `bimets`, whose verbs are called
   un-namespaced; everything else is called with explicit `pkg::` prefixes);
3. sources every file in `R/` into the global environment.

Bundled data files live in `extdata/` and are resolved with `extdata_path()`
(in `R/paths.R`) — there is no `system.file()` because there is no package.

## Layout

| Path | Role |
|---|---|
| `setup.R` | the loader — source this first |
| `R/fetch_*.R`, `cache.R`, `catalogue.R`, `update_data.R` | download data (ABS/RBA/FRED/OECD/World Bank/BoM); `to_martin_database()` builds the bimets database |
| `R/transformations.R`, `identities.R`, `derived.R`, `dummies.R`, `state_space.R`, `tpw.R`, `production.R`, `extend_exogenous.R`, `merge.R` | manipulate / create data (splicing, Chow-Lin, PIM, KFAS trends, dummies) |
| `R/nowcast.R`, `handover.R`, `conversion.R` | ragged-edge handover (Q+0/Q+1) via `fable` |
| `R/load_martin.R`, `model_features.R`, `equation_catalogue.R` | estimate + build the model in bimets |
| `R/solve_martin.R` | forecast: `solve_martin()` (unconditional + conditional via add-factors / exogenise) and `solve_martin_stochastic()` |
| `R/sensitivity_matrix.R` | IRFs / multipliers |
| `R/adjustment.R`, `quarter.R` | the add-factor S3 class + horizon expansion |
| `extdata/model_af/` | the default behavioural (AF) model, split into one file per economic block (consumption, prices, exports, imports, identities, ...); assembled at load by `read_model_lines("af")`. `extdata/MARTINMOD.txt`/`MARTINMOD_EST.txt` are the other single-file variants. |
| `extdata/` | `equation_catalogue.csv`, `series_catalogue.csv`, dummy specs, the CMO commodity xlsx, frozen `martin_data_fixture.xlsx` |
| `scripts/01..06` | runnable drivers, one per capability |
| `tests/` | `testthat` suite + `tests/run_tests.R` |

## Key facts to preserve

1. **Frozen vs re-estimated coefficients.** `load_martin()`/`solve_martin()`
   default to **frozen** (`estimation_end = NULL`): `bimets::ESTIMATE` re-fits
   the free coefficients but on the model file's embedded 2019Q3 `TSRANGE`,
   reproducing the published values. Re-estimating over a later sample
   (`coefficients = "reestimated"` + `estimation_end`) crosses the COVID break
   and changes the coefficients — an explicit opt-in, never the default.
2. **The baseline replays history.** With no add-factors, `solve_martin()`
   reproduces history to within solver tolerance by seeding each equation's
   `ConstantAdjustment` from its estimated residuals, decayed forward past the
   data end via the EViews `_a = _a(-1) * -0.5` rule. The regression test
   (`tests/testthat/test-regression-against-bimets.R`) pins this against the
   canonical bimets solve.
3. **Add-factors are first-class.** `adjustment()` carries
   `{equation, horizon, value, tail, rationale, ...}`. `tail` (`decay_50` /
   `zero` / `carry`) is a *model-mechanics* choice — it governs how a shock
   persists past its explicit horizon so a sustained level target on a
   growth-rate equation converges instead of diverging. Magnitudes are
   guard-railed in `validate_adjustment_bounds()`.
4. **Model features are opt-in, load-time transforms** (`apply_model_features()`
   + `seed_feature_data()`), baseline-neutral by construction: with no features
   the baseline is bit-identical to the bimets reference.

## Conventions

- snake_case for code; UPPERCASE for MARTIN variable names (bimets is
  case-sensitive — follow the blocks in `extdata/model_af/`).
- Explicit namespacing in source (`dplyr::filter()`), except the `bimets` verbs
  which are used un-namespaced (and `bimets` is attached by `setup.R`).
- No emojis in code, files, or commits.
- API keys via `.Renviron` (never in source); only needed for live download.
- Binary EViews `.wf1` files and the `data/cache/` parquet cache are gitignored.

## Commands

```sh
Rscript tests/run_tests.R              # full test suite
Rscript scripts/03_forecast_unconditional.R   # (and 01..06 per capability)
```

In a session: `source("setup.R")` then call `solve_martin()`, `load_martin()`,
`sensitivity_matrix()`, `solve_martin_stochastic()`, `update_data()`, etc.
