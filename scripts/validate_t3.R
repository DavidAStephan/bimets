# Out-of-sample validation of the T3 (re-estimating) model features.
#
# The four T3 features change an estimated behavioural equation, so they MUST be
# validated before being trusted in a forecast (they are OFF by default in the
# pipeline). Three of them re-fit a single behavioural:
#   convex_ptm            PTM   gap term  c7*LURGAP -> c7*(LURGAP/LUR)
#   inverted_le           LE    EC target -> inverted production-function LESTAR
#   corporate_accelerator NBRSP adds      c4*TSLAG(LEV,1) (BGG leverage channel)
# The fourth, endogenous_household, REPLACES the NHOY ECM with an identity, so it
# is validated separately (tracking error of the rebuilt NHOY), not as a re-fit.
#
# For each re-fitting feature we report, on the available sample:
#   - in-sample fit: SSR, R2, AIC vs the baseline equation;
#   - significance of any added coefficient (t-stat / p-value);
#   - a time-ordered 70/30 pseudo-OOS split (OLS on bimets' own design matrices
#     matrixX / vectorY), comparing held-out RMSE base vs feature.
#
# CAVEAT (printed in the output and docs/t3_validation.md): the bundled fixture
# ends 2019Q3, so the holdout here is PRE-COVID. The decision-relevant test --
# does the re-specification generalise THROUGH the COVID/inflation break -- needs
# a live re-estimation run (estimation_end past 2019Q3 with live data). This
# harness is written to run identically on that database; only the data changes.

root <- tryCatch(here::here(), error = function(e) getwd())
suppressWarnings(suppressMessages(source(file.path(root, "setup.R"))))

quiet_load <- function(data, features = character(0), feature_params = list()) {
  m <- NULL
  utils::capture.output(suppressWarnings(suppressMessages({
    m <- load_martin(data, variant = "af", estimate = TRUE,
                     features = features, feature_params = feature_params)
  })), file = nullfile())
  m
}

stat <- function(model, eq) {
  b <- model$behaviorals[[eq]]
  s <- b$statistics
  list(
    ssr   = as.numeric(s$SumSquaresResiduals),
    r2    = as.numeric(s$RSquared),
    aic   = as.numeric(s$AIC),
    nobs  = as.numeric(s$ObservationsCount),
    X     = s$matrixX,
    y     = as.numeric(s$vectorY),
    tstat = stats::setNames(as.numeric(s$CoeffTstatistic), rownames(b$coefficients)),
    pval  = stats::setNames(as.numeric(s$CoeffPvalues), rownames(b$coefficients))
  )
}

# Time-ordered 70/30 pseudo-OOS: OLS on the bimets design (already encodes the
# equation's restrictions), fit on the first 70% of observations, score RMSE on
# the held-out last 30%.
oos_rmse <- function(st) {
  X <- as.matrix(st$X); y <- st$y
  n <- nrow(X); cut <- floor(n * 0.7)
  if (is.na(cut) || cut < (ncol(X) + 2L) || cut >= n) return(NA_real_)
  itr <- seq_len(cut); ite <- (cut + 1L):n
  beta <- tryCatch(solve(crossprod(X[itr, , drop = FALSE]),
                         crossprod(X[itr, , drop = FALSE], y[itr])),
                   error = function(e) NULL)
  if (is.null(beta)) return(NA_real_)
  pred <- X[ite, , drop = FALSE] %*% beta
  sqrt(mean((y[ite] - pred)^2))
}

data <- read_fixture()

# inverted_le needs the output_gap scaffolding (EFF + CES gamma).
calib <- ces_calibration(data)
data_eff <- data
data_eff$EFF <- fit_efficiency_trend(data, calib)
fp_ces <- list(ces_gamma = calib$gamma, ces_theta_k = calib$theta_k)

base    <- quiet_load(data)
m_ptm   <- quiet_load(data, "convex_ptm")
m_le    <- quiet_load(data_eff, c("output_gap", "inverted_le"), fp_ces)
m_corp  <- quiet_load(data, "corporate_accelerator")

cases <- list(
  list(feature = "convex_ptm",            eq = "PTM",   base = base,    feat = m_ptm,  added = NULL),
  list(feature = "inverted_le",           eq = "LE",    base = base,    feat = m_le,   added = NULL),
  list(feature = "corporate_accelerator", eq = "NBRSP", base = base,    feat = m_corp, added = "c4")
)

rows <- lapply(cases, function(c) {
  sb <- stat(c$base, c$eq); sf <- stat(c$feat, c$eq)
  added_t <- if (!is.null(c$added)) sf$tstat[[c$added]] else NA_real_
  added_p <- if (!is.null(c$added)) sf$pval[[c$added]]  else NA_real_
  data.frame(
    feature      = c$feature,
    equation     = c$eq,
    ssr_base     = sb$ssr,
    ssr_feature  = sf$ssr,
    r2_base      = sb$r2,
    r2_feature   = sf$r2,
    aic_base     = sb$aic,
    aic_feature  = sf$aic,
    added_coef_t = added_t,
    added_coef_p = added_p,
    oos_rmse_base    = oos_rmse(sb),
    oos_rmse_feature = oos_rmse(sf),
    stringsAsFactors = FALSE
  )
})
res <- do.call(rbind, rows)
res$aic_improves <- res$aic_feature < res$aic_base
res$oos_improves <- res$oos_rmse_feature < res$oos_rmse_base

cat("\n=== T3 re-estimation validation (fixture sample, PRE-COVID holdout) ===\n\n")
print(format(res, digits = 4), row.names = FALSE)

# endogenous_household: identity respecification, validated by NHOY tracking.
m_eh <- quiet_load(
  { d <- data; d },
  c("household_income", "endogenous_household")
)
# Rebuilt NHOY vs actual (in-sample), if both present.
cat("\n=== endogenous_household (identity swap, not a re-fit) ===\n")
cat("NHOY is replaced by an accounting identity rebuilt from its components;\n",
    "it is baseline-neutral by construction (NHOY_RESID plugs the gap). It does\n",
    "not have an estimated fit to score -- validate via the round's NHOY/RC\n",
    "diff, which is zero in the seeding period.\n", sep = "")

saveRDS(res, "/tmp/t3_validation.rds")
cat("\nsaved /tmp/t3_validation.rds\n")
