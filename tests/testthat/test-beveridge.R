# beveridge_curve() is reporting-only: it pairs the unemployment rate (LUR) and
# the job-vacancy rate (VR) from a database. These tests use synthetic series so
# they need no live data.

mk <- function(v, y = 2000, p = 1) bimets::TIMESERIES(v, START = c(y, p), FREQ = 4)

test_that("beveridge_curve pairs LUR and VR in time order with a correlation", {
  # downward-sloping: unemployment up, vacancies down
  db <- list(LUR = mk(c(5, 5.5, 6, 6.5, 7)),
             VR  = mk(c(3, 2.6, 2.2, 1.8, 1.4)),
             Y   = mk(rep(1, 5)))
  bc <- beveridge_curve(db)
  expect_setequal(names(bc), c("quarter", "unemployment_rate", "vacancy_rate"))
  expect_equal(nrow(bc), 5L)
  expect_equal(bc$quarter[1], "2000Q1")
  expect_lt(attr(bc, "correlation"), 0)        # a healthy Beveridge curve slopes down
})

test_that("beveridge_curve errors clearly when LUR or VR is absent", {
  expect_error(beveridge_curve(list(LUR = mk(1:4))), "VR")
  expect_error(beveridge_curve(list(VR  = mk(1:4))), "LUR")
})

test_that("beveridge_curve drops non-finite quarters and honours from/to", {
  db <- list(LUR = mk(c(5, NA, 6, 7)), VR = mk(c(3, 2.5, NA, 1.5)))
  bc <- beveridge_curve(db)
  expect_equal(nrow(bc), 2L)                   # Q2 (LUR NA) and Q3 (VR NA) dropped
  expect_equal(bc$quarter, c("2000Q1", "2000Q4"))

  full <- list(LUR = mk(c(5, 5.5, 6, 6.5)), VR = mk(c(3, 2.6, 2.2, 1.8)))
  win <- beveridge_curve(full, from = "2000Q2", to = "2000Q3")
  expect_equal(win$quarter, c("2000Q2", "2000Q3"))
})
