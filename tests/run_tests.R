# Run the test suite against the flat MARTIN model.
#
#   Rscript tests/run_tests.R
#
# Sources setup.R (which loads all of R/ into the global environment), then
# runs every tests/testthat/test-*.R via testthat. Network-dependent data
# fetch tests skip themselves when offline.

root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "setup.R"))

library(testthat)
res <- test_dir(
  file.path(root, "tests", "testthat"),
  env = globalenv(),
  stop_on_failure = FALSE,
  reporter = "summary"
)

df <- as.data.frame(res)
cat(sprintf("\n==== totals: %d pass | %d fail | %d warn | %d skip ====\n",
            sum(df$passed), sum(df$failed), sum(df$warning), sum(df$skipped)))
if (sum(df$failed) > 0) quit(status = 1)
