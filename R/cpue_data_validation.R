#-------------------------------------------------------------------------------
# Project:      Electrofishing CPUE Analyzer (electrocpue)
# Report:       Engine package - input validation module
# Script:       cpue_data_validation.R
# Author:       Travis Shepherd
# Date:         2026-05-16
# Description:  Validates catch and reach metadata inputs before any
#               analytical step. Runs every check regardless of earlier
#               failures and aborts once with a single classed error
#               listing all problems, so users do not iterate through
#               failures one at a time. Generic schema checks (column
#               presence, types, NAs) delegate to the shared tritonIngest
#               validation kernel; CPUE domain rules stay local.
# Logic:        1. Check required columns exist in both tables    (kernel)
#               2. Check column types match the input contract    (kernel)
#                  (required columns, and optional columns when present)
#               3. Check no NA in required identifier columns     (kernel)
#               4. Check both tables contain rows and reach metadata is unique
#               5. Check pass numbers contiguous from 1 per reach x date
#               6. Check effort > 0 and finite for every record
#               7. Check effort/amperage constant within each pass
#               8. Check counts are non-negative integers
#               9. Check reach extent (length_m, area_m2) > 0 and finite for the
#                  reaches catch_data actually references
#              10. Check reach_id consistency across tables
#              11. Check that every catch row identifies a species
#              12. Collate failures; abort once via the kernel's
#                  validation_abort() with class cpue_validation_error
# Dependencies: tritonIngest - shared validation kernel
#               dplyr     - tidy data manipulation
#               purrr     - vectorized iteration without rowwise()
#               rlang     - .data pronoun
#               cli       - formatted advisory warnings
#               glue      - string interpolation
#               utils     - head() for orphan-id preview
#-------------------------------------------------------------------------------


# ---- Input contract specification --------------------------------------------

# Required and optional columns, with expected R types, for each input
# table. Defined as module-level constants (leading dot keeps them out
# of the package's public API) so check helpers do not re-specify the
# schema in multiple places.

.required_catch_cols <- c(
  reach_id       = "character",
  date           = "Date",
  pass_number    = "integer",
  species        = "character",
  count          = "integer",
  effort_seconds = "numeric"
)

.optional_catch_cols <- c(
  amperage = "numeric",
  voltage  = "numeric"
)

.required_reach_cols <- c(
  reach_id = "character",
  length_m = "numeric"
)

.optional_reach_cols <- c(
  mean_width_m  = "numeric",
  area_m2       = "numeric",
  habitat_class = "character",
  crew          = "character",
  gear          = "character"
)


# ---- Top-level validator -----------------------------------------------------

#' Validate electrofishing input data
#'
#' Runs the full battery of input validation checks against catch and
#' reach metadata tables. Every check runs regardless of earlier
#' failures, so the returned error lists every problem at once rather
#' than surfacing them one at a time.
#'
#' Both tables must contain at least one row, and `reach_metadata` must contain
#' exactly one row per `reach_id`. Effort and sampled reach extents used as
#' denominators must be finite and positive; `area_m2` may be `NA` when it is
#' unavailable. Every catch row must have a non-missing, non-blank species
#' identifier.
#'
#' @param catch_data A long-format catch data frame. Required columns:
#'   `reach_id` (chr), `date` (Date), `pass_number` (int), `species`
#'   (chr), `count` (int), `effort_seconds` (num). Optional columns:
#'   `amperage` (num), `voltage` (num).
#' @param reach_metadata A reach metadata data frame. Required columns:
#'   `reach_id` (chr), `length_m` (num). Optional columns:
#'   `mean_width_m`, `area_m2`, `habitat_class`, `crew`, `gear`.
#' @param strict Logical. If `TRUE` (default), missing optional columns
#'   trigger advisory warnings; if `FALSE`, missing optionals are silent.
#'
#' @return Invisibly returns `TRUE` if all validation checks pass.
#'   Otherwise aborts with a classed error of class
#'   `"cpue_validation_error"` (also `"triton_validation_error"`) whose
#'   `failures` field contains the character vector of all detected
#'   problems.
#'
#' @export
#' @family validation
#' @importFrom rlang .data
#'
#' @examples
#' \dontrun{
#' validate_cpue_input(catch_data, reach_metadata)
#' }
validate_cpue_input <- function(catch_data, reach_metadata, strict = TRUE) {

  # Run all checks; each returns a character vector of failure messages
  # (empty if the check passes). All collected before raising. Generic
  # schema checks come from the shared tritonIngest kernel; the remaining
  # checks are CPUE domain rules and stay local.

  # Optional columns need not be present, but when they are their type still
  # matters: a wrong-typed optional column (e.g. a character area_m2) would
  # otherwise pass validation and later abort an arithmetic step downstream.
  # Only the optionals actually present are type-checked.
  opt_catch      <- .optional_catch_cols[names(.optional_catch_cols) %in% names(catch_data)]
  opt_reach      <- .optional_reach_cols[names(.optional_reach_cols) %in% names(reach_metadata)]
  used_reach_ids <- if ("reach_id" %in% names(catch_data)) catch_data$reach_id else NULL

  failures <- c(
    check_input_nonempty(catch_data, "catch_data"),
    check_input_nonempty(reach_metadata, "reach_metadata"),
    tritonIngest::check_required_columns(catch_data,     .required_catch_cols, "catch_data"),
    tritonIngest::check_required_columns(reach_metadata, .required_reach_cols, "reach_metadata"),
    tritonIngest::check_column_types(catch_data,         .required_catch_cols, "catch_data"),
    tritonIngest::check_column_types(reach_metadata,     .required_reach_cols, "reach_metadata"),
    tritonIngest::check_column_types(catch_data,         opt_catch, "catch_data"),
    tritonIngest::check_column_types(reach_metadata,     opt_reach, "reach_metadata"),
    tritonIngest::check_no_na(
      catch_data,
      c("reach_id", "date", "pass_number", "species"),
      "catch_data"
    ),
    tritonIngest::check_no_na(reach_metadata, "reach_id", "reach_metadata"),
    check_reach_id_unique(reach_metadata),
    check_pass_contiguity(catch_data),
    check_effort_positive(catch_data),
    check_within_pass_consistency(catch_data),
    check_counts_nonneg_integer(catch_data),
    check_reach_extent_positive(reach_metadata, used_reach_ids),
    check_reach_id_consistency(catch_data, reach_metadata),
    check_species_present(catch_data)
  )

  tritonIngest::validation_abort(failures, class = "cpue_validation_error")

  # Optional column advisories (advisory only, do not fail validation)
  if (isTRUE(strict)) {
    advise_optional_columns(catch_data,     .optional_catch_cols, "catch_data")
    advise_optional_columns(reach_metadata, .optional_reach_cols, "reach_metadata")
  }

  invisible(TRUE)
}


