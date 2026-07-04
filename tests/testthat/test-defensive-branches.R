# Targeted tests for defensive guards and rarely-hit branches that the
# main behavioural tests don't exercise. Several call internal (unexported)
# helpers directly; this is intentional - it verifies the contract of each
# guard in isolation.

# ---- build_pass_matrix input guard ------------------------------------------

test_that("build_pass_matrix aborts when reshaping columns are missing", {
  expect_error(
    build_pass_matrix(data.frame(reach_id = "R1", date = Sys.Date())),
    class = "cpue_analysis_error"
  )
})

# ---- estimate_population: both estimators fail (auto) ------------------------

test_that("auto returns NA when both Zippin and Carle & Strub fail", {
  # A wildly increasing series: Zippin model fails, and Carle & Strub
  # runs away past the iteration cap (no depletion signal at all).
  expect_warning(
    out <- estimate_population(c(1, 1000000), method = "auto"),
    regexp = "[Bb]oth"
  )
  expect_true(is.na(out$N))
  expect_false(out$converged)
  expect_identical(out$note, "no_convergence")
})

# ---- carle_strub_estimate edge branches -------------------------------------

test_that("carle_strub_estimate flags a single-pass series", {
  expect_warning(out <- carle_strub_estimate(c(40)), regexp = "[Ss]ingle-pass")
  expect_true(is.na(out$N))
  expect_identical(out$note, "single_pass")
})

test_that("carle_strub_estimate hits its iteration cap on a runaway series", {
  expect_warning(
    out <- carle_strub_estimate(c(1, 1000000)),
    regexp = "did not converge"
  )
  expect_true(is.na(out$N))
  expect_identical(out$note, "no_convergence")
})

# ---- Variance helpers: non-finite guard -------------------------------------

test_that("Zippin variance helpers return NA on non-finite input", {
  expect_true(is.na(.zippin_no_var(74, NA_real_, 3)))
  expect_true(is.na(.zippin_p_var(74, NA_real_, 3)))
})

# ---- Validation helpers ------------------------------------------------------
# Generic kernel helpers (type_matches, check_column_types, check_no_na, ...)
# moved to tritonIngest and are tested there; only domain checks remain here.

test_that("check_counts_nonneg_integer returns no failures without a count col", {
  out <- check_counts_nonneg_integer(data.frame(other = 1))
  expect_identical(out, character(0))
})

test_that("check_counts_nonneg_integer flags non-integer counts", {
  out <- check_counts_nonneg_integer(data.frame(count = c(1.5, 2, 3)))
  expect_true(any(grepl("non-integer", out)))
})

# ---- advise_optional_columns: reaches the post-warning return ----------------

test_that("advise_optional_columns warns and returns invisibly", {
  # suppressWarnings (not tryCatch) lets execution continue past the
  # cli_warn() to the trailing invisible(NULL).
  expect_null(suppressWarnings(
    advise_optional_columns(
      data.frame(reach_id = "R1"),
      c(amperage = "numeric", voltage = "numeric"),
      "catch_data"
    )
  ))
})

# ---- summarize_cpue: single survey with NA standard error --------------------

test_that("summarize_cpue yields NA interval for a lone unidentified survey", {
  # Not identifiable (low p / unbounded above), so it is held out of the
  # interval -- which is therefore absent -- while the point estimate and the
  # weak flag are still reported.
  x <- data.frame(
    reach_id = "R1", species = "BNT",
    converged = TRUE, identifiable = FALSE, note = "ok",
    catch_total = 30, N = 32, N_se = NA_real_,
    N_lwr = NA_real_, N_upr = NA_real_, p = 0.2,
    length_m = 100, area_m2 = 800, cpue = 0.03,
    density_per_m = 0.32, density_per_m2 = 0.04,
    stringsAsFactors = FALSE
  )
  res <- summarize_cpue(x)
  expect_equal(res$density_per_m_mean, 0.32)
  expect_true(res$weak)
  expect_true(is.na(res$density_per_m_lwr))
  expect_true(is.na(res$density_per_m_upr))
})
