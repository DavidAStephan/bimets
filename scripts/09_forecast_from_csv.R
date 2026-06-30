# 09 — Forecast from a CSV instead of downloading public data.
#
#   Rscript scripts/09_forecast_from_csv.R
#
# An offline / "bring your own data" alternative to the download pipeline
# (scripts/01_update_data.R -> to_martin_database()). You supply ONE CSV with a
# period column plus one column per MARTIN variable (header = the variable
# name), and read_csv_database() turns it into the bimets database that
# load_martin()/solve_martin() consume — no ABS/RBA/FRED API keys required.
#
# This demo builds the CSV template from the bundled fixture so it is fully
# reproducible; in practice you would point read_csv_database() at your own CSV.

root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "setup.R"))

# ---- 0. Produce a CSV template from the fixture ----------------------------
# database_to_csv() writes the exact format read_csv_database() expects, so the
# fixture doubles as a fill-in-the-blanks template (quarter col + 205 vars).
csv_path <- file.path(root, "data", "martin_data.csv")
dir.create(dirname(csv_path), showWarnings = FALSE, recursive = TRUE)
database_to_csv(read_fixture(), csv_path)
cat("Wrote a CSV template to ", csv_path, "\n", sep = "")
cat("  header: quarter, <one column per MARTIN variable>\n")

# ---- 1. Load the database straight from the CSV ----------------------------
cat("\nReading the database from CSV ...\n")
db <- read_csv_database(csv_path)               # messages report coverage
cat(sprintf("  loaded %d series (%d are model variables, %d unknown)\n",
            length(db), length(attr(db, "vars_supplied")),
            length(attr(db, "unknown_columns"))))

# Partial CSVs are fine: pass `fallback = read_fixture()` to fill any variable
# (or quarter) the CSV leaves blank. e.g.
#   db <- read_csv_database("my_partial.csv", fallback = read_fixture())

# ---- 2. Solve exactly as with any other database ---------------------------
horizon <- c("2010Q1", "2019Q3")
cat("\nSolving baseline ", horizon[1], " -> ", horizon[2], " ...\n", sep = "")
base <- solve_martin(db, horizon = horizon, scenario = "baseline_from_csv")
conv <- attr(base, "convergence")
cat(sprintf("Converged: %s (non-finite cells: %s)\n",
            conv$converged, conv$n_nonfinite))

g <- function(p, v, q) { x <- p$value[p$variable == v & p$quarter == q]; if (length(x)) x else NA_real_ }
cat("\nHeadline (from CSV-sourced data):\n")
cat(sprintf("%-8s %10s %8s %8s %8s\n", "quarter", "Y", "LUR", "P", "NCR"))
for (q in c("2015Q4", "2017Q4", "2019Q3")) {
  cat(sprintf("%-8s %10.1f %8.2f %8.2f %8.2f\n",
              q, g(base, "Y", q), g(base, "LUR", q), g(base, "P", q), g(base, "NCR", q)))
}

cat("\nThis is the same workflow as scripts/03 — only the data SOURCE differs",
    "\n(CSV instead of public downloads). Edit the CSV (or supply your own with",
    "\nthe same column names) and re-run to forecast off your data.\n")
