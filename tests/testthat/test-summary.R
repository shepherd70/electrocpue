# Tests for summarize_cpue() and the .hksj_logci() helper.

# ---- Fixtures ----------------------------------------------------------------

# A synthetic analyze_cpue() output: one species (BNT) surveyed at reach R1
# on three dates, plus RBT once. Hand-built so CI values are predictable.
make_analysis <- function() {
  data.frame(
    reach_id    = c("R1", "R1", "R1", "R1"),
    date        = as.Date(c("2025-06-01", "2025-07-01", "2025-08-01", "2025-06-01")),
    species     = c("BNT", "BNT", "BNT", "RBT"),
    method      = "zippin",
    n_passes    = 3L,
    catch_total = c(70, 60, 80, 30),
    N           = c(74, 62, 80, 32),
    N_se        = c(3.2366, 2.5, 4.0, 2.4),
    # Profile-likelihood limits: bracket N, respect N >= catch. All well
    # identified (p = 0.6 >= p_min, bounded above), so weak = FALSE.
    N_lwr       = c(70, 60, 80, 30),
    N_upr       = c(82, 68, 90, 38),
    p           = 0.6,
    p_se        = 0.07,
    converged   = c(TRUE, TRUE, TRUE, TRUE),
    identifiable = c(TRUE, TRUE, TRUE, TRUE),
    note        = "ok",
    length_m    = 100,
    area_m2     = 800,
    effort_seconds = 900,
    effort_amp_seconds = NA_real_,
    effort_basis = "seconds",
    cpue        = c(70, 60, 80, 30) / 900,
    density_per_m  = c(74, 62, 80, 32) / 100,
    density_per_m2 = c(74, 62, 80, 32) / 800,
    stringsAsFactors = FALSE
  )
}

# ---- Structure ---------------------------------------------------------------

test_that("summarize_cpue returns one row per reach x species with documented columns", {
  res <- summarize_cpue(make_analysis())
  expect_identical(nrow(res), 2L)  # R1/BNT and R1/RBT
  expect_named(res, c(
    "reach_id", "species",
    "n_surveys", "n_converged", "prop_converged", "n_assumption_violated",
    "n_identified", "weak",
    "catch_total", "N_mean",
    "density_per_m_mean", "density_per_m_lwr", "density_per_m_upr",
    "density_per_m2_mean", "density_per_m2_lwr", "density_per_m2_upr",
    "cpue_mean"
  ))
})

test_that("survey counts and catch totals aggregate correctly", {
  res <- summarize_cpue(make_analysis())
  bnt <- res[res$species == "BNT", ]
  expect_identical(bnt$n_surveys, 3L)
  expect_identical(bnt$n_converged, 3L)
  expect_equal(bnt$prop_converged, 1)
  expect_equal(bnt$catch_total, 210)   # 70 + 60 + 80
  expect_equal(bnt$N_mean, mean(c(74, 62, 80)))
})

# ---- Confidence interval logic -----------------------------------------------

test_that("a single identified survey retains its profile interval and is flagged weak", {
  res <- summarize_cpue(make_analysis())
  rbt <- res[res$species == "RBT", ]   # n = 1
  expect_identical(rbt$n_identified, 1L)
  expect_true(rbt$weak)                # one survey cannot pin the reach mean
  d <- 32 / 100; dl <- 30 / 100; du <- 38 / 100
  expect_equal(rbt$density_per_m_mean, d)
  expect_equal(rbt$density_per_m_lwr, dl)
  expect_equal(rbt$density_per_m_upr, du)
})

test_that("multiple identified surveys pool to a positive HKSJ interval, not flagged weak", {
  res <- summarize_cpue(make_analysis())
  bnt <- res[res$species == "BNT", ]   # n = 3, all identified
  expect_identical(bnt$n_identified, 3L)
  expect_false(bnt$weak)
  expected <- .hksj_logci(
    c(74, 62, 80) / 100,
    c(70, 60, 80) / 100,
    c(82, 68, 90) / 100,
    resolution = 1 / 100
  )
  expect_equal(bnt$density_per_m_mean, expected[["mean"]])
  expect_gt(bnt$density_per_m_lwr, 0)                              # positive (log scale)
  expect_lt(bnt$density_per_m_lwr, bnt$density_per_m_mean)
  expect_gt(bnt$density_per_m_upr, bnt$density_per_m_mean)
})

test_that("level argument widens or narrows the interval", {
  wide   <- summarize_cpue(make_analysis(), level = 0.99)
  narrow <- summarize_cpue(make_analysis(), level = 0.90)
  w <- wide[wide$species == "BNT", ]
  n <- narrow[narrow$species == "BNT", ]
  expect_gt(w$density_per_m_upr - w$density_per_m_lwr,
            n$density_per_m_upr - n$density_per_m_lwr)
})