# ---- Content checks ----------------------------------------------------------
# Generic schema checks (check_required_columns, check_column_types,
# type_matches, check_no_na) live in tritonIngest; only CPUE domain rules
# are defined below.

#' Check that an input table contains at least one row
#'
#' @param data An input data frame.
#' @param table_name Human-readable argument name.
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_input_nonempty <- function(data, table_name) {

  if (!is.data.frame(data) || nrow(data) > 0) return(character(0))
  as.character(glue::glue("{table_name} contains no rows"))
}


#' Check that reach metadata contains one row per reach
#'
#' A duplicate metadata key makes a downstream join multiply analysis rows,
#' silently reweighting the affected reach in summaries.
#'
#' @param reach_metadata See [validate_cpue_input()].
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_reach_id_unique <- function(reach_metadata) {

  if (!"reach_id" %in% names(reach_metadata)) return(character(0))

  ids <- reach_metadata$reach_id
  duplicates <- unique(ids[duplicated(ids) & !is.na(ids)])
  if (length(duplicates) == 0) return(character(0))

  preview <- paste(utils::head(duplicates, 5), collapse = ", ")
  tail_n <- length(duplicates) - 5
  more <- if (tail_n > 0) glue::glue(" (and {tail_n} more)") else ""

  as.character(glue::glue(
    "reach_metadata$reach_id must be unique; duplicate id(s): ",
    "{preview}{more}"
  ))
}

#' Check that pass numbers are contiguous from 1 within each reach x date
#'
#' Multi-pass depletion requires a complete sequential pass series. A
#' reach with passes (1, 2, 4) cannot be estimated; nor can one starting
#' at pass 2.
#'
#' @param catch_data See [validate_cpue_input()].
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_pass_contiguity <- function(catch_data) {

  required <- c("reach_id", "date", "pass_number")
  if (!all(required %in% names(catch_data))) return(character(0))

  # Distinct (reach x date) pass sequences. Species does not affect
  # which passes were conducted, so collapse across species first.
  pass_sets <- catch_data |>
    dplyr::select(dplyr::all_of(required)) |>
    dplyr::distinct() |>
    dplyr::group_by(.data$reach_id, .data$date) |>
    dplyr::summarise(
      passes = list(sort(unique(.data$pass_number))),
      .groups = "drop"
    )

  bad <- pass_sets |>
    dplyr::mutate(
      expected   = purrr::map(.data$passes, ~ seq_len(length(.x))),
      contiguous = purrr::map2_lgl(.data$passes, .data$expected, identical)
    ) |>
    dplyr::filter(!.data$contiguous)

  if (nrow(bad) == 0) return(character(0))

  purrr::pmap_chr(bad, function(reach_id, date, passes, ...) {
    as.character(glue::glue(
      "Pass numbers are not contiguous from 1 at ",
      "reach_id='{reach_id}', date={date}: ",
      "found {paste(passes, collapse = ', ')}"
    ))
  })
}


