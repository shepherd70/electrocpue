# Tests for summarize_cpue() and the .summary_ci() helper.

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
    p           = 0.6,
    p_se        = 0.07,
    converged   = c(TRUE, TRUE, TRUE, TRUE),
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
    "n_surveys", "n_converged", "prop_converged", "catch_total", "N_mean",
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

test_that("single survey uses a Wald interval from the depletion SE", {
  res <- summarize_cpue(make_analysis())
  rbt <- res[res$species == "RBT", ]  # n = 1
  z   <- stats::qnorm(0.975)
  dens <- 32 / 100
  se   <- 2.4 / 100
  expect_equal(rbt$density_per_m_mean, dens)
  expect_equal(rbt$density_per_m_lwr, dens - z * se)
  expect_equal(rbt$density_per_m_upr, dens + z * se)
})

test_that("multiple surveys use a t-interval on the survey densities", {
  res <- summarize_cpue(make_analysis())
  bnt <- res[res$species == "BNT", ]
  vals <- c(74, 62, 80) / 100
  m    <- mean(vals)
  tcrit <- stats::qt(0.975, df = 2)
  se_mean <- stats::sd(vals) / sqrt(3)
  expect_equal(bnt$density_per_m_mean, m)
  expect_equal(bnt$density_per_m_lwr, m - tcrit * se_mean)
  expect_equal(bnt$density_per_m_upr, m + tcrit * se_mean)
})

test_that("level argument widens or narrows the interval", {
  wide   <- summarize_cpue(make_analysis(), level = 0.99)
  narrow <- summarize_cpue(make_analysis(), level = 0.90)
  w <- wide[wide$species == "BNT", ]
  n <- narrow[narrow$species == "BNT", ]
  expect_gt(w$density_per_m_upr - w$density_per_m_lwr,
            n$density_per_m_upr - n$density_per_m_lwr)
})

test_that("lower interval limit is truncated at zero", {
  x <- make_analysis()
  x <- x[x$species == "RBT", ]
  x$N_se <- 1000  # huge SE would push Wald lower below zero
  res <- summarize_cpue(x)
  expect_gte(res$density_per_m_lwr, 0)
})

# ---- Areal density -----------------------------------------------------------

test_that("areal density CI is computed when area is present", {
  res <- summarize_cpue(make_analysis())
  bnt <- res[res$species == "BNT", ]
  expect_equal(bnt$density_per_m2_mean, mean(c(74, 62, 80) / 800))
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
  expect_error(summarize_cpue(make_analysis(), level = 1.5),
               class = "cpue_analysis_error")
  expect_error(summarize_cpue(make_analysis(), level = 0),
               class = "cpue_analysis_error")
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