test_that("profile-derived precision is invariant to requested pooled level", {
  args <- list(d = c(1, 1.2), dl = c(0.8, 1), du = c(1.3, 1.5),
               resolution = 0.01)
  narrow <- do.call(.hksj_logci, c(args, list(level = 0.90)))
  wide   <- do.call(.hksj_logci, c(args, list(level = 0.99)))

  expect_equal(narrow[["mean"]], wide[["mean"]])
  expect_lt(narrow[["upr"]] / narrow[["mean"]],
            wide[["upr"]] / wide[["mean"]])
})

test_that("the lower interval limit is positive by construction (log scale)", {
  res <- summarize_cpue(make_analysis())
  expect_true(all(res$density_per_m_lwr > 0))
  ok <- !is.na(res$density_per_m2_lwr)
  expect_true(all(res$density_per_m2_lwr[ok] > 0))
})

# ---- Areal density -----------------------------------------------------------

test_that("areal density CI is computed when area is present", {
  res <- summarize_cpue(make_analysis())
  bnt <- res[res$species == "BNT", ]
  expected <- .hksj_logci(
    c(74, 62, 80) / 800,
    c(70, 60, 80) / 800,
    c(82, 68, 90) / 800,
    resolution = 1 / 800
  )
  expect_equal(bnt$density_per_m2_mean, expected[["mean"]])
  expect_false(is.na(bnt$density_per_m2_lwr))
})

test_that("areal density is NA when area_m2 is all NA", {
  x <- make_analysis()
  x$area_m2 <- NA_real_
  x$density_per_m2 <- NA_real_
  res <- summarize_cpue(x)
  expect_true(all(is.na(res$density_per_m2_mean)))
  expect_true(all(is.na(res$density_per_m2_lwr)))
})

# ---- Non-convergence handling ------------------------------------------------

test_that("non-converged surveys are excluded from means but counted", {
  x <- make_analysis()
  # Knock out the middle BNT survey.
  x$converged[2] <- FALSE
  x$N[2] <- NA_real_
  x$density_per_m[2] <- NA_real_
  x$density_per_m2[2] <- NA_real_
  res <- summarize_cpue(x)
  bnt <- res[res$species == "BNT", ]
  expect_identical(bnt$n_surveys, 3L)
  expect_identical(bnt$n_converged, 2L)
  expect_equal(bnt$prop_converged, 2 / 3)
  expect_equal(bnt$N_mean, mean(c(74, 80)))  # excludes the NA
  # CPUE is model-free: it is averaged over ALL surveys, including the
  # one whose depletion fit failed (its catch/effort is still valid).
  expect_equal(bnt$cpue_mean, mean(c(70, 60, 80) / 900))
})

test_that("a group with zero converged surveys yields NA estimates", {
  x <- make_analysis()
  x <- x[x$species == "RBT", ]
  x$converged <- FALSE
  x$N <- NA_real_
  x$density_per_m <- NA_real_
  res <- summarize_cpue(x)
  expect_identical(res$n_converged, 0L)
  expect_true(is.na(res$density_per_m_mean))
  expect_true(is.na(res$N_mean))
  # Abundance/density collapse to NA with no converged surveys, but the
  # observed CPUE does not depend on convergence and is still reported.
  expect_equal(res$cpue_mean, 30 / 900)
})

# ---- Assumption violations ---------------------------------------------------

test_that("assumption_violated surveys are excluded from estimates but surfaced", {
  x <- make_analysis()
  # The middle BNT survey converged to a number but violates the depletion
  # assumption; it must not pollute the abundance / density means.
  x$note[2] <- "assumption_violated"
  res <- summarize_cpue(x)
  bnt <- res[res$species == "BNT", ]
  expect_identical(bnt$n_converged, 3L)            # it did converge
  expect_identical(bnt$n_assumption_violated, 1L)  # but is flagged
  expect_equal(bnt$N_mean, mean(c(74, 80)))        # excludes the flagged N = 62
  expected <- .hksj_logci(
    c(74, 80) / 100,
    c(70, 80) / 100,
    c(82, 90) / 100,
    resolution = 1 / 100
  )
  expect_equal(bnt$density_per_m_mean, expected[["mean"]])
  # CPUE is model-free, so every survey still contributes.
  expect_equal(bnt$cpue_mean, mean(c(70, 60, 80) / 900))
})

