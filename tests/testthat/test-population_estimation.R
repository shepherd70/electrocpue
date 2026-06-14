# Tests for the K-pass removal population estimators.
# Point estimates and SEs are cross-validated against FSA::removal()
# (a Suggests-only reference); edge cases and the dispatcher are tested
# directly.

# ---- Cross-validation against FSA --------------------------------------------

test_that("zippin_estimate matches FSA::removal(method = 'Zippin')", {
  skip_if_not_installed("FSA")
  cases <- list(c(45, 18, 7), c(38, 26, 12), c(50, 10),
                c(7, 5, 4, 3), c(100, 40, 15, 5), c(3, 2, 1))
  for (counts in cases) {
    mine <- zippin_estimate(counts, quiet = TRUE)
    ref  <- summary(FSA::removal(counts, method = "Zippin"), verbose = FALSE)
    expect_equal(mine$N,    ref["No", "Estimate"],   tolerance = 1e-6)
    expect_equal(mine$N_se, ref["No", "Std. Error"], tolerance = 1e-4)
    expect_equal(mine$p,    ref["p", "Estimate"],    tolerance = 1e-4)
    expect_equal(mine$p_se, ref["p", "Std. Error"],  tolerance = 1e-4)
  }
})

test_that("carle_strub_estimate matches FSA::removal(method = 'CarleStrub')", {
  skip_if_not_installed("FSA")
  cases <- list(c(45, 18, 7), c(38, 26, 12), c(50, 10),
                c(7, 5, 4, 3), c(100, 40, 15, 5), c(3, 2, 1))
  for (counts in cases) {
    mine <- carle_strub_estimate(counts, quiet = TRUE)
    ref  <- summary(FSA::removal(counts, method = "CarleStrub"), verbose = FALSE)
    expect_equal(mine$N,    ref["No", "Estimate"],   tolerance = 1e-6)
    expect_equal(mine$N_se, ref["No", "Std. Error"], tolerance = 1e-4)
    expect_equal(mine$p,    ref["p", "Estimate"],    tolerance = 1e-4)
    expect_equal(mine$p_se, ref["p", "Std. Error"],  tolerance = 1e-4)
  }
})

# ---- Result structure --------------------------------------------------------

test_that("estimate returns a one-row data frame with the documented columns", {
  res <- zippin_estimate(c(45, 18, 7), quiet = TRUE)
  expect_s3_class(res, "data.frame")
  expect_identical(nrow(res), 1L)
  expect_named(res, c("method", "n_passes", "catch_total", "N", "N_se",
                      "p", "p_se", "converged", "note"))
  expect_identical(res$n_passes, 3L)
  expect_identical(res$catch_total, 70)
  expect_true(res$converged)
  expect_identical(res$note, "ok")
})

# ---- Edge case: single pass --------------------------------------------------

test_that("single-pass series returns NA with a warning", {
  expect_warning(out <- zippin_estimate(c(50)), regexp = "[Ss]ingle-pass")
  expect_true(is.na(out$N))
  expect_false(out$converged)
  expect_identical(out$note, "single_pass")
})

test_that("quiet = TRUE suppresses the single-pass warning", {
  expect_no_warning(out <- zippin_estimate(c(50), quiet = TRUE))
  expect_true(is.na(out$N))
})

# ---- Edge case: zero catch ---------------------------------------------------

test_that("zero total catch returns N = 0 and converged = TRUE (no warning)", {
  expect_no_warning(out <- zippin_estimate(c(0, 0, 0), quiet = FALSE))
  expect_identical(out$N, 0)
  expect_identical(out$N_se, 0)
  expect_true(is.na(out$p))
  expect_true(out$converged)
  expect_identical(out$note, "zero_catch")
})

test_that("carle_strub also reports zero catch as N = 0", {
  out <- carle_strub_estimate(c(0, 0), quiet = TRUE)
  expect_identical(out$N, 0)
  expect_true(out$converged)
  expect_identical(out$note, "zero_catch")
})

# ---- Edge case: Zippin model failure -----------------------------------------

test_that("increasing catch triggers Zippin model failure -> NA + warning", {
  expect_warning(out <- zippin_estimate(c(10, 15, 20)),
                 regexp = "model failure")
  expect_true(is.na(out$N))
  expect_false(out$converged)
  expect_identical(out$note, "model_failure")
})

