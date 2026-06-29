# Tests for the standard impulse-response battery (standard_irfs()).
# Runs real solves on the bundled fixture, so guarded on bimets + fixture.
# Asserts (a) every shock converges and (b) the headline channels move with
# the economically-correct sign — the point of the battery is to confirm the
# model's dynamic properties, so the signs are part of the contract.

irf_fixture <- function() {
  skip_if_not_installed("bimets")
  skip_if_not(file.exists(martin_data_fixture()), "MARTINDATA fixture missing")
  read_fixture()
}

# Pull one (scenario, variable, offset) deviation out of the tidy table.
dev_at <- function(irf, scenario, variable, offset) {
  r <- irf[irf$scenario == scenario & irf$variable == variable &
             irf$offset_q == offset, , drop = FALSE]
  if (nrow(r) == 0L) return(NA_real_)
  r$deviation[1]
}

test_that("standard_irf_specs() covers the four standard shocks", {
  specs <- standard_irf_specs()
  expect_setequal(
    names(specs),
    c("monetary_100bp", "govcons_1pc", "commodity_10pc", "rer_10pc"))
  # The small behavioural shocks respect the DEFAULT per-units ceilings ...
  expect_silent(validate_adjustment_bounds(
    adjustment(equation = specs$monetary_100bp$equation,
               horizon = "2015Q1", value = specs$monetary_100bp$value,
               rationale = "t", tail = "zero")))
  expect_silent(validate_adjustment_bounds(
    adjustment(equation = specs$govcons_1pc$equation,
               horizon = "2015Q1", value = specs$govcons_1pc$value,
               rationale = "t", tail = "zero")))
  # ... while the +10% world-price / FX shocks exceed the default log_diff
  # ceiling (0.02) and so must carry a ceiling override that admits them.
  expect_true(specs$commodity_10pc$value > 0.02)
  expect_true(specs$rer_10pc$value > 0.02)
  for (k in c("commodity_10pc", "rer_10pc")) {
    expect_true(!is.null(specs[[k]]$ceiling))
    expect_true(specs[[k]]$value <= specs[[k]]$ceiling$log_diff)
  }
})

test_that("the standard IRF battery solves and moves with the right signs", {
  data <- irf_fixture()
  horizon     <- c("2008Q1", "2014Q4")
  shock_start <- "2010Q1"
  offsets     <- c(0L, 1L, 4L, 8L)

  irf <- suppressMessages(suppressWarnings(
    standard_irfs(data, horizon = horizon, shock_start = shock_start,
                  offsets = offsets, progress = FALSE)
  ))

  # (a) Every shock converged.
  conv <- attr(irf, "convergence")
  for (k in names(conv)) {
    expect_true(isTRUE(conv[[k]]$converged),
                info = sprintf("scenario %s did not converge", k))
  }

  # (b) Model-property signs ------------------------------------------------

  # Monetary +100bp: cash rate up on impact; activity weaker and unemployment
  # higher with a lag; prices lower.
  expect_gt(dev_at(irf, "monetary_100bp", "NCR", 0), 0)
  expect_lt(dev_at(irf, "monetary_100bp", "Y",   4), 0)
  expect_gt(dev_at(irf, "monetary_100bp", "LUR", 8), 0)

  # +1% government consumption: GDP higher on impact (a demand component).
  expect_gt(dev_at(irf, "govcons_1pc", "Y", 0), 0)

  # Permanent +10% commodity prices: terms of trade rise.
  expect_gt(dev_at(irf, "commodity_10pc", "TOT", 4), 0)

  # +10% real appreciation for one quarter: RTWI ~ +10% on impact, then
  # mean-reverts back toward baseline.
  expect_gt(dev_at(irf, "rer_10pc", "RTWI", 0), 8)
  expect_lt(dev_at(irf, "rer_10pc", "RTWI", 0), 12)
  expect_lt(abs(dev_at(irf, "rer_10pc", "RTWI", 8)),
            abs(dev_at(irf, "rer_10pc", "RTWI", 0)))
})
