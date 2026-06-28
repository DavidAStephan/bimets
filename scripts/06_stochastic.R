# 06 — Stochastic simulation (uncertainty bands).
#
#   Rscript scripts/06_stochastic.R
#
# solve_martin_stochastic() propagates equation-error uncertainty into the
# projection. When bimets STOCHSIMULATE is available, each behavioural
# equation's disturbance is drawn n_draws times at its own regression standard
# error and the model is re-solved per replica; bands are the empirical
# 2.5%/97.5% quantiles. The central path equals the deterministic solve_martin()
# baseline. (A coefficient-free add-factor-perturbation fallback is used if
# STOCHSIMULATE is absent.)

root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "setup.R"))

db <- read_fixture()
horizon <- c("2015Q1", "2023Q4")
db <- splice_handover(db, nowcast_handover(db, h = 2L, method = "naive"))
db <- extend_exogenous(db, end_quarter = horizon[2])

cat("Stochastic simulation (this re-solves the model many times) ...\n")
bands <- solve_martin_stochastic(
  db, horizon = horizon, n_draws = 200L,
  band_start = "2020Q1",                   # widen bands only over the forecast
  scenario = "baseline"
)
cat("band method:", attr(bands, "band_method"),
    "| draws:", attr(bands, "n_draws"), "\n")

show_band <- function(v) {
  cat(sprintf("\n%s — central [2.5%%, 97.5%%]:\n", v))
  for (q in c("2020Q4", "2022Q4", "2023Q4")) {
    r <- bands[bands$variable == v & bands$quarter == q, ]
    if (nrow(r)) cat(sprintf("  %-8s %8.2f  [%7.2f, %7.2f]\n",
                             q, r$value, r$lower, r$upper))
  }
}
show_band("LUR")
show_band("P")
show_band("NCR")

saveRDS(bands, file.path(root, "data", "stochastic_bands.rds"))
cat("\nSaved bands to data/stochastic_bands.rds\n")