# ---- Edge case: Carle & Strub assumption violation ---------------------------

test_that("non-depleting catch is flagged assumption_violated, not ok", {
  expect_warning(out <- carle_strub_estimate(c(10, 15, 20)),
                 regexp = "does not decline")
  # The search still converges to a number, but it is flagged, not "ok".
  expect_true(out$converged)
  expect_false(is.na(out$N))
  expect_identical(out$note, "assumption_violated")
})

test_that("a flat (no depletion) two-pass series is flagged", {
  out <- carle_strub_estimate(c(8, 8), quiet = TRUE)
  expect_identical(out$note, "assumption_violated")
})

test_that("quiet = TRUE suppresses the assumption-violation warning", {
  expect_no_warning(out <- carle_strub_estimate(c(10, 15, 20), quiet = TRUE))
  expect_identical(out$note, "assumption_violated")
})

test_that("a genuinely depleting series keeps note = 'ok'", {
  out <- carle_strub_estimate(c(30, 25, 20), quiet = TRUE)
  expect_identical(out$note, "ok")
  expect_true(out$converged)
})

# ---- Dispatcher: auto --------------------------------------------------------

test_that("auto uses Zippin when its model is valid", {
  out <- estimate_population(c(45, 18, 7), method = "auto", quiet = TRUE)
  expect_identical(out$method, "zippin")
  expect_true(out$converged)
})

test_that("auto falls back to Carle & Strub on Zippin model failure", {
  expect_warning(
    out <- estimate_population(c(10, 15, 20), method = "auto"),
    regexp = "Carle"
  )
  expect_identical(out$method, "carle_strub")
  expect_true(out$converged)
  expect_false(is.na(out$N))
  # The fallback series is increasing, so the depletion assumption is
  # violated; the estimate is returned but flagged rather than "ok".
  expect_identical(out$note, "assumption_violated")
})

test_that("auto warns that the depletion assumption is violated for rising catch", {
  expect_warning(
    estimate_population(c(10, 15, 20), method = "auto"),
    regexp = "assumption is violated"
  )
})

test_that("auto returns NA for single-pass data without trying Carle & Strub", {
  expect_warning(
    out <- estimate_population(c(42), method = "auto"),
    regexp = "[Ss]ingle-pass"
  )
  expect_true(is.na(out$N))
  expect_identical(out$note, "single_pass")
})

test_that("auto fallback agrees with an explicit Carle & Strub call", {
  skip_if_not_installed("FSA")
  auto <- estimate_population(c(10, 15, 20), method = "auto", quiet = TRUE)
  cs   <- carle_strub_estimate(c(10, 15, 20), quiet = TRUE)
  expect_equal(auto$N, cs$N)
})

# ---- Input validation --------------------------------------------------------

test_that("non-numeric counts abort with a classed error", {
  expect_error(zippin_estimate(c("a", "b")), class = "cpue_estimation_error")
})

test_that("NA counts abort", {
  expect_error(zippin_estimate(c(10, NA, 3)), class = "cpue_estimation_error")
})

test_that("negative counts abort", {
  expect_error(zippin_estimate(c(10, -2, 1)), class = "cpue_estimation_error")
})

test_that("non-integer counts abort", {
  expect_error(zippin_estimate(c(10.5, 4, 1)), class = "cpue_estimation_error")
})

test_that("empty counts abort", {
  expect_error(zippin_estimate(numeric(0)), class = "cpue_estimation_error")
})

test_that("non-positive Carle & Strub priors abort", {
  expect_error(carle_strub_estimate(c(10, 5, 2), alpha = 0),
               class = "cpue_estimation_error")
  expect_error(carle_strub_estimate(c(10, 5, 2), beta = -1),
               class = "cpue_estimation_error")
})

# ---- Determinism / sanity ----------------------------------------------------

test_that("more depletion implies higher capture probability", {
  steep  <- zippin_estimate(c(80, 10, 2), quiet = TRUE)
  gentle <- zippin_estimate(c(30, 25, 20), quiet = TRUE)
  expect_gt(steep$p, gentle$p)
})
