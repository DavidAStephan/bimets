# Running MARTIN from your own CSV data

This guide walks through the whole workflow when you have your **own data in a
CSV** and want to estimate, forecast, and run impulse responses — no public
data downloads, no API keys.

If you just want the short version:

```r
source("setup.R")                              # from the repo root
db   <- read_csv_database("my_data.csv")       # your CSV -> model database
base <- solve_martin(db, horizon = c("2010Q1", "2024Q4"))   # forecast
```

or run the end-to-end demo driver:

```sh
Rscript scripts/09_forecast_from_csv.R
```

The rest of this guide explains each step and the things worth knowing.

---

## 0. One-time setup

You need R (≥ 4.3) and the CRAN packages listed in the
[README](../README.md#setup). Install them once, then from the **repo root**:

```r
source("setup.R")
```

`setup.R` loads `bimets` and the other dependencies and sources every function
in `R/` into your session. After this the functions used below
(`read_csv_database()`, `solve_martin()`, ...) are available. You do **not**
need API keys — those are only for the live-download path.

---

## 1. Get your CSV into the right shape

The format is deliberately simple — **one row per quarter, one column per
variable**:

| column | meaning |
|---|---|
| a **period** column | the quarter, as `2019Q3` (case-insensitive) **or** a quarter-start date `2019-07-01`. Name it `quarter`, `date`, or `period` and it is auto-detected. |
| one column **per MARTIN variable** | the header is the **exact** variable name (case-sensitive: `RC`, `NCR`, `WPCOM`, `Y`, ...). Values are numeric; blank / `NA` means missing. |

Example:

```
quarter,Y,RC,P,NCR,LUR,WPCOM
2018Q1,470123.4,300111.2,372.1,1.50,5.45,131.2
2018Q2,472980.1,301540.9,373.0,1.50,5.41,133.7
...
```

Rows do not need to be sorted and may have gaps — the loader sorts by period
and puts each series on a regular quarterly axis.

### The easy way: start from a template

You don't have to type the ~200 variable names by hand. Export the bundled
fixture to the exact CSV format and edit it:

```r
source("setup.R")
database_to_csv(read_fixture(), "template.csv")   # quarter col + one col per variable
```

`template.csv` now has every variable as a column, filled with the bundled
history. Replace the values (or whole columns) with yours and save. You can
also list the names directly:

```r
martin_model_variables("af")                 # all variables the model uses
martin_model_variables("af", "endogenous")   # just the ones the model solves
```

### You don't need every variable

MARTIN estimates its behavioural equations on history going back to the
1980s–2000s. If your CSV doesn't reach that far back (or omits some series),
fill the gaps from the bundled fixture:

```r
db <- read_csv_database("my_data.csv", fallback = read_fixture())
```

This takes your CSV value wherever you supplied one and falls back to the
bundled data everywhere else (quarter by quarter, per variable). It is the
most robust way to run with a partial / recent-only CSV.

---

## 2. Load the CSV into the model database

```r
db <- read_csv_database("my_data.csv")
```

`db` is a named list of quarterly time series — the exact object every other
function consumes. The call prints a coverage report, and records the same
information in attributes:

```r
attr(db, "vars_supplied")    # model variables your CSV provided
attr(db, "vars_missing")     # model variables it did NOT provide
attr(db, "unknown_columns")  # CSV columns that aren't MARTIN variables (loaded anyway)
```

Check `vars_missing` — anything important there is a candidate for
`fallback = read_fixture()` (see above). Useful options:

```r
read_csv_database("my_data.csv",
                  date_col = "obs_date",   # name the period column explicitly
                  fallback = read_fixture(),
                  validate = TRUE)         # print the coverage report (default)
```

---

## 3. Forecast

### Unconditional (baseline)

```r
base <- solve_martin(db, horizon = c("2010Q1", "2024Q4"))
attr(base, "convergence")     # list(converged = TRUE, n_nonfinite = 0)
```

`base` is a tidy long tibble of `(variable, quarter, value, scenario)`. With no
add-factors the in-sample part **replays history** and the out-of-sample part is
the model's own baseline.

**Forecasting past the end of your data?** The simulator needs a value for every
exogenous variable (world economy, policy targets, calendar dummies) at every
quarter in the horizon. If your horizon extends beyond your CSV's last quarter,
extend the exogenous paths first (and, optionally, nowcast the ragged edge):

```r
db <- extend_exogenous(db, end_quarter = "2024Q4")          # carry exogenous paths forward
db <- splice_handover(db, nowcast_handover(db, h = 2))      # optional: fill the ragged edge
base <- solve_martin(db, horizon = c("2010Q1", "2024Q4"))
```

(See `scripts/03_forecast_unconditional.R` for the full pipeline.)

### Conditional (scenarios)

Two ways to condition a projection — both via `solve_martin()`:

```r
# A. Add-factor: a +50bp cash-rate path held over 2024
af <- adjustment_list(
  adjustment("NCR", horizon = c("2024Q1","2024Q2","2024Q3","2024Q4"),
             value = rep(0.50, 4), rationale = "scenario: +50bp", tail = "zero")
)
tight <- solve_martin(db, adjustments = af, horizon = c("2010Q1","2024Q4"))

# B. Exogenise a variable (hold it at a chosen path); see scripts/04.
```

See `scripts/04_forecast_conditional.R`.

---

## 4. Impulse responses and uncertainty

```r
# Standard, economically-sized shocks -> a tidy deviation table:
irf <- standard_irfs(db, horizon = c("2005Q1", "2019Q2"))

# Generic per-equation multiplier table:
sm  <- sensitivity_matrix(db, baseline = base, horizon = c("2010Q1","2018Q4"))

# Stochastic bands:
bands <- solve_martin_stochastic(db, horizon = c("2010Q1","2024Q4"), n_draws = 200)
```

The standard IRF battery is also a runnable script — `Rscript
scripts/08_standard_irfs.R` — which writes per-scenario CSVs to `results/irfs/`.

---

## 5. The whole thing in one script

`scripts/09_forecast_from_csv.R` does steps 1–3 end to end (it builds a CSV
template from the fixture, reads it back, and forecasts). Point it at your own
CSV by changing the `csv_path`, or copy it as a starting point:

```sh
Rscript scripts/09_forecast_from_csv.R
```

---

## 6. Moving to another machine (offline / work computer)

A common setup: you can fetch data on one machine but want to **run the model on
another** that is offline, has no API keys, or can't install the download
packages. Freeze the data to a CSV on the connected machine and carry just that
CSV across.

### Get the code there

```sh
git clone https://github.com/DavidAStephan/bimets.git
cd bimets
```

In R, install only the **required** packages — the CSV path doesn't need the
live-download ones (`readabs`, `readrba`, `fredr`, `arrow`, `OECD`):

```r
install.packages(c(
  "bimets","dplyr","tidyr","tibble","purrr","rlang","stringr","lubridate",
  "readr","glue","readxl","xts","zoo","KFAS","tempdisagg",
  "fable","fabletools","feasts","tsibble"
))
```

`setup.R` only prints a note (not an error) if the optional download packages
are absent, so this lean install is enough to run everything below.

### Build the CSV once, on a machine that has the data

Export **after** `to_martin_database()` so the re-estimated state-space trends
(`TLUR`, `RSTAR`, `PI_E`, ...) and the full history are **baked into the CSV** —
the offline machine then needs no network, no keys, and no re-estimation:

```r
source("setup.R")
panel <- update_data()                            # current ABS/RBA/FRED/... vintages
db    <- to_martin_database(panel)                # builds + re-estimates the trends
db    <- merge_with_fallback(db, read_fixture())  # backfill deep history
database_to_csv(db, "martin_data.csv")            # freeze the whole database to one CSV
```

(No connected machine? Use the fixture template from
[step 1](#the-easy-way-start-from-a-template) and fill in your own numbers
instead — then carry that CSV across.)

### Run it on the offline machine

Copy `martin_data.csv` over, then:

```r
source("setup.R")
db   <- read_csv_database("martin_data.csv", fallback = read_fixture())
db   <- extend_exogenous(db, end_quarter = "2026Q1")        # only if forecasting past the data end
base <- solve_martin(db, horizon = c("2010Q1", "2026Q1"))   # forecast
irf  <- standard_irfs(db, horizon = c("2010Q1", "2026Q1"))  # impulse responses
```

Everything runs locally from the one CSV — no downloads. (If you built the CSV
the "baked-in trends" way above, `fallback = read_fixture()` is belt-and-braces;
keep it so any column you didn't carry still resolves.)

---

## Things worth knowing

- **Variable names are case-sensitive.** `rc` won't be recognised as `RC`; the
  loader warns about unrecognised columns but still loads them.
- **Quarterly only.** MARTIN is a quarterly model; the period column must be
  quarterly.
- **Coefficients are frozen by default.** `solve_martin()` re-fits the free
  coefficients on the model's embedded sample (ending 2019Q3), reproducing the
  published values. Re-estimating over a later sample crosses the COVID break
  and changes the coefficients — it's an explicit opt-in
  (`coefficients = "reestimated", estimation_end = "2024Q4"`), never the default.
- **Enough history to estimate.** The behavioural equations are fit on history
  back to the 1980s–2000s. A short / recent-only CSV won't estimate on its own —
  use `fallback = read_fixture()` so the historical sample comes from the bundled
  data while your CSV supplies the recent vintage.
- **Always check `attr(base, "convergence")`.** A non-converged solve can leave
  non-finite values; the attribute reports this so you never read garbage.
```
