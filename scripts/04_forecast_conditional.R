# 04 — Conditional forecasts.
#
#   Rscript scripts/04_forecast_conditional.R
#
# Two ways to condition a MARTIN projection:
#
#   A. Add-factors — perturb an equation's residual over a horizon (a
#      judgemental "tune"). Here: a sustained +50bp cash-rate path.
#   B. Exogenize — hold a variable on a chosen path (here its baseline) so it
#      stops responding to the model. Here: a household-demand shock solved with
#      the cash rate HELD at baseline, isolating the demand impulse from the
#      policy response.

root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "setup.R"))

# ---- shared forecast database ---------------------------------------------
db <- read_fixture()
horizon  <- c("2015Q1", "2024Q4")
fc_start <- "2020Q1"                       # first out-of-sample quarter
db <- splice_handover(db, nowcast_handover(db, h = 2L, method = "naive"))
db <- extend_exogenous(db, end_quarter = horizon[2])

g <- function(p, v, q) { x <- p$value[p$variable == v & p$quarter == q]; if (length(x)) x else NA_real_ }
fc_qs <- quarter_seq(fc_start, horizon[2])

cat("Baseline ...\n")
base <- solve_martin(db, horizon = horizon, scenario = "baseline")

# ---- A. Add-factor: +50bp cash rate, sustained over the forecast, decaying ---
cat("Conditional A: +50bp cash-rate add-factor ...\n")
af <- adjustment_list(
  adjustment(equation = "NCR", horizon = fc_qs,
             value = rep(0.50, length(fc_qs)),
             rationale = "scenario: +50bp cash rate held over the forecast",
             tail = "zero")
)
condA <- solve_martin(db, adjustments = af, horizon = horizon, scenario = "tighter")

# ---- B. Exogenize the cash rate, shock household consumption ----------------
cat("Conditional B: household-demand shock with cash rate exogenised at baseline ...\n")
demand <- adjustment_list(
  adjustment(equation = "RC", horizon = fc_qs,
             value = rep(0.004, length(fc_qs)),
             rationale = "scenario: persistent positive consumption shock",
             tail = "carry")
)
condB <- solve_martin(
  db, adjustments = demand, horizon = horizon, scenario = "demand_fixed_rate",
  exogenize = "NCR", baseline_for_exogenize = base,
  exogenize_range = c(fc_start, horizon[2])
)

# ---- compare ---------------------------------------------------------------
cat("\nDeviation from baseline at 2024Q4 (level differences):\n")
cat(sprintf("%-26s %8s %8s %8s\n", "scenario", "LUR", "P", "NCR"))
for (nm in c("A_tighter", "B_demand")) {
  p <- if (nm == "A_tighter") condA else condB
  cat(sprintf("%-26s %+8.3f %+8.3f %+8.3f\n", nm,
              g(p, "LUR", "2024Q4") - g(base, "LUR", "2024Q4"),
              g(p, "P",   "2024Q4") - g(base, "P",   "2024Q4"),
              g(p, "NCR", "2024Q4") - g(base, "NCR", "2024Q4")))
}
cat("\n(B's NCR delta should be ~0 — it is held at baseline by exogenize.)\n")
