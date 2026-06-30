# 08 — Standard impulse responses (model-property battery) -> CSV.
#
#   Rscript scripts/08_standard_irfs.R
#
# A fixed set of named, economically-sized shocks for inspecting MARTIN's
# dynamic properties (cf. the RBA technical-note IRFs). Each is solved against
# a common baseline and the deviation of EVERY endogenous variable is reported
# at a set of horizons after the shock:
#
#   1. monetary_100bp  — +100bp cash rate (NCR) for one quarter, then the
#                        Taylor rule resumes (a true monetary-policy shock).
#   2. govcons_1pc     — +1% government consumption (GC) for one quarter.
#   3. commodity_10pc  — a PERMANENT +10% lift to world commodity prices
#                        (WPCOM), held by offsetting the equation's reversion.
#   4. rer_10pc        — ~+10% real-exchange-rate (RTWI) appreciation, 1 qtr.
#
# Every shock is delivered as an add-factor on the equation's residual, leaving
# the variable endogenous so its lags carry the shock forward and it propagates
# through the model. (Holding a variable on a shocked path with `exogenize` does
# NOT propagate downstream in this engine — see R/irf_scenarios.R.)
#
# REPORTING UNITS: every variable is reported as a percent (%) deviation from
# baseline EXCEPT the rate variables — the unemployment rate, all domestic and
# world interest rates and spreads, the neutral rate, and inflation expectations
# (see .irf_rate_vars()) — which are reported as plain percentage-point (ppt)
# deviations. Exchange-rate indices (RTWI/NTWI/NUSD) stay as % deviations.
#
# MARTIN is nonlinear: the +100bp / +1% / +10% magnitudes are conventional
# reporting sizes, not freely rescalable. Coefficients are FROZEN by default
# (the project convention — re-estimating crosses the COVID break).
#
# Outputs (committed): results/irfs/standard_irfs_long.csv (tidy, all scenarios)
# and one wide table per scenario, results/irfs/irf_<scenario>.csv.

root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "setup.R"))

db <- read_fixture()
# In-sample structural window (exogenous world paths are real history here),
# matching scripts/05_irf.R. The shock lands with room for the longest offset.
horizon     <- c("2005Q1", "2019Q2")
shock_start <- "2010Q1"
offsets     <- c(0L, 1L, 2L, 4L, 8L, 12L, 16L, 20L)

# Report every variable the model solves; present each as a % deviation EXCEPT
# the rate variables (.irf_rate_vars() — unemployment + interest rates/spreads),
# which are reported as ppt deviations.
report_vars <- martin_model_variables("af", which = "endogenous")

cat("Baseline ", horizon[1], " -> ", horizon[2], " ...\n", sep = "")
base <- solve_martin(db, horizon = horizon, scenario = "baseline")
cat(sprintf("  converged: %s\n", attr(base, "convergence")$converged))

cat(sprintf("Running the standard IRF battery over %d variables ...\n",
            length(report_vars)))
irf <- standard_irfs(
  db,
  horizon     = horizon,
  shock_start = shock_start,
  baseline    = base,
  report_vars = report_vars,
  offsets     = offsets,
  progress    = TRUE
)

# Per-scenario convergence (never report deviations off a garbage solve).
conv <- attr(irf, "convergence")
cat("\nConvergence:\n")
for (k in names(conv)) {
  cat(sprintf("  %-16s %s\n", k, conv[[k]]$converged))
}

# ---- write CSVs -----------------------------------------------------------
outdir <- file.path(root, "results", "irfs")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

# 1. Tidy long table across all scenarios. `unit` makes the % vs ppt convention
#    explicit per row; `deviation` is the value in those units.
long <- irf
long$unit <- ifelse(long$measure == "ppt", "ppt_deviation", "pct_deviation")
long <- long[, c("scenario", "scenario_label", "variable", "offset_q",
                 "quarter", "baseline", "scenario_value", "deviation", "unit")]
long_path <- file.path(outdir, "standard_irfs_long.csv")
utils::write.csv(long, long_path, row.names = FALSE)

# 2. One wide table per scenario: rows = variable, columns = h+offset deviation,
#    plus a `unit` column. Rows ordered as report_vars (model/solve order).
offs <- sort(unique(irf$offset_q))
wide_for <- function(s) {
  vars <- intersect(report_vars, unique(s$variable))
  out  <- data.frame(variable = vars, stringsAsFactors = FALSE)
  out$unit <- vapply(vars, function(v) {
    m <- s$measure[s$variable == v]
    if (length(m) && m[1] == "ppt") "ppt_deviation" else "pct_deviation"
  }, character(1))
  for (o in offs) {
    out[[paste0("h", o)]] <- vapply(vars, function(v) {
      x <- s$deviation[s$variable == v & s$offset_q == o]
      if (length(x)) round(x[1], 5) else NA_real_
    }, numeric(1))
  }
  out
}
written <- character(0)
for (k in unique(irf$scenario)) {
  p <- file.path(outdir, paste0("irf_", k, ".csv"))
  utils::write.csv(wide_for(irf[irf$scenario == k, , drop = FALSE]),
                   p, row.names = FALSE)
  written <- c(written, p)
}

# ---- compact console preview (headline subset only) -----------------------
headline <- c("Y", "GNE", "LUR", "P", "PTM", "NCR", "RTWI", "TOT", "WPCOM")
fmt_dev <- function(d, measure) {
  ifelse(is.na(d), "    .",
         sprintf("%+7.3f%s", d, ifelse(measure == "ppt", "p", "%")))
}
for (k in unique(irf$scenario)) {
  s <- irf[irf$scenario == k & irf$variable %in% headline, , drop = FALSE]
  cat(sprintf("\n=== %s (headline subset) ===\n", s$scenario_label[1]))
  cat(sprintf("%-6s", "var"))
  for (o in offs) cat(sprintf(" %8s", paste0("h+", o)))
  cat("\n")
  for (v in intersect(headline, unique(s$variable))) {
    cat(sprintf("%-6s", v))
    for (o in offs) {
      cell <- s[s$variable == v & s$offset_q == o, , drop = FALSE]
      txt  <- if (nrow(cell)) fmt_dev(cell$deviation, cell$measure) else "    ."
      cat(sprintf(" %8s", txt))
    }
    cat("\n")
  }
}
cat("\nRead: 'p' = percentage-point deviation (rates: unemployment + interest",
    "rates/spreads);\n      '%' = percent deviation from baseline (all else).\n")

saveRDS(irf, file.path(root, "data", "standard_irfs.rds"))
cat(sprintf("\nWrote %d CSV files to %s:\n", length(written) + 1L, outdir))
cat("  standard_irfs_long.csv  (tidy, all scenarios x all variables)\n")
for (p in written) cat("  ", basename(p), "\n", sep = "")
