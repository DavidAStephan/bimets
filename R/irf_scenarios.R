#' Standard impulse responses for testing MARTIN's model properties
#'
#' A small library of *named, economically-sized* shocks for inspecting the
#' model's dynamic properties (the kind of impulse responses RBA technical
#' notes report). Unlike [sensitivity_matrix()] — which sweeps every adjustable
#' equation with a tiny standardized add-factor — these are a fixed set of
#' interpretable shocks delivered as add-factors via [adjustment_list()] and
#' solved with [solve_martin()].
#'
#' The four standard shocks (see [standard_irf_specs()]):
#'   * `monetary_100bp` — +100bp cash rate (NCR) for one quarter, then the
#'     Taylor rule resumes (a true monetary-policy *shock*).
#'   * `govcons_1pc`    — +1% government consumption (GC) for one quarter.
#'   * `commodity_10pc` — a *permanent* +10% lift to world commodity prices
#'     (WPCOM): an initial +10% level jump, then a small sustained add-factor
#'     that offsets the WPCOM equation's own mean-reversion so the level is held
#'     near +10% over the whole projection.
#'   * `rer_10pc`       — a ~+10% real-exchange-rate (RTWI) appreciation for one
#'     quarter, then it mean-reverts under its own equation.
#'
#' @section Why add-factors (and not exogenize):
#'   Every shock is an add-factor on the relevant equation's residual, leaving
#'   the variable endogenous so its lags carry the shock forward and it
#'   propagates through the rest of the model. Holding a variable on a shocked
#'   path with `exogenize` does *not* propagate downstream in this engine (the
#'   exogenised series is pinned but the equations that read it do not respond),
#'   so add-factors are the correct mechanism for impulse responses. `exogenize`
#'   remains the right tool for *holding a variable at baseline* (see
#'   [solve_martin()] and scripts/04).
#'
#' @section The "permanent" commodity shock:
#'   This bimets port models real commodity prices (WPCOM) as a mean-reverting
#'   AR process, so a literally-permanent level shift is not a native concept.
#'   The `commodity_10pc` shock therefore counters the equation's own
#'   error-correction (coefficient 0.05) with a small sustained add-factor,
#'   holding WPCOM within roughly +10% to +12% across the horizon. A one-off
#'   +10% jump (set `hold = NA`) instead decays at the model's reversion rate.
#'
#' @section Linearity / scaling:
#'   MARTIN is nonlinear. The +100bp / +1% / +10% sizes here are the
#'   conventional reporting magnitudes, not freely rescalable — re-run with a
#'   custom spec at a different size rather than scaling the table.
NULL

# WPCOM equation error-correction coefficient (see the WPCOM block in
# extdata/model_af/11_world.txt): the level reverts toward its long-run real
# value at this rate per quarter, so a sustained add-factor of
# `rate * log(1+shock)` holds the level shift.
.wpcom_ec_rate <- 0.05

# A loosened add-factor ceiling for the FX / world-price shocks: log(1.10) ~=
# 0.095 exceeds the default 0.02 log_diff ceiling (those defaults guard against
# runaway judgemental tunes, not a deliberate, documented +10% IRF).
.irf_log_ceiling <- function() {
  list(log_diff = 0.12, level = 1.0, percent = 5.0, unknown = 5.0)
}

# Variables reported as a rate (percentage points): an additive deviation, not
# a percent deviation. Everything else is reported as a percent deviation.
.irf_rate_vars <- function() {
  c("LUR", "TLUR", "NCR", "RCR", "RSTAR", "N2R", "N10R", "NBR", "NMR",
    "R2R", "WRR", "WR2R", "PI_E")
}

