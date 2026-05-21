# Tests for build_pass_matrix() and the analyze_cpue() pipeline.

# ---- Fixtures ----------------------------------------------------------------

# Two reaches, one date. R1 has two species over 3 passes; R2 has one
# species over 2 passes. Effort is 300 s/pass at R1, 250 s/pass at R2,
# duplicated across species rows as in real long-format data.
make_catch <- function() {
  data.frame(
    reach_id = c(rep("R1", 6), rep("R2", 2)),
    date     = as.Date("2025-06-01"),
    pass_number = c(1L, 2L, 3L, 1L, 2L, 3L, 1L, 2L),
    species  = c("BNT", "BNT", "BNT", "RBT", "RBT", "RBT", "BNT", "BNT"),
    count    = c(45L, 18L, 7L, 20L, 8L, 3L, 50L, 10L),
    effort_seconds = c(300, 300, 300, 300, 300, 300, 250, 250),
    stringsAsFactors = FALSE
  )
}

make_meta <- function(area = TRUE) {
  m <- data.frame(reach_id = c("R1", "R2"), length_m = c(100, 150),
                  stringsAsFactors = FALSE)
  if (area) m$area_m2 <- c(800, 1200)
  m
}

# ---- build_pass_matrix -------------------------------------------------------

test_that("build_pass_matrix returns one row per reach x date x species", {
  pm <- build_pass_matrix(make_catch())
  expect_identical(nrow(pm), 3L)
  expect_named(pm, c("reach_id", "date", "species", "n_passes", "counts"))
  expect_type(pm$counts, "list")
})

test_that("pass-count vectors are ordered by pass number", {
  pm <- build_pass_matrix(make_catch())
  r1_bnt <- pm$counts[[which(pm$reach_id == "R1" & pm$species == "BNT")]]
  expect_identical(r1_bnt, c(45, 18, 7))
})

test_that("a species absent from a conducted pass is filled with zero", {
  catch <- make_catch()
  # Drop RBT's pass-2 row; passes 1,2,3 still exist (from BNT).
  catch <- catch[!(catch$species == "RBT" & catch$pass_number == 2L), ]
  pm <- build_pass_matrix(catch)
  rbt <- pm$counts[[which(pm$reach_id == "R1" & pm$species == "RBT")]]
  expect_identical(rbt, c(20, 0, 3))
})

test_that("duplicate species x pass rows are summed", {
  catch <- make_catch()
  dup <- catch[catch$reach_id == "R1" & catch$species == "RBT" &
                 catch$pass_number == 1L, ]
  dup$count <- 5L
  catch <- rbind(catch, dup)
  pm <- build_pass_matrix(catch)
  rbt <- pm$counts[[which(pm$reach_id == "R1" & pm$species == "RBT")]]
  expect_identical(rbt[1], 25)  # 20 + 5
})

# ---- analyze_cpue: structure -------------------------------------------------

test_that("analyze_cpue returns one tidy row per series with documented columns", {
  res <- analyze_cpue(make_catch(), make_meta())
  expect_identical(nrow(res), 3L)
  expect_named(res, c(
    "reach_id", "date", "species",
    "method", "n_passes", "catch_total",
    "N", "N_se", "p", "p_se", "converged", "note",
    "length_m", "area_m2",
    "effort_seconds", "effort_amp_seconds", "effort_basis", "cpue",
    "density_per_m", "density_per_m2"
  ))
})

# ---- analyze_cpue: estimates and derived metrics -----------------------------

test_that("N agrees with a direct estimate_population call", {
  res <- analyze_cpue(make_catch(), make_meta())
  direct <- estimate_population(c(45, 18, 7), quiet = TRUE)
  row <- res[res$reach_id == "R1" & res$species == "BNT", ]
  expect_equal(row$N, direct$N)
  expect_equal(row$N_se, direct$N_se, tolerance = 1e-6)
})

test_that("density_per_m = N / length_m and density_per_m2 = N / area_m2", {
  res <- analyze_cpue(make_catch(), make_meta())
  row <- res[res$reach_id == "R1" & res$species == "BNT", ]
  expect_equal(row$density_per_m, row$N / 100)
  expect_equal(row$density_per_m2, row$N / 800)
})

test_that("areal density is NA when reach_metadata lacks area_m2", {
  res <- analyze_cpue(make_catch(), make_meta(area = FALSE))
  expect_true(all(is.na(res$density_per_m2)))
  expect_true(all(is.na(res$area_m2)))
  expect_false(any(is.na(res$density_per_m)))  # length-based still works
})

# ---- analyze_cpue: effort ----------------------------------------------------

test_that("effort is summed per pass, not double-counted across species", {
  res <- analyze_cpue(make_catch(), make_meta())
  # R1: 3 passes x 300 s = 900 (despite two species sharing each pass)
  expect_equal(unique(res$effort_seconds[res$reach_id == "R1"]), 900)
  expect_equal(unique(res$effort_seconds[res$reach_id == "R2"]), 500)
})

test_that("cpue = catch_total / effort in the seconds basis", {
  res <- analyze_cpue(make_catch(), make_meta())
  row <- res[res$reach_id == "R1" & res$species == "BNT", ]
  expect_equal(row$cpue, 70 / 900)
})

test_that("amp_seconds basis errors without an amperage column", {
  expect_error(
    analyze_cpue(make_catch(), make_meta(), effort_basis = "amp_seconds"),
    class = "cpue_analysis_error"
  )
})

test_that("amp_seconds basis works and drives cpue when amperage present", {
  catch <- make_catch()
  catch$amperage <- 4  # constant 4 A across all passes
  res <- analyze_cpue(catch, make_meta(), effort_basis = "amp_seconds")
  row <- res[res$reach_id == "R1" & res$species == "BNT", ]
  expect_equal(row$effort_amp_seconds, 900 * 4)   # 3600 amp-seconds
  expect_equal(row$cpue, 70 / (900 * 4))
  expect_identical(unique(res$effort_basis), "amp_seconds")
})

# ---- analyze_cpue: method + validation wiring --------------------------------

test_that("method argument is passed through to the estimator", {
  res <- analyze_cpue(make_catch(), make_meta(), method = "carle_strub")
  expect_true(all(res$method == "carle_strub"))
})

test_that("validate = TRUE propagates a validation error for bad input", {
  catch <- make_catch()
  catch$effort_seconds[1] <- -5  # invalid effort
  expect_error(
    analyze_cpue(catch, make_meta()),
    class = "cpue_validation_error"
  )
})

test_that("validate = FALSE skips validation", {
  catch <- make_catch()
  catch$effort_seconds[1] <- -5
  # Should not raise the validation error (effort still used downstream).
  expect_no_error(suppressWarnings(
    analyze_cpue(catch, make_meta(), validate = FALSE)
  ))
})

test_that("non-converging series produce a single aggregated warning", {
  # Increasing catch -> Zippin model failure for R1/BNT.
  catch <- make_catch()
  catch$count[catch$reach_id == "R1" & catch$species == "BNT"] <- c(7L, 18L, 45L)
  expect_warning(
    res <- analyze_cpue(catch, make_meta(), method = "zippin"),
    regexp = "did not yield"
  )
  bad <- res[res$reach_id == "R1" & res$species == "BNT", ]
  expect_false(bad$converged)
  expect_true(is.na(bad$N))
})
