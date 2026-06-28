# Beveridge curve — reporting only.
#
# The Beveridge curve is the (downward-sloping) relationship between the
# unemployment rate and the job-vacancy rate. This is a *reporting* view: it
# reads the unemployment rate (LUR) and vacancy rate (VR) out of a MARTIN
# database and returns them aligned for plotting. It does NOT add an equation
# or feed into solve_martin() — VR is exogenous reporting, nothing depends on it.

#' Beveridge-curve data: unemployment rate vs job-vacancy rate
#'
#' Pure reporting. Pairs the unemployment rate (`LUR`) with the job-vacancy rate
#' (`VR`, derived as `100 * JV / LF`) from a MARTIN database, quarter by quarter,
#' for plotting the Beveridge curve.
#'
#' Both series come from a *live* database — `update_data()` ->
#' `to_martin_database()` pulls ABS job vacancies (`JV`) and derives `VR`. The
#' bundled fixture predates this and has no vacancies, so build a live database
#' first.
#'
#' @param database A MARTIN database (named list of `bimets::TIMESERIES`)
#'   containing `LUR` and `VR`.
#' @param from,to Optional inclusive `"yyyyQq"` bounds.
#' @return A tibble `(quarter, unemployment_rate, vacancy_rate)` for the quarters
#'   where both are finite, in time order. Carries a `correlation` attribute (the
#'   in-sample U-V correlation; a healthy Beveridge curve is negative).
#' @export
beveridge_curve <- function(database, from = NULL, to = NULL) {
  need <- c("LUR", "VR")
  miss <- need[!need %in% names(database)]
  if (length(miss)) {
    stop("database is missing ", paste(miss, collapse = " and "),
         ". Build a live database (update_data -> to_martin_database); the ",
         "bundled fixture has no job vacancies.", call. = FALSE)
  }

  as_df <- function(ts, col) {
    t <- as.numeric(stats::time(ts)); y <- floor(t + 1e-9)
    q <- round((t - y) * 4 + 1)
    out <- data.frame(quarter = sprintf("%04dQ%d", y, q),
                      v = as.numeric(ts), stringsAsFactors = FALSE)
    names(out)[2] <- col
    out
  }
  df <- merge(as_df(database$LUR, "unemployment_rate"),
              as_df(database$VR, "vacancy_rate"), by = "quarter")
  df <- df[is.finite(df$unemployment_rate) & is.finite(df$vacancy_rate), ,
           drop = FALSE]
  # time order ("yyyyQq" sorts correctly lexically)
  df <- df[order(df$quarter), , drop = FALSE]
  if (!is.null(from)) df <- df[df$quarter >= from, , drop = FALSE]
  if (!is.null(to))   df <- df[df$quarter <= to, , drop = FALSE]

  out <- tibble::as_tibble(df)
  attr(out, "correlation") <- if (nrow(out) > 2L) {
    stats::cor(out$unemployment_rate, out$vacancy_rate)
  } else NA_real_
  out
}
