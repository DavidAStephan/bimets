# Re-estimate MARTIN to the latest quarter with COVID lockdown dummies.
#
#   Rscript scripts/reestimate_covid.R
#
# Re-estimating MARTIN across the COVID break degrades the behavioural
# equations (see docs/equation_diagnostics.md and the audit). The 2020-21
# lockdown quarters are extreme one-off outliers that distort OLS. This script
# adds *targeted pulse dummies* (=1 in one quarter, 0 elsewhere) to absorb them,
# then re-estimates and reports the effect.
#
# Design (see docs/covid_dummies.md):
#   - Candidate lockdown quarters: 2020Q1-2020Q4, 2021Q3, 2021Q4.
#   - A dummy is added to an equation only where THAT equation has a
#     standardised residual |z| >= 2.5 in that quarter (targeted, not blanket).
#   - The 2022 inflation-surge quarters are deliberately NOT dummied: that was a
#     genuine economic development, not a measurement outlier, and the model
#     should fit it.
#
# the model files in extdata/model_af/ are NOT modified (the frozen default stays
# bit-identical to the bimets reference); the dummies are injected at runtime.

root <- tryCatch(here::here(), error = function(e) getwd())
suppressWarnings(suppressMessages(source(file.path(root, "setup.R"))))

EST_END <- "2026Q1"                                    # latest complete quarter
LOCK <- c("2020Q1","2020Q2","2020Q3","2020Q4","2021Q3","2021Q4")
ZTHRESH <- 2.5

