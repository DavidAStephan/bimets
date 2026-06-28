# 02 — Estimate the model in bimets.
#
#   Rscript scripts/02_estimate.R
#
# load_martin() wraps bimets LOAD_MODEL -> LOAD_MODEL_DATA -> ESTIMATE. The
# MARTINMOD_AF.txt form has 95 BEHAVIORAL> equations; ESTIMATE re-fits their
# free coefficients on every load. "Frozen" (the default, estimation_end = NULL)
# estimates over the model file's embedded 2019Q3 sample, reproducing the
# published coefficients. Pass estimation_end = "yyyyQq" to re-fit on a later
# sample (this crosses the COVID break and changes the coefficients — opt in
# deliberately).

root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "setup.R"))

db <- read_fixture()

cat("Estimating MARTIN (frozen, 2019Q3 sample) ...\n")
model <- load_martin(db, variant = "af", estimate = TRUE)   # estimation_end = NULL

eqs <- names(model$behaviorals)
cat(sprintf("Behavioural equations estimated: %d\n\n", length(eqs)))

# Show fitted coefficients for a few headline equations.
show_coef <- function(eq) {
  b <- model$behaviorals[[eq]]
  co <- tryCatch(as.numeric(b$coefficients), error = function(e) NULL)
  se <- tryCatch(b$statistics$StandardErrorRegression, error = function(e) NA)
  if (is.null(co)) { cat(sprintf("  %-6s (no coefficients)\n", eq)); return(invisible()) }
  cat(sprintf("  %-6s coefs: %s | regression SE: %.4g\n",
              eq, paste(sprintf("%.4f", co), collapse = ", "), se))
}
cat("Selected estimated equations:\n")
for (eq in intersect(c("PTM", "RC", "LUR", "PW", "NCR_RULE", "NCR"), eqs)) show_coef(eq)

# Residual standard deviations drive the stochastic bands (script 06).
res_sd <- vapply(eqs, function(eq) {
  r <- as.numeric(model$behaviorals[[eq]]$residuals)
  r <- r[is.finite(r)]; if (length(r) < 2) NA_real_ else stats::sd(r)
}, numeric(1))
res_sd <- sort(res_sd[is.finite(res_sd)], decreasing = TRUE)
cat("\nLargest residual SDs (equation error scale):\n")
print(utils::head(round(res_sd, 4), 8))

cat("\nTo re-estimate over a later sample (crosses COVID):\n")
cat('  load_martin(db, estimation_end = "2024Q4")\n')
