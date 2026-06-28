# 01 — Download data and build the MARTIN database.
#
#   Rscript scripts/01_update_data.R
#
# Fetches the live source panels (ABS / RBA / FRED / OECD / World Bank / BoM),
# maps them to MARTIN variables via the series catalogue, applies the
# transformations (splicing, Chow-Lin disaggregation, PIM accumulation,
# identities, state-space trends, deterministic dummies), and returns a named
# list of bimets TIMESERIES ready for load_martin() / solve_martin().
#
# Live fetching needs network access and (for FRED) an API key in FRED_API_KEY
# (see .Renviron.example). If the live path fails, this falls back to the frozen
# fixture so the script still produces a usable database offline.

root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "setup.R"))

build_live <- function() {
  panel <- update_data(vintage = Sys.Date())          # tidy panel, cached as parquet
  live  <- to_martin_database(panel)                   # -> named list of bimets ts
  merge_with_fallback(live, read_fixture())            # backfill history gaps
}

db <- tryCatch(
  build_live(),
  error = function(e) {
    message("Live data build failed (", conditionMessage(e),
            ");\n  falling back to the frozen fixture (extdata/martin_data_fixture.xlsx).")
    read_fixture()
  }
)

cat(sprintf("\nDatabase: %d variables\n", length(db)))
prov <- database_provenance(db)
if (!is.null(prov)) {
  cat("Provenance:\n")
  print(as.data.frame(table(prov$source_class)))
}

# Show the span of a few headline series.
endq <- function(ts) { tp <- stats::tsp(ts); y <- floor(tp[2] + 1e-9)
                       sprintf("%04dQ%d", y, round((tp[2] - y) * 4 + 1)) }
for (v in c("Y", "LUR", "P", "NCR")) {
  if (!is.null(db[[v]])) cat(sprintf("  %-6s ends %s\n", v, endq(db[[v]])))
}

# Persist for downstream scripts (optional).
out <- file.path(root, "data", "martin_database.rds")
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
saveRDS(db, out)
cat("\nSaved database to", out, "\n")