#' Check effort and amperage are constant within each pass
#'
#' `effort_seconds` -- and `amperage` where present -- describe a pass, not
#' a species, so they are recorded identically on every species row of a
#' given `reach_id` x `date` x `pass_number`. When those rows disagree it
#' is a data-entry error: [analyze_cpue()] would otherwise resolve it
#' silently with `dplyr::first()`, keeping one value and discarding the
#' rest, so it is rejected here instead.
#'
#' @param catch_data See [validate_cpue_input()].
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_within_pass_consistency <- function(catch_data) {

  pass_cols <- c("reach_id", "date", "pass_number")
  if (!all(pass_cols %in% names(catch_data))) return(character(0))

  # Only present, numeric pass-level columns: a wrong type is already
  # reported by the kernel, and comparing it here could abort the battery.
  cols <- intersect(c("effort_seconds", "amperage"), names(catch_data))
  cols <- cols[purrr::map_lgl(cols, ~ is.numeric(catch_data[[.x]]))]
  if (length(cols) == 0) return(character(0))

  problems <- purrr::map_chr(cols, function(col) {
    n_per_group <- catch_data |>
      dplyr::group_by(dplyr::across(dplyr::all_of(pass_cols))) |>
      dplyr::summarise(n_val = dplyr::n_distinct(.data[[col]]), .groups = "drop")
    bad_n <- sum(n_per_group$n_val > 1)
    if (bad_n == 0) {
      NA_character_
    } else {
      as.character(glue::glue(
        "catch_data${col} varies within {bad_n} reach x date x pass ",
        "group(s); it must be constant across the species rows of a pass"
      ))
    }
  })

  problems[!is.na(problems)]
}


#' Flag non-positive (and optionally NA) values in a numeric column
#'
#' Shared by the positivity checks ([check_effort_positive()] and
#' [check_reach_extent_positive()]). A non-numeric column returns no
#' problem here: its wrong type is already reported by the kernel type
#' check, and comparing it would otherwise misbehave or abort the battery
#' mid-run (e.g. `factor <= 0` is all-`NA`, so a downstream
#' `if (bad_n > 0)` would error with "missing value where TRUE/FALSE
#' needed" before [validate_cpue_input()] could collate and abort once).
#'
#' @param values A vector; only acted on when numeric.
#' @param prefix Human-readable column reference for the message.
#' @param requirement Trailing clause stating the rule.
#' @param na_ok If `TRUE`, `NA` is permitted; if `FALSE` (default), `NA`
#'   is treated as a failure.
#'
#' @return Character vector of failure messages (length 0 or 1).
#'
#' @keywords internal
.positive_column_problem <- function(values, prefix, requirement, na_ok = FALSE) {

  if (!is.numeric(values)) return(character(0))

  bad <- values <= 0 | !is.finite(values)
  if (na_ok) bad[is.na(values) & !is.nan(values)] <- FALSE
  bad_n <- sum(bad)
  if (bad_n == 0) return(character(0))

  has_nonfinite <- any((is.infinite(values) | is.nan(values)) & bad)
  kind <- if (has_nonfinite) {
    if (na_ok) "non-positive or non-finite" else "non-positive, non-finite, or NA"
  } else if (na_ok) {
    "non-positive"
  } else {
    "non-positive or NA"
  }
  as.character(glue::glue("{prefix} has {bad_n} {kind} value(s); {requirement}"))
}


#' Check that effort values are strictly positive
#'
#' @param catch_data See [validate_cpue_input()].
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_effort_positive <- function(catch_data) {

  if (!"effort_seconds" %in% names(catch_data)) return(character(0))

  .positive_column_problem(
    catch_data$effort_seconds,
    "catch_data$effort_seconds",
    "all records must have effort > 0"
  )
}


