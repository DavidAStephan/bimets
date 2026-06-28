# MARTIN in R

A pure-R implementation of the RBA's **MARTIN** macroeconometric model of the
Australian economy, built on the [`bimets`](https://cran.r-project.org/package=bimets)
simultaneous-equation engine. It covers the full workflow:

- **download** public data (ABS, RBA, FRED, OECD, World Bank, BoM);
- **build** the model database (splicing, Chow-Lin disaggregation, PIM
  accumulation, identity chains, state-space trends, deterministic dummies);
- **estimate** the behavioural equations in bimets;
- **simulate** impulse responses (IRFs / multipliers);
- **forecast** unconditionally;
- run **conditional** forecasts (add-factors / "tunes" and variable exogenisation);
- run **stochastic** simulations (uncertainty bands).

There is no package to install and no build system — it is a flat set of R
scripts you `source()`. It is deliberately dependency-light so it runs in a
plain R environment.

## Layout

```
R-MARTIN/
├── setup.R              # source this: loads deps + all of R/ into the session
├── R/                   # the model, one concern per file
│   ├── fetch_*.R, cache.R, catalogue.R, update_data.R   # download data
│   ├── transformations.R, identities.R, derived.R,
│   │   dummies.R, state_space.R, tpw.R, production.R,
│   │   extend_exogenous.R, merge.R                       # build / modify data
│   ├── nowcast.R, handover.R, conversion.R              # ragged-edge handover
│   ├── load_martin.R, model_features.R,
│   │   equation_catalogue.R                              # estimate + build in bimets
│   ├── solve_martin.R                                    # forecast (uncond / cond / stochastic)
│   ├── sensitivity_matrix.R                              # IRFs / multipliers
│   ├── adjustment.R, quarter.R                           # add-factors
│   └── read_fixture.R, paths.R, utils.R                  # plumbing
├── extdata/             # bundled model files + catalogues + frozen data fixture
├── scripts/             # runnable drivers, one per capability (01..06)
├── tests/               # testthat suite + tests/run_tests.R
└── data/                # local parquet cache + saved projections (gitignored)
```

## Setup

R ≥ 4.3 and these packages (all CRAN):

```r
install.packages(c(
  "bimets", "dplyr", "tidyr", "tibble", "purrr", "rlang", "stringr",
  "lubridate", "readr", "glue", "readxl", "xts", "zoo", "here",
  "KFAS", "tempdisagg",                         # state-space trends, Chow-Lin
  "fable", "fabletools", "feasts", "tsibble"    # nowcast bridge models
))
# Optional, only for live data download:
install.packages(c("arrow", "readabs", "readrba", "fredr", "OECD", "fs"))
```

Then, from the repo root:

```r
source("setup.R")        # loads everything into the session
```

Live data download additionally needs a FRED API key in `.Renviron` (see
[.Renviron.example](.Renviron.example)). The model runs against the bundled
fixture with no keys.

## Use

Each capability has a runnable driver in `scripts/`:

```sh
Rscript scripts/01_update_data.R           # download + build the database (fixture fallback)
Rscript scripts/02_estimate.R              # load + estimate the model in bimets
Rscript scripts/03_forecast_unconditional.R# baseline projection
Rscript scripts/04_forecast_conditional.R  # add-factors + exogenisation
Rscript scripts/05_irf.R                   # impulse responses
Rscript scripts/06_stochastic.R            # uncertainty bands
Rscript scripts/07_beveridge_curve.R       # ABS job vacancies -> vacancy rate -> Beveridge curve
```

Or interactively:

```r
source("setup.R")
db   <- read_fixture()                                  # bundled history to 2019Q3
base <- solve_martin(db, horizon = c("2010Q1", "2018Q4"))   # unconditional

# conditional: a +50bp cash-rate add-factor over 2014
af <- adjustment_list(
  adjustment("NCR", horizon = c("2014Q1","2014Q2","2014Q3","2014Q4"),
             value = rep(0.5, 4), rationale = "scenario: +50bp", tail = "zero")
)
tight <- solve_martin(db, adjustments = af, horizon = c("2010Q1","2018Q4"))

# impulse responses; uncertainty bands
irf   <- sensitivity_matrix(db, baseline = base, horizon = c("2010Q1","2018Q4"))
bands <- solve_martin_stochastic(db, horizon = c("2010Q1","2018Q4"), n_draws = 200)
```

## Coefficients: frozen vs re-estimated

The behavioural (AF) model defines 95 `BEHAVIORAL>` equations, split for
readability into one file per economic block under `extdata/model_af/`
(consumption, prices, exports, imports, identities, ...) and assembled at load.
`bimets::ESTIMATE` re-fits their free coefficients on **every** load; "frozen"
(the default) just means it estimates over the model's embedded **2019Q3**
sample, reproducing the published coefficients. To re-fit over a later sample (which crosses the COVID
break and materially changes the coefficients), opt in explicitly:

```r
solve_martin(db, horizon = h, coefficients = "reestimated", estimation_end = "2024Q4")
```

## Tests

```sh
Rscript tests/run_tests.R
```

Runs the full `testthat` suite (720 assertions), including a regression test
that asserts the no-adjustment solve matches the canonical `bimets` reference
to within solver tolerance. Network-dependent data-fetch tests skip when offline.

## Provenance

The `bimets` model definitions in `extdata/` (the per-block `model_af/` files and
the single-file `MARTINMOD.txt`/`MARTINMOD_EST.txt` variants) and the frozen
`martin_data_fixture.xlsx` are vendored, with attribution, from the upstream
MARTIN ports:

- the EViews/R implementation (the canonical equations and data-flow recipes),
- the [`bimets`](https://cran.r-project.org/package=bimets) MARTIN port that the
  solver is built on.

MARTIN itself is documented in RBA Research Discussion Paper 2019-07.