#' The four standard impulse-response shock specifications
#'
#' @return A named list of shock specs. Each is delivered as an add-factor and
#'   has: `label` (human text), `equation`, `value` (the per-quarter add-factor,
#'   i.e. the impact-quarter jump), `n_quarters` (length of the explicit shock
#'   window; `NA` = run to the horizon end for a permanent shock), `tail` (see
#'   [adjustment()]), `hold` (`NA`, or a sustained per-quarter add-factor applied
#'   after the first quarter to hold a permanent level shift), and `ceiling`
#'   (`NULL`, or a `sibyl.af_ceiling` override for shocks larger than the
#'   default per-units bound).
#' @export
standard_irf_specs <- function() {
  list(
    monetary_100bp = list(
      label      = "Monetary policy: +100bp cash rate (1 quarter)",
      equation   = "NCR",
      value      = 1.00,             # percent units: +100 basis points
      n_quarters = 1L,
      tail       = "zero",
      hold       = NA_real_,
      ceiling    = NULL              # 1.00 < default percent ceiling (5.0)
    ),
    govcons_1pc = list(
      label      = "Government consumption: +1% (1 quarter)",
      equation   = "GC",
      value      = 0.01,             # log_diff: ~ +1% on the quarterly level
      n_quarters = 1L,
      tail       = "zero",
      hold       = NA_real_,
      ceiling    = NULL              # 0.01 < default log_diff ceiling (0.02)
    ),
    commodity_10pc = list(
      label      = "World commodity prices: permanent +10%",
      equation   = "WPCOM",
      value      = log(1.10),        # +10% level jump on impact
      n_quarters = NA_integer_,      # permanent: run to the horizon end
      tail       = "carry",
      hold       = .wpcom_ec_rate * log(1.10),  # offset WPCOM mean-reversion
      ceiling    = .irf_log_ceiling()
    ),
    rer_10pc = list(
      label      = "Real exchange rate: +10% appreciation (1 quarter)",
      equation   = "RTWI",
      value      = log(1.10),        # ~ +10% appreciation on impact
      n_quarters = 1L,
      tail       = "zero",
      hold       = NA_real_,
      ceiling    = .irf_log_ceiling()
    )
  )
}

# Quarter string `offset` quarters after `shock_start` (0 == shock_start).
.quarter_at_offset <- function(shock_start, offset) {
  quarter_offsets(shock_start, n_after = offset)[offset + 1L]
}

# Build the per-quarter add-factor value vector for a spec over `shock_q`:
# the first quarter takes `value`; if `hold` is set, every later quarter takes
# `hold` (a sustained offset that holds a permanent level shift).
.irf_value_vector <- function(spec, n) {
  vals <- rep(spec$value, n)
  if (!is.na(spec$hold) && n > 1L) vals[-1L] <- spec$hold
  vals
}

#' Solve one standard-IRF shock
#'
#' @param database The same database passed to [solve_martin()].
#' @param horizon Length-2 `c("yyyyQq", "yyyyQq")`.
#' @param shock_start `"yyyyQq"` of the first shocked quarter.
#' @param spec One element of [standard_irf_specs()].
#' @param coefficients,estimation_end Passed straight to [solve_martin()].
#' @return The scenario projection tibble (with `solve_martin()`'s attributes,
#'   including `convergence`).
#' @export
run_irf_scenario <- function(database, horizon, shock_start, spec,
                             coefficients = c("frozen", "reestimated"),
                             estimation_end = NULL) {
  coefficients <- match.arg(coefficients)

  # Explicit shock window: a fixed length, or the whole horizon when permanent.
  if (is.na(spec$n_quarters)) {
    shock_q <- quarter_seq(shock_start, horizon[2])
  } else {
    last_q  <- .quarter_at_offset(shock_start, spec$n_quarters - 1L)
    shock_q <- quarter_seq(shock_start, last_q)
  }
  vals <- .irf_value_vector(spec, length(shock_q))

  # Loosen the add-factor ceiling for the (deliberately large) world-price /
  # FX shocks, restoring the prior setting on exit.
  if (!is.null(spec$ceiling)) {
    old <- getOption("sibyl.af_ceiling")
    options(sibyl.af_ceiling = spec$ceiling)
    on.exit(options(sibyl.af_ceiling = old), add = TRUE)
  }

  af <- adjustment_list(
    adjustment(
      equation  = spec$equation,
      horizon   = shock_q,
      value     = vals,
      rationale = paste("standard IRF:", spec$label),
      tail      = spec$tail
    )
  )
  solve_martin(
    database, adjustments = af, horizon = horizon,
    coefficients = coefficients, estimation_end = estimation_end,
    scenario = spec$label
  )
}