#' Check that reach extent columns are strictly positive
#'
#' `length_m` is the denominator of linear density and must be a
#' positive, non-missing value for every reach; a `0`, negative, or `NA`
#' length otherwise passes type-checking and silently yields an
#' `Inf`/`NaN`/negative density downstream. `area_m2` is optional, so an
#' absent or `NA` value is allowed (it simply yields an `NA` areal
#' density), but where a value is present it must likewise be positive.
#'
#' Only the reaches `catch_data` actually references are checked: a master
#' reach inventory may legitimately carry placeholder extents for reaches
#' not sampled this season, and those rows are dropped by the downstream
#' join in [analyze_cpue()] before any density is computed.
#'
#' @param reach_metadata See [validate_cpue_input()].
#' @param used_reach_ids Optional vector of `reach_id`s referenced by
#'   `catch_data`. When supplied, only those reaches are checked; when
#'   `NULL` (the default), every row is checked.
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_reach_extent_positive <- function(reach_metadata, used_reach_ids = NULL) {

  if (!is.null(used_reach_ids) && "reach_id" %in% names(reach_metadata)) {
    reach_metadata <- reach_metadata[
      reach_metadata$reach_id %in% used_reach_ids, , drop = FALSE
    ]
  }

  problems <- character(0)

  if ("length_m" %in% names(reach_metadata)) {
    problems <- c(problems, .positive_column_problem(
      reach_metadata$length_m,
      "reach_metadata$length_m",
      "every reach must have length_m > 0"
    ))
  }

  if ("area_m2" %in% names(reach_metadata)) {
    problems <- c(problems, .positive_column_problem(
      reach_metadata$area_m2,
      "reach_metadata$area_m2",
      "area_m2 must be > 0 where present",
      na_ok = TRUE
    ))
  }

  problems
}


#' Check that counts are non-negative integers
#'
#' @param catch_data See [validate_cpue_input()].
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_counts_nonneg_integer <- function(catch_data) {

  if (!"count" %in% names(catch_data)) return(character(0))

  counts   <- catch_data$count
  problems <- character(0)

  if (any(is.na(counts))) {
    problems <- c(problems, as.character(glue::glue(
      "catch_data$count contains {sum(is.na(counts))} NA value(s)"
    )))
  }

  nonfinite <- !is.na(counts) & !is.finite(counts)
  if (any(nonfinite)) {
    problems <- c(problems, as.character(glue::glue(
      "catch_data$count contains {sum(nonfinite)} non-finite value(s)"
    )))
  }

  non_na <- counts[!is.na(counts) & is.finite(counts)]

  if (any(non_na < 0)) {
    problems <- c(problems, as.character(glue::glue(
      "catch_data$count contains {sum(non_na < 0)} negative value(s)"
    )))
  }

  if (any(non_na != as.integer(non_na))) {
    problems <- c(
      problems,
      "catch_data$count contains non-integer value(s)"
    )
  }

  problems
}


#' Check that every reach_id in catch_data exists in reach_metadata
#'
#' @param catch_data See [validate_cpue_input()].
#' @param reach_metadata See [validate_cpue_input()].
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_reach_id_consistency <- function(catch_data, reach_metadata) {

  if (!"reach_id" %in% names(catch_data) ||
      !"reach_id" %in% names(reach_metadata)) {
    return(character(0))
  }

  orphans <- setdiff(catch_data$reach_id, reach_metadata$reach_id)
  if (length(orphans) == 0) return(character(0))

  preview <- paste(utils::head(orphans, 5), collapse = ", ")
  tail_n  <- length(orphans) - 5
  more    <- if (tail_n > 0) glue::glue(" (and {tail_n} more)") else ""

  as.character(glue::glue(
    "catch_data references reach_id(s) not in reach_metadata: ",
    "{preview}{more}"
  ))
}


#' Check that every catch record identifies a species
#'
#' Every row contributes a count to a species-specific removal series, so an
#' empty identifier cannot be rescued by another valid species elsewhere in
#' the same reach x date. Empty and whitespace-only strings fail. `NA` values
#' are reported by the shared required-column NA check.
#'
#' @param catch_data See [validate_cpue_input()].
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_species_present <- function(catch_data) {

  if (!"species" %in% names(catch_data) ||
      !is.character(catch_data$species)) {
    return(character(0))
  }

  blank <- !is.na(catch_data$species) & !nzchar(trimws(catch_data$species))
  bad_n <- sum(blank)
  if (bad_n == 0) return(character(0))

  as.character(glue::glue(
    "catch_data$species has {bad_n} empty or whitespace-only value(s); ",
    "every catch record must identify a species"
  ))
}


# ---- Optional column advisor -------------------------------------------------

#' Warn about missing optional columns
#'
#' Advisory only; never fails validation. Surfaces silently-absent
#' columns that change downstream behavior (e.g., missing `amperage`
#' means `effort_basis = "amp_seconds"` is unavailable).
#'
#' @param data A data frame to check.
#' @param optional Named character vector of optional columns and types.
#' @param table_name Human-readable name of the table (used in warning
#'   messages).
#'
#' @keywords internal
advise_optional_columns <- function(data, optional, table_name) {

  missing_cols <- setdiff(names(optional), names(data))
  if (length(missing_cols) == 0) return(invisible(NULL))

  cli::cli_warn(c(
    "Optional column(s) missing from {table_name}:",
    "i" = paste(missing_cols, collapse = ", "),
    "i" = "Some downstream features will be unavailable."
  ))

  invisible(NULL)
}