# --- database: reuse the cached live build, else fetch fresh (needs FRED key) -
db_path <- file.path(root, "data", "live_db.rds")
if (file.exists(db_path)) {
  db0 <- readRDS(db_path)
} else {
  message("Building live database (update_data); needs network + FRED_API_KEY ...")
  db0 <- merge_with_fallback(to_martin_database(
    update_data(vintage = Sys.Date(), tolerate_failures = TRUE)), read_fixture())
  dir.create(dirname(db_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(db0, db_path)
}
db <- suppressWarnings(extend_exogenous(db0, "2030Q4", "carry_all"))

# --- helpers ---------------------------------------------------------------
dvar <- function(q) paste0("DCOV", substr(q, 1, 4), "Q", substr(q, 6, 6))
estd <- function(lines, data, ee) {
  if (!is.null(ee)) lines <- rewrite_tsrange_end(lines, ee)   # the key step
  .suppress_bimets_version_warning({ invisible(capture.output({
    m <- bimets::LOAD_MODEL(modelText = paste(lines, collapse = "\n"), quietly = TRUE)
    m <- suppressWarnings(bimets::LOAD_MODEL_DATA(m, data, quietly = TRUE))
    m <- suppressWarnings(suppressMessages(bimets::ESTIMATE(m, quietly = TRUE)))
  })) }); m
}
qlab <- function(ts) { tp <- stats::tsp(ts); y0 <- floor(tp[1] + 1e-9)
  q0 <- round((tp[1] - y0) * 4 + 1); n <- length(as.numeric(ts))
  vapply(0:(n - 1), function(k) { a <- y0 * 4 + (q0 - 1) + k
    sprintf("%04dQ%d", a %/% 4, a %% 4 + 1) }, character(1)) }
is_estimated <- function(m, eq) {
  t <- suppressWarnings(as.numeric(m$behaviorals[[eq]]$statistics$CoeffTstatistic))
  any(!is.na(t) & abs(t) < 1e6)
}
block_range <- function(L, nm) { st <- grep(paste0("^BEHAVIORAL> ", nm, "$"), L)
  r <- grep("^(BEHAVIORAL>|IDENTITY>|COMMENT>)", L); c(st, min(r[r > st]) - 1) }
inject1 <- function(L, eq, qs) {                       # add +cK*DCOV terms to one equation
  dv <- vapply(qs, dvar, character(1)); r <- block_range(L, eq); blk <- L[r[1]:r[2]]
  ci <- grep("^COEFF>", blk)
  mx <- max(as.integer(sub("c", "", regmatches(blk[ci], gregexpr("c[0-9]+", blk[ci]))[[1]])))
  nc <- paste0("c", mx + seq_along(dv))
  term <- paste0("                      ", paste0("+", nc, "*", dv, collapse = ""))
  blk <- append(blk, term, after = ci - 1); ci2 <- grep("^COEFF>", blk)
  blk[ci2] <- paste(blk[ci2], paste(nc, collapse = " "))
  c(L[seq_len(r[1] - 1)], blk, L[(r[2] + 1):length(L)])
}
build <- function(lines, map) { for (e in names(map)) lines <- inject1(lines, e, map[[e]]); lines }

lines <- read_model_lines("af")

# --- 1. re-estimate (no dummies) and find each equation's lockdown outliers --
cat("Re-estimating to", EST_END, "(no dummies) and detecting lockdown outliers ...\n")
mND <- estd(lines, db, EST_END)
dmap <- list()
for (eq in names(mND$behaviorals)) {
  if (!is_estimated(mND, eq)) next
  r <- mND$behaviorals[[eq]]$residuals
  ser <- as.numeric(mND$behaviorals[[eq]]$statistics$StandardErrorRegression)
  if (is.null(r) || !is.finite(ser) || ser <= 0) next
  z <- as.numeric(r) / ser; ql <- qlab(r)
  hit <- LOCK[vapply(LOCK, function(q) { i <- match(q, ql)
    !is.na(i) && is.finite(z[i]) && abs(z[i]) >= ZTHRESH }, logical(1))]
  if (length(hit)) dmap[[eq]] <- hit
}
allq <- sort(unique(unlist(dmap)))
cat(sprintf("  lockdown dummies in use: %s\n  equations dummied: %d\n",
            paste(allq, collapse = ", "), length(dmap)))

# --- 2. seed the dummy series ---------------------------------------------
tmpl <- db[["Y"]]; tp <- stats::tsp(tmpl); y0 <- floor(tp[1] + 1e-9)
q0 <- round((tp[1] - y0) * 4 + 1); n <- length(as.numeric(tmpl))
for (q in allq) { yy <- as.integer(substr(q, 1, 4)); qq <- as.integer(substr(q, 6, 6))
  idx <- (yy * 4 + (qq - 1)) - (y0 * 4 + (q0 - 1)) + 1
  v <- rep(0, n); if (idx >= 1 && idx <= n) v[idx] <- 1
  db[[dvar(q)]] <- bimets::TIMESERIES(v, START = c(y0, q0), FREQ = 4) }

# --- 3. re-estimate with dummies (drop any equation that still goes singular) -
dropped <- character(0)
repeat {
  res <- tryCatch(estd(build(lines, dmap), db, EST_END),
                  error = function(e) conditionMessage(e))
  if (!is.character(res)) { mD <- res; break }
  eq <- sub('.*Behavioral: "([^"]+)".*', '\\1', res)
  if (eq == res || eq %in% dropped) { stop("unresolved singularity: ", substr(res, 1, 160)) }
  cat("  dropping dummies from singular equation:", eq, "\n")
  dropped <- c(dropped, eq); dmap[[eq]] <- NULL
}
saveRDS(list(model = mD, map = dmap, est_end = EST_END),
        file.path(root, "data", "model_reestimated_covid.rds"))

# --- 4. report -------------------------------------------------------------
cc <- function(m, eq, i) as.numeric(m$behaviorals[[eq]]$coefficients)[i]
ct <- function(m, eq, i) suppressWarnings(as.numeric(m$behaviorals[[eq]]$statistics$CoeffTstatistic))[i]
r2 <- function(m, eq) as.numeric(m$behaviorals[[eq]]$statistics$RSquared)
key <- list(c("RC","2","EC"), c("LE","3","dyn"), c("M","2","EC"), c("XS","2","EC"),
            c("XM","2","EC"), c("LUR","2","Okun"), c("PTM","7","gap"),
            c("PW","2","gap"), c("GC","2","EC"))
cat(sprintf("\n%-16s %-22s %-22s %s\n", "eq:coef(role)",
            "no dummies", "with dummies", "dummies"))
for (x in key) { eq <- x[1]; i <- as.integer(x[2])
  dq <- if (!is.null(dmap[[eq]])) paste(substr(dmap[[eq]], 3, 99), collapse = "/") else "(none)"
  cat(sprintf("%-5s c%-2s(%-4s) % .4g [t% .1f]   % .4g [t% .1f]   R2 %.2f->%.2f  %s\n",
      eq, x[2], x[3], cc(mND, eq, i), ct(mND, eq, i),
      cc(mD, eq, i), ct(mD, eq, i), r2(mND, eq), r2(mD, eq), dq)) }
cat("\nSaved data/model_reestimated_covid.rds\n")
