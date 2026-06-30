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
│   ├── csv_data.R                                        # OR load data from a CSV
│   ├── transformations.R, identities.R, derived.R,
│   │   dummies.R, state_space.R, tpw.R, production.R,
│   │   extend_exogenous.R, merge.R                       # build / modify data
│   ├── nowcast.R, handover.R, conversion.R              # ragged-edge handover
│   ├── load_martin.R, model_features.R,
│   │   equation_catalogue.R                              # estimate + build in bimets
│   ├── solve_martin.R                                    # forecast (uncond / cond / stochastic)
│   ├── sensitivity_matrix.R, irf_scenarios.R            # IRFs: generic + standard battery
│   ├── adjustment.R, quarter.R                           # add-factors
│   └── read_fixture.R, paths.R, utils.R                  # plumbing
├── extdata/             # bundled model files + catalogues + frozen data fixture
│   └── model_af/        # AF model: one file per equation, grouped by block
├── scripts/             # runnable drivers, one per capability (01..09)
├── results/irfs/        # committed standard-IRF output CSVs
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
Rscript scripts/08_standard_irfs.R         # standard IRF battery -> results/irfs/*.csv
Rscript scripts/09_forecast_from_csv.R     # forecast from a CSV instead of downloading
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

## Run it with your own data (CSV)

No downloads and no API keys: put your data in a CSV (one **period** column plus
one column **per MARTIN variable**, header = the variable name) and load it
straight into the model.

```r
source("setup.R")
db   <- read_csv_database("my_data.csv")                    # CSV -> model database
base <- solve_martin(db, horizon = c("2010Q1", "2024Q4"))   # forecast
```

To get the exact column format, export the bundled fixture as a template and
edit it (`database_to_csv(read_fixture(), "template.csv")`); to run with a
partial / recent-only CSV, fill the gaps from the bundled data
(`read_csv_database("my_data.csv", fallback = read_fixture())`).

**Full step-by-step walkthrough: [docs/running_from_csv.md](docs/running_from_csv.md)**
(includes forecasting past your data end, scenarios, and IRFs). The runnable
demo is `Rscript scripts/09_forecast_from_csv.R`.

## Build the database from public data

The other way to get data in: pull current vintages from the agencies and build
the database (instead of the frozen fixture or a CSV).

```r
source("setup.R")
panel <- update_data(vintage = Sys.Date())          # ABS / RBA / FRED / OECD / World Bank / BoM
db    <- to_martin_database(panel)                   # pivot to MARTIN variables + build
db    <- merge_with_fallback(db, read_fixture())     # backfill deep history from the fixture
```

Each source has a fetcher in `R/fetch_*.R`, wired to `readabs` / `readrba` /
`fredr` / the OECD SDMX API / the bundled Pink Sheet / BoM. `update_data()`
caches each source as parquet under `data/cache/`, so re-runs on the same
vintage are instant. FRED needs an API key in `.Renviron`; a source that fails
(offline, missing key) is skipped and backfilled from the fixture. Driver:
`scripts/01_update_data.R`.

### Re-estimating the state-space trends

`to_martin_database()` re-estimates MARTIN's unobserved-component trends — the
NAIRU (`TLUR`), the neutral real rate (`RSTAR`), inflation expectations
(`PI_E`), and the productivity / population / hours trends — with KFAS Kalman
filters as part of the build (`R/state_space.R`: `fit_nairu_kfas()`,
`fit_rstar_kfas_full()`, `fit_pie_kfas()`, via `apply_state_space_trends()`).
This runs on the **public-data path only**; `read_fixture()` and
`read_csv_database()` use the trend values already present in the file rather
than re-estimating them.

## Coefficients: frozen vs re-estimated

The behavioural (AF) model defines 95 `BEHAVIORAL>` equations, split for
readability into one file per equation under `extdata/model_af/` (grouped into
per-block subdirectories: `01_household/`, `05_prices_wages/`, ...) and
assembled at load.
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

Runs the full `testthat` suite (800+ assertions), including a regression test
that asserts the no-adjustment solve matches the canonical `bimets` reference
to within solver tolerance. Network-dependent data-fetch tests skip when offline.

## Provenance

The `bimets` model definitions in `extdata/` (the per-equation `model_af/` files
and the single-file `MARTINMOD.txt`/`MARTINMOD_EST.txt` variants) and the frozen
`martin_data_fixture.xlsx` are vendored, with attribution, from the upstream
MARTIN ports:

- the EViews/R implementation (the canonical equations and data-flow recipes),
- the [`bimets`](https://cran.r-project.org/package=bimets) MARTIN port that the
  solver is built on.

MARTIN itself is documented in RBA Research Discussion Paper 2019-07.
