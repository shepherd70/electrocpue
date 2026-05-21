# Tests for validate_cpue_input() and its helper checks.
# Each section targets one check in the validation pipeline.

# ---- Fixtures ----------------------------------------------------------------

make_catch <- function() {
  data.frame(
    reach_id       = c("R1", "R1", "R1", "R2", "R2"),
    date           = as.Date(c("2025-06-01", "2025-06-01", "2025-06-01",
                               "2025-06-01", "2025-06-01")),
    pass_number    = c(1L, 2L, 3L, 1L, 2L),
    species        = c("BNT", "BNT", "BNT", "RBT", "RBT"),
    count          = c(10L, 5L, 2L, 8L, 4L),
    effort_seconds = c(300, 300, 300, 250, 250),
    stringsAsFactors = FALSE
  )
}

make_meta <- function() {
  data.frame(
    reach_id = c("R1", "R2"),
    length_m = c(100, 150),
    stringsAsFactors = FALSE
  )
}

# Captures the classed error object so tests can inspect $failures.
catch_cpue_error <- function(catch_data, reach_metadata, strict = TRUE) {
  tryCatch(
    validate_cpue_input(catch_data, reach_metadata, strict = strict),
    cpue_validation_error = function(e) e
  )
}

# ---- Happy path --------------------------------------------------------------

test_that("valid data returns TRUE invisibly", {
  expect_invisible(validate_cpue_input(make_catch(), make_meta(), strict = FALSE))
  expect_true(validate_cpue_input(make_catch(), make_meta(), strict = FALSE))
})

# ---- Error class and structure -----------------------------------------------

test_that("validation error has class cpue_validation_error", {
  catch <- make_catch()
  catch$reach_id <- NULL
  expect_error(
    validate_cpue_input(catch, make_meta()),
    class = "cpue_validation_error"
  )
})

test_that("error object carries a non-empty failures character vector", {
  catch <- make_catch()
  catch$reach_id <- NULL
  err <- catch_cpue_error(catch, make_meta())
  expect_s3_class(err, "cpue_validation_error")
  expect_type(err$failures, "character")
  expect_gt(length(err$failures), 0)
})

test_that("all failures are reported in a single error, not one at a time", {
  catch <- make_catch()
  catch$reach_id <- NULL     # missing required col
  catch$count    <- -catch$count  # negative counts
  err <- catch_cpue_error(catch, make_meta())
  expect_gt(length(err$failures), 1)
})

# ---- Required columns --------------------------------------------------------

test_that("missing required catch column is reported", {
  catch <- make_catch()
  catch$pass_number <- NULL
  expect_error(
    validate_cpue_input(catch, make_meta(), strict = FALSE),
    class = "cpue_validation_error"
  )
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("pass_number", err$failures)))
})

test_that("missing required reach metadata column is reported", {
  meta <- make_meta()
  meta$length_m <- NULL
  expect_error(
    validate_cpue_input(make_catch(), meta, strict = FALSE),
    class = "cpue_validation_error"
  )
  err <- catch_cpue_error(make_catch(), meta, strict = FALSE)
  expect_true(any(grepl("length_m", err$failures)))
})

test_that("multiple missing columns are all reported", {
  catch <- make_catch()
  catch$species       <- NULL
  catch$effort_seconds <- NULL
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("species",        err$failures)))
  expect_true(any(grepl("effort_seconds", err$failures)))
})

# ---- Column types ------------------------------------------------------------

test_that("wrong type for pass_number is reported", {
  catch <- make_catch()
  catch$pass_number <- as.numeric(catch$pass_number)  # numeric, not integer
  expect_error(
    validate_cpue_input(catch, make_meta(), strict = FALSE),
    class = "cpue_validation_error"
  )
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("pass_number", err$failures)))
})

test_that("wrong type for date is reported", {
  catch <- make_catch()
  catch$date <- as.character(catch$date)  # character, not Date
  expect_error(
    validate_cpue_input(catch, make_meta(), strict = FALSE),
    class = "cpue_validation_error"
  )
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("date", err$failures)))
})

test_that("integer count column satisfies numeric-typed reach metadata length_m", {
  # type_matches("numeric") accepts integer — verify no false positive
  meta <- make_meta()
  meta$length_m <- as.integer(meta$length_m)
  expect_no_error(validate_cpue_input(make_catch(), meta, strict = FALSE))
})

# ---- NA checks ---------------------------------------------------------------

test_that("NA in catch$reach_id is reported", {
  catch <- make_catch()
  catch$reach_id[1] <- NA_character_
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("reach_id", err$failures)))
})

test_that("NA in catch$date is reported", {
  catch <- make_catch()
  catch$date[1] <- NA
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("date", err$failures)))
})

test_that("NA in catch$pass_number is reported", {
  catch <- make_catch()
  catch$pass_number[2] <- NA_integer_
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("pass_number", err$failures)))
})

test_that("NA in catch$species is reported", {
  catch <- make_catch()
  catch$species[1] <- NA_character_
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  # Caught by check_no_na; species_present check may also fire
  expect_gt(length(err$failures), 0)
})

test_that("NA in reach_metadata$reach_id is reported", {
  meta <- make_meta()
  meta$reach_id[1] <- NA_character_
  err <- catch_cpue_error(make_catch(), meta, strict = FALSE)
  expect_true(any(grepl("reach_id", err$failures)))
})

