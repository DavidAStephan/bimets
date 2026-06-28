# Tests for the lur_floor feature: a floor on the unemployment rate. The LUR
# behavioural solves a change, so a strong-demand forecast can push the level
# below any frictional minimum or negative. lur_floor renames the behavioural to
# LUR_RULE (preserving estimation + the residual handover) and makes LUR a
# floored identity via bimets IF> branches. It MUST stay off the default path:
# in sample the floor never binds, so the solve is bit-identical to baseline.

fix_or_skip <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  read_fixture()
}

coef_of <- function(model, eq) {
  co <- model$behaviorals[[eq]]$coefficients
  stats::setNames(as.numeric(co), rownames(co))
}

test_that("lur_floor renames LUR to LUR_RULE and adds a floored identity", {
  mt <- paste(apply_model_features(read_model_lines("af"), "lur_floor"),
              collapse = "\n")
  expect_true(grepl("BEHAVIORAL> LUR_RULE", mt, fixed = TRUE))
  expect_false(grepl("BEHAVIORAL> LUR\n", mt, fixed = TRUE))
  expect_equal(lengths(regmatches(mt, gregexpr("IDENTITY> LUR\n", mt))), 2L)
  expect_true(grepl("IF> LUR_RULE > 2.5", mt, fixed = TRUE))
  expect_true(grepl("IF> LUR_RULE <= 2.5", mt, fixed = TRUE))
  # The renamed rule keeps the change form and its (floored) LUR lags.
  expect_true(grepl("EQ> TSDELTA(LUR_RULE,1)", mt, fixed = TRUE))
  expect_true("LUR_RULE" %in% feature_new_vars("lur_floor"))
})

test_that("LUR_RULE inherits LUR's history and estimates identically", {
  data <- fix_or_skip()
  lur_base <- coef_of(load_martin(data), "LUR")
  m_floor  <- load_martin(data, features = "lur_floor")
  lur_rule <- coef_of(m_floor, "LUR_RULE")
  expect_equal(unname(lur_base), unname(lur_rule), tolerance = 1e-10)
  expect_null(m_floor$behaviorals[["LUR"]])   # LUR is now an identity
})

test_that("lur_floor is baseline-neutral in sample (floor does not bind)", {
  data <- fix_or_skip()
  base  <- solve_martin(data, NULL, horizon = c("2010Q1", "2018Q4"),
                        scenario = "base")
  floor <- solve_martin(data, NULL, horizon = c("2010Q1", "2018Q4"),
                        features = "lur_floor", scenario = "floor")
  for (v in c("LUR", "Y", "RC", "PTM", "NCR")) {
    b <- dplyr::filter(base,  variable == v)$value
    f <- dplyr::filter(floor, variable == v)$value
    expect_equal(f, b, tolerance = 1e-8, info = paste("lur_floor changed", v))
  }
})

test_that("lur_floor clamps the unemployment rate when it is pushed below", {
  data <- fix_or_skip()
  dbE  <- extend_exogenous(data, "2026Q4", "carry_all")
  qs   <- quarter_seq("2020Q1", "2026Q4")
  # a sustained negative add-factor drives unemployment well below the floor
  af <- adjustment_list(adjustment("LUR", horizon = qs,
          value = rep(-0.25, length(qs)),
          rationale = "stress test: force unemployment to the floor",
          tail = "zero"))
  unfloored <- solve_martin(dbE, af, horizon = c("2015Q1", "2026Q4"),
                            scenario = "unfloored")
  floored   <- solve_martin(dbE, af, horizon = c("2015Q1", "2026Q4"),
                            features = "lur_floor", scenario = "floored")
  lur_uf <- dplyr::filter(unfloored, variable == "LUR")$value
  lur_fl <- dplyr::filter(floored,   variable == "LUR")$value
  expect_lt(min(lur_uf), 2.5)              # unfloored breaches the floor
  expect_gte(min(lur_fl), 2.5 - 1e-6)      # floored never does
})
