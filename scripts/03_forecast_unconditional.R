# 03 — Unconditional forecast.
#
#   Rscript scripts/03_forecast_unconditional.R
#
# The baseline projection: solve MARTIN forward with no judgemental
# add-factors. Pipeline:
#   1. nowcast the ragged edge (Q+0/Q+1 for the handover variables that lag in
#      real time) and splice it back into the database;
#   2. extend exogenous paths (world economy, policy targets, dummies) forward
#      to the horizon end so the simulator has values at every period;
#   3. solve_martin() over the horizon (frozen coefficients by default).
#
# With no adjustments, the in-sample portion replays history to within solver
# tolerance and the out-of-sample portion is the model's own baseline.

root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "setup.R"))

db <- read_fixture()                       # history to 2019Q3
horizon <- c("2015Q1", "2024Q4")           # replay from 2015Q1, forecast to 2024Q4

# 1. Nowcast handover (fills the ragged edge; on the fixture this projects the
#    first couple of quarters past the data end). method = "arima" | "naive" | ...
cat("Nowcasting the handover variables ...\n")
hc <- nowcast_handover(db, h = 2L, method = "arima")
db <- splice_handover(db, hc)

# 2. Extend exogenous paths to the horizon end (carry-forward).
db <- extend_exogenous(db, end_quarter = horizon[2])

# 3. Solve.
cat("Solving baseline ", horizon[1], " -> ", horizon[2], " ...\n", sep = "")
base <- solve_martin(db, horizon = horizon, scenario = "baseline")

conv <- attr(base, "convergence")
cat(sprintf("Converged: %s (non-finite cells: %s)\n",
            conv$converged, conv$n_nonfinite))

# Headline forecast: four-quarter-ended growth/inflation + levels.
yoy <- function(p, v, q) {
  cur <- p$value[p$variable == v & p$quarter == q]
  prv <- p$value[p$variable == v & p$quarter == paste0(as.integer(substr(q,1,4)) - 1, substr(q,5,6))]
  if (length(cur) && length(prv)) 100 * (cur / prv - 1) else NA_real_
}
lvl <- function(p, v, q) { x <- p$value[p$variable == v & p$quarter == q]; if (length(x)) x else NA_real_ }

cat("\nHeadline baseline:\n")
cat(sprintf("%-8s %8s %8s %8s %8s\n", "quarter", "GDP%yoy", "CPI%yoy", "LUR", "cash%"))
for (q in c("2020Q4", "2022Q4", "2024Q4")) {
  cat(sprintf("%-8s %8.2f %8.2f %8.2f %8.2f\n",
              q, yoy(base, "Y", q), yoy(base, "P", q), lvl(base, "LUR", q), lvl(base, "NCR", q)))
}

saveRDS(base, file.path(root, "data", "baseline_projection.rds"))
cat("\nSaved baseline to data/baseline_projection.rds\n")