#' Deviation of a scenario from baseline at a set of offsets
#'
#' @param baseline,scenario Long projection tibbles
#'   `(variable, quarter, value)`.
#' @param vars Character vector of variables to report.
#' @param shock_start `"yyyyQq"` the shock begins.
#' @param offsets Integer quarter offsets from `shock_start` (0 = impact).
#' @param scenario_key,scenario_label Identifiers written into the output.
#' @return A tidy tibble: one row per (variable, offset) with `baseline`,
#'   `scenario_value`, `deviation`, and `measure` (`"pct"` or `"ppt"`).
#' @export
irf_deviation_table <- function(baseline, scenario, vars, shock_start,
                                offsets, scenario_key, scenario_label) {
  base_lk <- lapply(split(baseline, baseline$variable),
                    function(d) stats::setNames(d$value, d$quarter))
  scen_lk <- lapply(split(scenario, scenario$variable),
                    function(d) stats::setNames(d$value, d$quarter))
  rate_vars <- .irf_rate_vars()

  rows <- list()
  for (v in vars) {
    bv <- base_lk[[v]]
    sv <- scen_lk[[v]]
    if (is.null(bv) || is.null(sv)) next
    is_rate <- v %in% rate_vars
    for (o in offsets) {
      q <- .quarter_at_offset(shock_start, o)
      if (!q %in% names(bv) || !q %in% names(sv)) next
      b <- unname(bv[q])
      s <- unname(sv[q])
      if (is_rate) {
        dev <- s - b
        measure <- "ppt"
      } else {
        dev <- if (abs(b) > 1e-12) 100 * (s / b - 1) else NA_real_
        measure <- "pct"
      }
      rows[[length(rows) + 1L]] <- tibble::tibble(
        scenario       = scenario_key,
        scenario_label = scenario_label,
        variable       = v,
        offset_q       = as.integer(o),
        quarter        = q,
        baseline       = b,
        scenario_value = s,
        deviation      = dev,
        measure        = measure
      )
    }
  }
  dplyr::bind_rows(rows)
}

#' Run the standard battery of impulse responses
#'
#' Solves a baseline once, then each shock in [standard_irf_specs()] (or a
#' caller-supplied `specs` subset), and returns a tidy table of deviations from
#' baseline for `report_vars` at `offsets` quarters after the shock starts.
#'
#' @param database The database passed to [solve_martin()] (extend exogenous
#'   paths to `horizon[2]` first when projecting past the data end).
#' @param horizon Length-2 `c("yyyyQq","yyyyQq")`.
#' @param shock_start `"yyyyQq"` for the first shocked quarter. Default `NULL`
#'   derives `horizon[2] - max(offsets)` so the longest offset stays in-window.
#' @param baseline Optional pre-computed baseline projection; solved here if
#'   `NULL`.
#' @param report_vars Headline variables to report deviations on.
#' @param offsets Integer quarter offsets from `shock_start` (0 = impact).
#' @param specs Named list of shock specs; default [standard_irf_specs()].
#' @param coefficients,estimation_end Passed to [solve_martin()] (frozen by
#'   default — see the project conventions on the COVID break).
#' @param progress Logical; one line per shock. Default `interactive()`.
#' @return A tidy tibble (rows = scenario x variable x offset). Attributes:
#'   `shock_start`, `offsets`, `baseline` (the baseline projection),
#'   `convergence` (named list of each scenario's convergence diagnostics).
#' @export
standard_irfs <- function(database,
                          horizon,
                          shock_start  = NULL,
                          baseline     = NULL,
                          report_vars  = c("Y", "GNE", "LUR", "P", "PTM",
                                           "NCR", "RTWI", "TOT", "WPCOM"),
                          offsets      = c(0L, 1L, 4L, 8L, 12L, 16L, 20L),
                          specs        = standard_irf_specs(),
                          coefficients = c("frozen", "reestimated"),
                          estimation_end = NULL,
                          progress     = interactive()) {
  coefficients <- match.arg(coefficients)
  stopifnot(length(horizon) == 2L, is.character(horizon))
  offsets <- as.integer(offsets)

  if (is.null(shock_start)) {
    shock_start <- quarter_minus(horizon[2], max(offsets))
  }

  if (is.null(baseline)) {
    if (progress) message("[standard_irfs] solving baseline ...")
    baseline <- solve_martin(
      database, horizon = horizon, scenario = "baseline",
      coefficients = coefficients, estimation_end = estimation_end
    )
  }

  conv <- list()
  rows <- list()
  for (key in names(specs)) {
    spec <- specs[[key]]
    if (progress) message(sprintf("[standard_irfs] shock: %s", spec$label))
    scen <- run_irf_scenario(
      database, horizon, shock_start, spec,
      coefficients = coefficients, estimation_end = estimation_end
    )
    conv[[key]] <- attr(scen, "convergence")
    rows[[key]] <- irf_deviation_table(
      baseline, scen, report_vars, shock_start, offsets,
      scenario_key = key, scenario_label = spec$label
    )
  }

  out <- dplyr::bind_rows(rows)
  attr(out, "shock_start") <- shock_start
  attr(out, "offsets")     <- offsets
  attr(out, "baseline")    <- baseline
  attr(out, "convergence") <- conv
  out
}
