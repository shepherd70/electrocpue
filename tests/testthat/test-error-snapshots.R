# Snapshot tests for user-facing error and warning message formatting.
#
# The other test files assert on error *content* (via grepl on $failures).
# These tests pin the fully rendered message text — the wording, structure,
# and bullet formatting a user actually sees — so unintended changes to the
# UX surface show up as reviewable snapshot diffs. expect_snapshot() runs
# under testthat's reproducible output (fixed width, no color, ASCII), so
# the captured text is stable across platforms.

# ---- Fixtures ----------------------------------------------------------------
# Local, self-contained fixtures (test files do not share helpers).

snap_catch <- function() {
  data.frame(
    reach_id       = c("R1", "R1", "R1", "R2", "R2"),
    date           = as.Date("2025-06-01"),
    pass_number    = c(1L, 2L, 3L, 1L, 2L),
    species        = c("BNT", "BNT", "BNT", "RBT", "RBT"),
    count          = c(10L, 5L, 2L, 8L, 4L),
    effort_seconds = c(300, 300, 300, 250, 250),
    stringsAsFactors = FALSE
  )
}

snap_meta <- function() {
  data.frame(
    reach_id = c("R1", "R2"),
    length_m = c(100, 150),
    stringsAsFactors = FALSE
  )
}

# ---- Validation: collected failures ------------------------------------------

test_that("validate_cpue_input aborts with all failures listed at once", {
  catch <- snap_catch()
  catch$reach_id <- NULL            # missing required column
  catch$count    <- -catch$count    # negative counts
  catch$effort_seconds[1] <- 0      # non-positive effort
  expect_snapshot(
    validate_cpue_input(catch, snap_meta(), strict = FALSE),
    error = TRUE
  )
})

test_that("validate_cpue_input reports non-contiguous passes with location", {
  catch <- snap_catch()
  catch$pass_number[catch$reach_id == "R2"] <- c(1L, 3L)
  expect_snapshot(
    validate_cpue_input(catch, snap_meta(), strict = FALSE),
    error = TRUE
  )
})

test_that("validate_cpue_input truncates the orphan reach_id preview", {
  catch <- snap_catch()
  extra <- data.frame(
    reach_id       = paste0("ORPHAN_", 1:7),
    date           = as.Date("2025-06-01"),
    pass_number    = 1L,
    species        = "BNT",
    count          = 1L,
    effort_seconds = 100,
    stringsAsFactors = FALSE
  )
  expect_snapshot(
    validate_cpue_input(rbind(catch, extra), snap_meta(), strict = FALSE),
    error = TRUE
  )
})

test_that("validate_cpue_input advises about missing optional columns", {
  expect_snapshot(
    invisible(validate_cpue_input(snap_catch(), snap_meta(), strict = TRUE))
  )
})

test_that("validate_cpue_input reports a non-positive reach length", {
  meta <- snap_meta()
  meta$length_m[1] <- 0       # zero-length reach -> Inf density downstream
  expect_snapshot(
    validate_cpue_input(snap_catch(), meta, strict = FALSE),
    error = TRUE
  )
})

test_that("validate_cpue_input reports within-pass effort disagreement", {
  catch <- snap_catch()
  extra <- catch[1, ]                 # R1, pass 1
  extra$species        <- "RBT"
  extra$effort_seconds <- 999         # effort differs within the pass
  expect_snapshot(
    validate_cpue_input(rbind(catch, extra), snap_meta(), strict = FALSE),
    error = TRUE
  )
})

# ---- Estimation: warnings and aborts -----------------------------------------

test_that("single-pass series warns and returns NA", {
  expect_snapshot(invisible(estimate_population(c(5L))))
})

test_that("auto falls back to Carle & Strub when Zippin fails", {
  # Increasing catch -> Zippin model failure -> Carle & Strub fallback.
  expect_snapshot(invisible(estimate_population(c(2L, 5L, 9L))))
})

test_that("zippin_estimate warns on insufficient depletion", {
  expect_snapshot(invisible(zippin_estimate(c(2L, 5L, 9L))))
})

test_that("carle_strub_estimate flags a non-depleting catch series", {
  # Increasing catch converges numerically but violates the assumption.
  expect_snapshot(invisible(carle_strub_estimate(c(2L, 5L, 9L))))
})

test_that("carle_strub_estimate rejects non-positive priors", {
  expect_snapshot(carle_strub_estimate(c(5L, 3L), alpha = 0), error = TRUE)
})

test_that("estimate_population rejects non-integer counts", {
  expect_snapshot(estimate_population(c(4.5, 2)), error = TRUE)
})

test_that("estimate_population rejects negative counts", {
  expect_snapshot(estimate_population(c(-1L, 2L)), error = TRUE)
})

# ---- Analysis pipeline: aborts -----------------------------------------------

test_that("build_pass_matrix reports missing reshape columns", {
  catch <- snap_catch()
  catch$species <- NULL
  expect_snapshot(build_pass_matrix(catch), error = TRUE)
})

test_that("analyze_cpue rejects amp_seconds basis without amperage", {
  expect_snapshot(
    analyze_cpue(snap_catch(), snap_meta(), effort_basis = "amp_seconds"),
    error = TRUE
  )
})

test_that("analyze_cpue rejects amp_seconds basis with an invalid amperage", {
  catch <- snap_catch()
  catch$amperage    <- 4
  catch$amperage[1] <- NA_real_       # a missing current reading
  expect_snapshot(
    analyze_cpue(catch, snap_meta(), effort_basis = "amp_seconds", validate = FALSE),
    error = TRUE
  )
})

test_that("analyze_cpue warns when some series do not converge", {
  catch <- snap_catch()
  # Reduce R2 to a single pass -> non-convergent (single_pass) series.
  catch <- catch[!(catch$reach_id == "R2" & catch$pass_number == 2L), ]
  expect_snapshot(invisible(analyze_cpue(catch, snap_meta(), validate = FALSE)))
})

# ---- Summary: aborts ---------------------------------------------------------

test_that("summarize_cpue rejects a non-data-frame input", {
  expect_snapshot(summarize_cpue(list(1, 2, 3)), error = TRUE)
})

test_that("summarize_cpue reports missing analyze_cpue columns", {
  expect_snapshot(summarize_cpue(data.frame(reach_id = "R1")), error = TRUE)
})

test_that("summarize_cpue rejects an out-of-range confidence level", {
  catch <- snap_catch()
  res   <- analyze_cpue(catch, snap_meta(), validate = FALSE)
  expect_snapshot(summarize_cpue(res, level = 1.5), error = TRUE)
})
