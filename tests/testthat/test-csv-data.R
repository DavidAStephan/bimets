# Tests for the CSV data source: read_csv_database() / database_to_csv() /
# martin_model_variables(). The pure period/parse helpers run without bimets;
# the round-trip and validation tests are guarded on bimets + the fixture.

# ---- pure helpers (no bimets needed) ---------------------------------------

test_that("parse_period_vector handles yyyyQq, lowercase, and ISO dates", {
  qi <- parse_period_vector(c("2019Q3", "2019q4", "2020-01-01", "2020-04-15"))
  # 2019Q3 -> 2019*4+2 ; 2019Q4 -> +3 ; 2020Q1 -> 2020*4 ; 2020Q2 -> +1
  expect_equal(qi, c(2019 * 4 + 2, 2019 * 4 + 3, 2020 * 4 + 0, 2020 * 4 + 1))
})

test_that("parse_period_vector returns NA for unparseable values", {
  qi <- parse_period_vector(c("2019Q3", "garbage", "2019Q9"))
  expect_false(is.na(qi[1]))
  expect_true(is.na(qi[2]))
  expect_true(is.na(qi[3]))  # Q9 is not a valid quarter
})

test_that("quarter_label round-trips parse_period_vector", {
  labs <- c("1991Q1", "2005Q4", "2019Q3")
  expect_equal(quarter_label(parse_period_vector(labs)), labs)
  iso <- quarter_label(parse_period_vector(labs), "date")
  expect_equal(iso, c("1991-01-01", "2005-10-01", "2019-07-01"))
})

test_that("coerce_numeric tolerates thousands commas and blanks", {
  expect_equal(coerce_numeric(c("1,234.5", "", "10")), c(1234.5, NA, 10))
})

test_that("detect_period_column prefers known names then first column", {
  expect_equal(detect_period_column(c("Dates", "RC", "Y")), "Dates")
  expect_equal(detect_period_column(c("quarter", "RC")), "quarter")
  expect_equal(suppressMessages(detect_period_column(c("RC", "Y"))), "RC")
})

# ---- bimets-backed behaviour -----------------------------------------------

csv_fixture_db <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  read_fixture()
}

# Compare two bimets quarterly series on the quarters they share.
max_common_diff <- function(a, b) {
  la <- ts_to_labelled(a)
  lb <- ts_to_labelled(b)
  va <- stats::setNames(la$values, la$qi)
  vb <- stats::setNames(lb$values, lb$qi)
  common <- intersect(names(va), names(vb))
  d <- va[common] - vb[common]
  max(abs(d[is.finite(d)]))
}

test_that("martin_model_variables returns the model's endo + exo names", {
  skip_if_not_installed("bimets")
  v <- martin_model_variables("af")
  expect_true(length(v) > 150)
  expect_true(all(c("Y", "RC", "NCR", "WPCOM", "RTWI", "GC") %in% v))
  expect_false(anyDuplicated(v) > 0)
})

test_that("martin_model_variables(which=) splits endogenous and exogenous", {
  skip_if_not_installed("bimets")
  all <- martin_model_variables("af", "all")
  en  <- martin_model_variables("af", "endogenous")
  ex  <- martin_model_variables("af", "exogenous")
  expect_setequal(union(en, ex), all)
  expect_length(intersect(en, ex), 0L)
  expect_true(length(en) > length(ex))
  expect_true(all(c("Y", "RC", "NCR") %in% en))   # solved variables
})

test_that("database_to_csv -> read_csv_database round-trips the fixture", {
  fx  <- csv_fixture_db()
  tmp <- tempfile(fileext = ".csv")
  database_to_csv(fx, tmp)

  db <- suppressMessages(read_csv_database(tmp))
  # Every fixture variable comes back, and they are all known model vars.
  expect_setequal(names(db), names(fx))
  expect_length(attr(db, "unknown_columns"), 0L)
  # Values are identical on the quarters each series covers.
  for (v in c("Y", "RC", "NCR", "LUR", "WPCOM", "RTWI", "P")) {
    expect_lt(max_common_diff(fx[[v]], db[[v]]), 1e-9)
  }
})

test_that("read_csv_database flags unknown columns but still loads them", {
  skip_if_not_installed("bimets")
  tmp <- tempfile(fileext = ".csv")
  writeLines(c("quarter,RC,NOT_A_VAR",
               "2010Q1,100,1",
               "2010Q2,101,2"), tmp)
  db <- suppressMessages(read_csv_database(tmp))
  expect_true("RC" %in% names(db))
  expect_true("NOT_A_VAR" %in% names(db))             # loaded anyway
  expect_equal(attr(db, "unknown_columns"), "NOT_A_VAR")
  expect_true("RC" %in% attr(db, "vars_supplied"))
})

test_that("read_csv_database errors on duplicate or unparseable periods", {
  skip_if_not_installed("bimets")
  dup <- tempfile(fileext = ".csv")
  writeLines(c("quarter,RC", "2010Q1,1", "2010Q1,2"), dup)
  expect_error(read_csv_database(dup), "Duplicate periods")

  bad <- tempfile(fileext = ".csv")
  writeLines(c("quarter,RC", "not-a-quarter,1"), bad)
  expect_error(read_csv_database(bad), "Could not parse")
})

test_that("fallback fills variables the CSV omits", {
  fx  <- csv_fixture_db()
  tmp <- tempfile(fileext = ".csv")
  # A CSV with only RC; everything else should come from the fixture.
  database_to_csv(fx["RC"], tmp)
  db <- suppressMessages(read_csv_database(tmp, fallback = fx))
  expect_true(all(c("RC", "NCR", "Y", "WPCOM") %in% names(db)))
  # NCR (absent from the CSV) matches the fixture it was filled from.
  expect_lt(max_common_diff(db[["NCR"]], fx[["NCR"]]), 1e-9)
})
