# 05 — Impulse responses (multiplier / sensitivity matrix).
#
#   Rscript scripts/05_irf.R
#
# sensitivity_matrix() shocks each chosen equation's add-factor by a
# standardized amount, sustained over a few quarters with a decaying tail,
# re-solves, and records the deviation of headline targets from baseline at a
# set of horizons. The result is an impulse-response / multiplier table.
#
# MARTIN is nonlinear, so probe_curvature = TRUE also solves at 3x the shock and
# reports curvature_ratio (~1 if the response scales linearly) and linearity_ok.

root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "setup.R"))

db <- read_fixture()
horizon <- c("2008Q1", "2018Q4")           # in-sample window: structural IRFs

cat("Baseline ...\n")
base <- solve_martin(db, horizon = horizon, scenario = "baseline")

cat("Computing impulse responses ...\n")
irf <- sensitivity_matrix(
  db,
  baseline        = base,
  horizon         = horizon,
  equations       = c("NCR", "PTM", "RC", "PW"),   # policy, prices, consumption, wages
  targets         = c("Y", "LUR", "P", "NCR"),
  measure_offsets = c(1L, 4L, 8L),
  probe_curvature = TRUE,
  progress        = FALSE
)

cat("\nImpulse responses (deviation from baseline per standardized shock):\n")
show <- irf[, c("equation", "shock_value", "target", "offset_q",
                "deviation", "linearity_ok")]
show$deviation <- round(show$deviation, 5)
print(as.data.frame(show), row.names = FALSE)

cat("\nRead: row (NCR, LUR, offset 8) = deviation of unemployment 8 quarters",
    "\nafter a standardized cash-rate shock. linearity_ok flags where the",
    "\nresponse scales ~linearly with shock size.\n")