# ---- Pass contiguity ---------------------------------------------------------

test_that("non-contiguous passes are reported", {
  catch <- make_catch()
  # Replace R2 passes (1, 2) with a gap (1, 3)
  catch$pass_number[catch$reach_id == "R2"] <- c(1L, 3L)
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("contiguous", err$failures)))
  expect_true(any(grepl("R2", err$failures)))
})

test_that("passes not starting at 1 are reported", {
  catch <- make_catch()
  catch$pass_number[catch$reach_id == "R2"] <- c(2L, 3L)
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("contiguous", err$failures)))
})

test_that("single-pass sampling (pass = 1) is valid", {
  catch <- make_catch()
  catch <- catch[catch$reach_id == "R1" & catch$pass_number == 1L, ]
  catch <- rbind(catch, data.frame(
    reach_id = "R2", date = as.Date("2025-06-01"), pass_number = 1L,
    species = "RBT", count = 8L, effort_seconds = 250,
    stringsAsFactors = FALSE
  ))
  expect_no_error(validate_cpue_input(catch, make_meta(), strict = FALSE))
})

# ---- Effort positive ---------------------------------------------------------

test_that("zero effort is reported", {
  catch <- make_catch()
  catch$effort_seconds[1] <- 0
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("effort_seconds", err$failures)))
})

test_that("negative effort is reported", {
  catch <- make_catch()
  catch$effort_seconds[2] <- -10
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("effort_seconds", err$failures)))
})

test_that("NA effort is reported via effort check", {
  catch <- make_catch()
  catch$effort_seconds[1] <- NA_real_
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("effort_seconds", err$failures)))
})

# ---- Counts non-negative integer --------------------------------------------

test_that("negative count is reported", {
  catch <- make_catch()
  catch$count[1] <- -1L
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("negative", err$failures)))
})

test_that("NA count is reported", {
  catch <- make_catch()
  catch$count[1] <- NA_integer_
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("count", err$failures)))
})

test_that("zero count is valid", {
  catch <- make_catch()
  catch$count[3] <- 0L
  expect_no_error(validate_cpue_input(catch, make_meta(), strict = FALSE))
})

# ---- Reach ID consistency ---------------------------------------------------

test_that("catch reach_id absent from metadata is reported", {
  catch <- make_catch()
  catch$reach_id[1] <- "R_ORPHAN"
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("R_ORPHAN", err$failures)))
})

test_that("reach_id in metadata but not in catch is not an error", {
  # Extra metadata rows are fine (not every reach needs to have catch data)
  meta <- rbind(make_meta(), data.frame(reach_id = "R3", length_m = 200,
                                        stringsAsFactors = FALSE))
  expect_no_error(validate_cpue_input(make_catch(), meta, strict = FALSE))
})

test_that("preview truncates beyond 5 orphan IDs and reports total", {
  catch <- make_catch()
  # Add 7 orphan reach IDs
  extra <- data.frame(
    reach_id       = paste0("ORPHAN_", 1:7),
    date           = as.Date("2025-06-01"),
    pass_number    = 1L,
    species        = "BNT",
    count          = 1L,
    effort_seconds = 100,
    stringsAsFactors = FALSE
  )
  catch <- rbind(catch, extra)
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  # "and N more" should appear because > 5 orphans
  expect_true(any(grepl("more", err$failures)))
})

# ---- Species present ---------------------------------------------------------

test_that("reach-date with all-empty species strings is reported", {
  catch <- make_catch()
  catch$species[catch$reach_id == "R1"] <- ""
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_true(any(grepl("species", err$failures, ignore.case = TRUE) |
                    grepl("R1", err$failures)))
})

test_that("reach-date with all-NA species is reported", {
  catch <- make_catch()
  catch$species[catch$reach_id == "R2"] <- NA_character_
  err <- catch_cpue_error(catch, make_meta(), strict = FALSE)
  expect_gt(length(err$failures), 0)
})

test_that("mixed empty and valid species within a reach-date still passes", {
  # One valid species in the group is enough
  catch <- make_catch()
  catch$species[catch$reach_id == "R1" & catch$pass_number != 1L] <- ""
  expect_no_error(validate_cpue_input(catch, make_meta(), strict = FALSE))
})

# ---- Optional column advisories (strict mode) --------------------------------

test_that("strict=TRUE issues at least one warning for missing optional columns", {
  # tryCatch captures the first warning; we just need to confirm one fires.
  w <- tryCatch(
    validate_cpue_input(make_catch(), make_meta(), strict = TRUE),
    warning = function(w) w
  )
  expect_s3_class(w, "warning")
})

test_that("strict=FALSE suppresses optional column warnings", {
  expect_no_warning(
    validate_cpue_input(make_catch(), make_meta(), strict = FALSE)
  )
})

test_that("no warning when all optional catch columns are present", {
  catch <- make_catch()
  catch$amperage <- 3.0
  catch$voltage  <- 400
  meta <- make_meta()
  meta$mean_width_m  <- 8
  meta$area_m2       <- 800
  meta$habitat_class <- "pool"
  meta$crew          <- "Team A"
  meta$gear          <- "Smith-Root"
  expect_no_warning(
    validate_cpue_input(catch, meta, strict = TRUE)
  )
})