test_that("a group of only assumption_violated surveys yields NA estimates", {
  x <- make_analysis()
  x <- x[x$species == "BNT", ]
  x$note <- "assumption_violated"
  res <- summarize_cpue(x)
  expect_identical(res$n_converged, 3L)
  expect_identical(res$n_assumption_violated, 3L)
  expect_true(is.na(res$N_mean))
  expect_true(is.na(res$density_per_m_mean))
  expect_equal(res$cpue_mean, mean(c(70, 60, 80) / 900))  # still observed
})

test_that("an infinite cpue (zero-effort survey) is dropped from cpue_mean", {
  x <- make_analysis()
  x$cpue[2] <- Inf            # e.g. effort_basis = "amp_seconds", zero amperage
  res <- summarize_cpue(x)
  bnt <- res[res$species == "BNT", ]
  expect_equal(bnt$cpue_mean, mean(c(70, 80) / 900))  # the Inf survey is dropped
})

test_that("modified Knapp-Hartung retains uncertainty for identical estimates", {
  out <- .hksj_logci(
    d = c(1, 1), dl = c(0.8, 0.8), du = c(1.2, 1.2),
    resolution = 0.01
  )
  expect_equal(out[["mean"]], 1)
  expect_lt(out[["lwr"]], out[["mean"]])
  expect_gt(out[["upr"]], out[["mean"]])
})

test_that("zero-width discrete profiles pool to finite nonzero-width limits", {
  out <- .hksj_logci(
    d = c(1, 1), dl = c(1, 1), du = c(1, 1),
    resolution = 0.01
  )
  expect_true(all(is.finite(out[c("mean", "lwr", "upr")])))
  expect_lt(out[["lwr"]], out[["mean"]])
  expect_gt(out[["upr"]], out[["mean"]])
})

test_that("pooled density estimate always lies inside its own interval", {
  d <- c(rep(1, 9), 10000)
  out <- .hksj_logci(d, 0.9 * d, 1.1 * d, resolution = 0.01)
  expect_lte(out[["lwr"]], out[["mean"]])
  expect_gte(out[["upr"]], out[["mean"]])
  expect_false(isTRUE(all.equal(out[["mean"]], mean(d))))
})

test_that("statistical intervals are not truncated by a display-width cap", {
  d <- c(1, 1000)
  out <- .hksj_logci(d, 0.9 * d, 1.1 * d, resolution = 0.01)
  expect_gt(out[["upr"]] / out[["mean"]], 20)
  expect_gt(out[["mean"]] / out[["lwr"]], 20)
})

# ---- Custom grouping ---------------------------------------------------------

test_that("by argument can collapse to reach level across species", {
  res <- summarize_cpue(make_analysis(), by = "reach_id")
  expect_identical(nrow(res), 1L)
  expect_identical(res$n_surveys, 4L)         # all four rows
  expect_equal(res$catch_total, 240)          # 70+60+80+30
})

# ---- Input validation --------------------------------------------------------

test_that("non-data-frame input aborts", {
  expect_error(summarize_cpue(list(a = 1)), class = "cpue_analysis_error")
})

test_that("missing required columns abort with a helpful message", {
  expect_error(summarize_cpue(data.frame(reach_id = "R1", species = "BNT")),
               class = "cpue_analysis_error")
})

test_that("invalid confidence level aborts", {
  for (level in list(1.5, 0, NA_real_, Inf, numeric(0), c(0.9, 0.95))) {
    expect_error(summarize_cpue(make_analysis(), level = level),
                 class = "cpue_analysis_error")
  }
})

test_that("invalid capture-probability threshold aborts", {
  for (p_min in list(-0.1, 1, NA_real_, Inf, numeric(0), c(0.3, 0.4))) {
    expect_error(summarize_cpue(make_analysis(), p_min = p_min),
                 class = "cpue_analysis_error")
  }
})

# ---- Integration with analyze_cpue -------------------------------------------

test_that("summarize_cpue consumes analyze_cpue output directly", {
  catch <- data.frame(
    reach_id = "R1",
    date     = rep(as.Date(c("2025-06-01", "2025-07-01")), each = 3),
    pass_number = rep(1:3, times = 2),
    species  = "BNT",
    count    = c(45L, 18L, 7L, 40L, 15L, 6L),
    effort_seconds = 300,
    stringsAsFactors = FALSE
  )
  meta <- data.frame(reach_id = "R1", length_m = 100, area_m2 = 800)
  res  <- summarize_cpue(analyze_cpue(catch, meta))
  expect_identical(nrow(res), 1L)
  expect_identical(res$n_surveys, 2L)
  expect_true(res$density_per_m_mean > 0)
})
