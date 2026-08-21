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
                      "N_lwr", "N_upr", "p", "p_se", "converged",
                      "identifiable", "note"))
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

test_that("profile interval includes a p = 1 boundary estimate", {
  for (estimator in list(zippin_estimate, carle_strub_estimate)) {
    for (counts in list(c(26, 0), c(26, 0, 0), c(26, 0, 0, 0))) {
      out <- estimator(counts, quiet = TRUE)
      expect_equal(out$p, 1)
      expect_equal(out$N, 26)
      expect_equal(out$N_lwr, 26)
      expect_lte(out$N_lwr, out$N)
      expect_gte(out$N_upr, out$N)
    }
  }
})

test_that("profile intervals contain converged estimates across a grid", {
  cases <- unlist(lapply(2:40, function(first) {
    lapply(0:min(first - 1L, 12L), function(later) c(first, later))
  }), recursive = FALSE)

  estimators <- list(zippin = zippin_estimate, carle_strub = carle_strub_estimate)
  for (estimator_name in names(estimators)) {
    for (counts in cases) {
      out <- estimators[[estimator_name]](counts, quiet = TRUE)
      if (isTRUE(out$converged)) {
        case_info <- paste(estimator_name, "counts =",
                           paste(counts, collapse = ","))
        expect_true(out$N_lwr <= out$N, info = case_info)
        expect_true(out$N_upr >= out$N, info = case_info)
      }
    }
  }
})

test_that("constant-memory profile search matches exhaustive integer search", {
  exhaustive_profile <- function(counts, level = 0.95, cap_mult = 50) {
    k <- length(counts)
    total <- sum(counts)
    removed <- c(0, cumsum(counts)[-k])
    weighted_removed <- sum(removed)
    cap <- floor(max(total * cap_mult, total + 300))
    candidates <- seq.int(total, cap)
    denom <- k * candidates - weighted_removed
    ok <- denom >= total

    term <- rowSums(vapply(
      seq_len(k),
      function(i) {
        lgamma(candidates - removed[i] + 1) -
          lgamma(candidates - removed[i] - counts[i] + 1)
      },
      numeric(length(candidates))
    ))
    ll <- rep(-Inf, length(candidates))
    boundary <- ok & denom == total
    interior <- ok & denom > total
    ll[boundary] <- term[boundary]
    phat <- total / denom[interior]
    ll[interior] <- term[interior] + total * log(phat) +
      (denom[interior] - total) * log1p(-phat)

    accepted <- 2 * (max(ll) - ll) <= stats::qchisq(level, 1)
    upper <- max(candidates[accepted])
    list(
      lwr = min(candidates[accepted]),
      upr = upper,
      identifiable = upper < cap
    )
  }

  cases <- list(
    c(26, 0), c(45, 18, 7), c(38, 26, 12), c(8, 8),
    c(7, 5, 4, 3), c(100, 40, 15, 5), c(3, 2, 1)
  )
  for (counts in cases) {
    expect_equal(
      electrocpue:::.profile_ci_N(counts),
      exhaustive_profile(counts),
      info = paste("counts =", paste(counts, collapse = ","))
    )
  }
})

test_that("profile search handles very large catches without a candidate grid", {
  interval <- electrocpue:::.profile_ci_N(c(10000000, 0))

  expect_identical(interval$lwr, 10000000)
  expect_gte(interval$upr, interval$lwr)
  expect_true(interval$identifiable)
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

test_that("an interior catch spike is flagged, not just the endpoints", {
  # Last pass (9) is below the first (10), so an endpoint-only test would
  # pass it; but pass 2 spikes to 30, and the first pass should catch the
  # most under depletion, so the all-passes check flags it.
  out <- carle_strub_estimate(c(10, 30, 9), quiet = TRUE)
  expect_true(out$converged)
  expect_identical(out$note, "assumption_violated")
})

test_that("a first-pass-dominant series with mild interior noise stays ok", {
  # Pass 3 (20) slightly exceeds pass 2 (18), but the first pass is the
  # maximum and the series declines overall: genuine depletion, not flagged.
  out <- carle_strub_estimate(c(45, 18, 20, 7), quiet = TRUE)
  expect_identical(out$note, "ok")
})

test_that("zippin flags a non-depleting series it still converges on", {
  # Zippin converges on a flat series (N is numeric), but it does not
  # deplete, so it must carry the same flag Carle & Strub would apply.
  out <- zippin_estimate(c(8, 8), quiet = TRUE)
  expect_true(out$converged)
  expect_false(is.na(out$N))
  expect_identical(out$note, "assumption_violated")
})

test_that("an extreme non-depleting series fails to converge rather than flagging", {
  # The integer search runs away on a violently increasing series and is
  # reported as a non-convergence (NA) -- the documented edge of the flag.
  out <- carle_strub_estimate(c(5, 9999), quiet = TRUE)
  expect_identical(out$note, "no_convergence")
  expect_true(is.na(out$N))
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

test_that("auto flags a non-depleting series even when Zippin converges", {
  # Regression: the flat series c(8, 8) makes Zippin converge, so auto
  # returned it before the depletion check ever ran (note = "ok"). The flag
  # must survive the Zippin-wins path, with a warning.
  expect_warning(
    out <- estimate_population(c(8, 8), method = "auto"),
    regexp = "assumption is violated"
  )
  expect_identical(out$method, "zippin")
  expect_true(out$converged)
  expect_false(is.na(out$N))
  expect_identical(out$note, "assumption_violated")
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

test_that("non-finite counts abort", {
  expect_error(zippin_estimate(c(10, Inf, 3)), class = "cpue_estimation_error")
  expect_error(carle_strub_estimate(c(10, -Inf, 3)), class = "cpue_estimation_error")
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

test_that("Carle & Strub priors must be finite numeric scalars", {
  bad_priors <- list(NA_real_, Inf, numeric(0), c(1, 2), "1")
  for (prior in bad_priors) {
    expect_error(
      carle_strub_estimate(c(10, 5, 2), alpha = prior),
      class = "cpue_estimation_error"
    )
    expect_error(
      carle_strub_estimate(c(10, 5, 2), beta = prior),
      class = "cpue_estimation_error"
    )
  }
})

# ---- Determinism / sanity ----------------------------------------------------

test_that("more depletion implies higher capture probability", {
  steep  <- zippin_estimate(c(80, 10, 2), quiet = TRUE)
  gentle <- zippin_estimate(c(30, 25, 20), quiet = TRUE)
  expect_gt(steep$p, gentle$p)
})
