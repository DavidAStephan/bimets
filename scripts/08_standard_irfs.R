# 08 — Standard impulse responses (model-property battery).
#
#   Rscript scripts/08_standard_irfs.R
#
# A fixed set of named, economically-sized shocks for inspecting MARTIN's
# dynamic properties (cf. the RBA technical-note IRFs). Each is solved against
# a common baseline and the deviation of the headline aggregates is reported at
# a set of horizons after the shock:
#
#   1. monetary_100bp  — +100bp cash rate (NCR) for one quarter, then the
#                        Taylor rule resumes (a true monetary-policy shock).
#   2. govcons_1pc     — +1% government consumption (GC) for one quarter.
#   3. commodity_10pc  — a PERMANENT +10% lift to world commodity prices
#                        (WPCOM), held by offsetting the equation's reversion.
#   4. rer_10pc        — ~+10% real-exchange-rate (RTWI) appreciation, 1 quarter.
#
# Every shock is delivered as an add-factor on the equation's residual, leaving
# the variable endogenous so its lags carry the shock forward and it propagates
# through the model. (Holding a variable on a shocked path with `exogenize` does
# NOT propagate downstream in this engine — see R/irf_scenarios.R.)
#
# MARTIN is nonlinear: the +100bp / +1% / +10% magnitudes are conventional
# reporting sizes, not freely rescalable. Coefficients are FROZEN by default
# (the project convention — re-estimating crosses the COVID break).

root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "setup.R"))

db <- read_fixture()
# In-sample structural window (exogenous world paths are real history here),
# matching scripts/05_irf.R. The shock lands with room for the longest offset.
horizon     <- c("2005Q1", "2019Q2")
shock_start <- "2010Q1"
offsets     <- c(0L, 1L, 4L, 8L, 12L, 16L)

cat("Baseline ", horizon[1], " -> ", horizon[2], " ...\n", sep = "")
base <- solve_martin(db, horizon = horizon, scenario = "baseline")
cat(sprintf("  converged: %s\n", attr(base, "convergence")$converged))

cat("Running the standard impulse-response battery ...\n")
irf <- standard_irfs(
  db,
  horizon     = horizon,
  shock_start = shock_start,
  baseline    = base,
  offsets     = offsets,
  progress    = TRUE
)

# Per-scenario convergence (never report deviations off a garbage solve).
conv <- attr(irf, "convergence")
cat("\nConvergence:\n")
for (k in names(conv)) {
  cat(sprintf("  %-16s %s\n", k, conv[[k]]$converged))
}

# Print one compact table per scenario: variable x offset deviation.
fmt_dev <- function(d, measure) {
  ifelse(is.na(d), "    .",
         sprintf("%+7.3f%s", d, ifelse(measure == "ppt", "p", "%")))
}
for (k in unique(irf$scenario)) {
  s     <- irf[irf$scenario == k, , drop = FALSE]
  label <- s$scenario_label[1]
  cat(sprintf("\n=== %s ===\n", label))
  offs  <- sort(unique(s$offset_q))
  cat(sprintf("%-6s", "var"))
  for (o in offs) cat(sprintf(" %8s", paste0("h+", o)))
  cat("\n")
  for (v in unique(s$variable)) {
    cat(sprintf("%-6s", v))
    for (o in offs) {
      cell <- s[s$variable == v & s$offset_q == o, , drop = FALSE]
      txt  <- if (nrow(cell)) fmt_dev(cell$deviation, cell$measure) else "    ."
      cat(sprintf(" %8s", txt))
    }
    cat("\n")
  }
}

cat("\nRead: 'p' = percentage-point deviation (rates: LUR, NCR);",
    "'%' = percent deviation from baseline (levels/indices).\n")

saveRDS(irf, file.path(root, "data", "standard_irfs.rds"))
cat("\nSaved IRF table to data/standard_irfs.rds\n")
