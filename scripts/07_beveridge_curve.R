# 07 - Beveridge curve (reporting).
#
#   Rscript scripts/07_beveridge_curve.R
#
# The Beveridge curve is the inverse relationship between the unemployment rate
# and the job-vacancy rate. This pulls ABS job vacancies (6354.0) and the labour
# force (6202.0), builds the MARTIN database (which derives the unemployment rate
# LUR and the vacancy rate VR = 100 * JV / LF), and reports the curve.
#
# Reporting only: VR/JV are exogenous series in the database; nothing in the
# model solve depends on them. Needs network (and a FRED key for the rest of the
# live build, though only ABS labour data is required for the curve itself).

root <- tryCatch(here::here(), error = function(e) getwd())
suppressWarnings(suppressMessages(source(file.path(root, "setup.R"))))

# ---- build a live database that includes job vacancies (JV) ----------------
cat("Building live database (ABS/RBA/...; JV from ABS 6354.0) ...\n")
panel <- update_data(vintage = Sys.Date(), tolerate_failures = TRUE)
# Guarantee JV is in the panel even if a cached vintage predates the JV
# catalogue row (its catalogue 6354.0 may not have been fetched before).
if (!"A590698F" %in% panel$series_id) {
  jv <- fetch_job_vacancies()
  panel <- dplyr::bind_rows(panel, tibble::tibble(
    series_id = "A590698F", source = "abs",
    date = jv$date, value = jv$value, vintage = Sys.Date()))
}
db <- merge_with_fallback(to_martin_database(panel), read_fixture())
saveRDS(db, file.path(root, "data", "live_db.rds"))

# ---- the Beveridge curve ---------------------------------------------------
bc <- beveridge_curve(db)
cat(sprintf("\nBeveridge curve: %d quarters %s..%s | U-V correlation = %.2f%s\n",
            nrow(bc), bc$quarter[1], tail(bc$quarter, 1),
            attr(bc, "correlation"),
            if (attr(bc, "correlation") < 0) "  (downward-sloping, as expected)" else ""))

g <- function(q, col) { r <- bc[bc$quarter == q, ]; if (nrow(r)) r[[col]] else NA }
cat("\nNotable regimes (unemployment % / vacancy %):\n")
for (q in c("2008Q1", "2019Q4", "2020Q2", "2022Q2", "2023Q4",
            tail(bc$quarter, 1))) {
  if (q %in% bc$quarter)
    cat(sprintf("  %-7s  U = %4.1f   V = %4.2f\n", q, g(q, "unemployment_rate"),
                g(q, "vacancy_rate")))
}
cat("\nLast 6 quarters:\n")
print(as.data.frame(tail(bc, 6)), row.names = FALSE, digits = 3)

# ---- outputs: tidy data + a plot ------------------------------------------
out_csv <- file.path(root, "data", "beveridge_curve.csv")
write.csv(bc, out_csv, row.names = FALSE)

png_path <- file.path(root, "data", "beveridge_curve.png")
grDevices::png(png_path, width = 1000, height = 750, res = 110)
op <- graphics::par(mar = c(4.5, 4.5, 3, 1))
plot(bc$unemployment_rate, bc$vacancy_rate, type = "l", col = "grey75",
     xlab = "Unemployment rate (%)", ylab = "Vacancy rate (% of labour force)",
     main = sprintf("Australian Beveridge curve, %s-%s",
                    substr(bc$quarter[1], 1, 4),
                    substr(tail(bc$quarter, 1), 1, 4)))
graphics::points(bc$unemployment_rate, bc$vacancy_rate, pch = 20,
                 col = "grey55", cex = 0.6)
recent <- utils::tail(bc, 20)                       # last ~5 years in red
graphics::lines(recent$unemployment_rate, recent$vacancy_rate,
                col = "firebrick", lwd = 2)
ends <- recent[c(1, nrow(recent)), ]
graphics::points(ends$unemployment_rate, ends$vacancy_rate, pch = 19,
                 col = "firebrick")
graphics::text(ends$unemployment_rate, ends$vacancy_rate, labels = ends$quarter,
               pos = 4, cex = 0.8, col = "firebrick")
graphics::par(op); grDevices::dev.off()

cat(sprintf("\nSaved: %s\n       %s\n", out_csv, png_path))
