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
#               failures one at a time.
# Logic:        1. Check required columns exist in both tables
#               2. Check column types match the input contract
#               3. Check no NA in required identifier columns
#               4. Check pass numbers contiguous from 1 per reach x date
#               5. Check effort > 0 for every record
#               6. Check counts are non-negative integers
#               7. Check reach_id consistency across tables
#               8. Check species present for every reach x date
#               9. Collate failures; abort with classed error if any
# Dependencies: dplyr     - tidy data manipulation
#               purrr     - vectorized iteration without rowwise()
#               rlang     - .data pronoun and classed errors
#               cli       - formatted error and warning messages
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
#'   `"cpue_validation_error"` whose `failures` field contains the
#'   character vector of all detected problems.
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
  # (empty if the check passes). All collected before raising.

  failures <- c(
    check_required_columns(catch_data,     .required_catch_cols, "catch_data"),
    check_required_columns(reach_metadata, .required_reach_cols, "reach_metadata"),
    check_column_types(catch_data,         .required_catch_cols, "catch_data"),
    check_column_types(reach_metadata,     .required_reach_cols, "reach_metadata"),
    check_no_na(
      catch_data,
      c("reach_id", "date", "pass_number", "species"),
      "catch_data"
    ),
    check_no_na(reach_metadata, "reach_id", "reach_metadata"),
    check_pass_contiguity(catch_data),
    check_effort_positive(catch_data),
    check_counts_nonneg_integer(catch_data),
    check_reach_id_consistency(catch_data, reach_metadata),
    check_species_present(catch_data)
  )

  if (length(failures) > 0) {
    cli::cli_abort(
      c(
        "Input validation failed with {length(failures)} issue{?s}:",
        rlang::set_names(failures, rep("x", length(failures)))
      ),
      class = "cpue_validation_error",
      failures = failures
    )
  }

  # Optional column advisories (advisory only, do not fail validation)
  if (isTRUE(strict)) {
    advise_optional_columns(catch_data,     .optional_catch_cols, "catch_data")
    advise_optional_columns(reach_metadata, .optional_reach_cols, "reach_metadata")
  }

  invisible(TRUE)
}


# ---- Schema checks -----------------------------------------------------------

#' Check that required columns are present in a data frame
#'
#' @param data A data frame to check.
#' @param required Named character vector mapping required column names
#'   to their expected R types.
#' @param table_name Human-readable name of the table (used in error
#'   messages).
#'
#' @return Character vector of failure messages; empty if all required
#'   columns are present.
#'
#' @keywords internal
check_required_columns <- function(data, required, table_name) {

  missing_cols <- setdiff(names(required), names(data))
  if (length(missing_cols) == 0) return(character(0))

  as.character(glue::glue(
    "{table_name} is missing required column(s): ",
    "{paste(missing_cols, collapse = ', ')}"
  ))
}


#' Check that columns have expected types
#'
#' Validates type only for columns that are present; absence is handled
#' separately by [check_required_columns()].
#'
#' @inheritParams check_required_columns
#'
#' @return Character vector of failure messages; empty if all present
#'   columns are of the correct type.
#'
#' @keywords internal
check_column_types <- function(data, required, table_name) {

  present_cols <- intersect(names(required), names(data))
  if (length(present_cols) == 0) return(character(0))

  type_messages <- purrr::map_chr(present_cols, function(col) {
    expected <- required[[col]]
    actual   <- class(data[[col]])[1]
    if (type_matches(actual, expected)) {
      NA_character_
    } else {
      as.character(glue::glue(
        "{table_name}${col} should be {expected}, found {actual}"
      ))
    }
  })

  type_messages[!is.na(type_messages)]
}


#' Check whether an actual R class satisfies an expected type spec
#'
#' Numeric accepts both numeric and integer; integer is strict; Date
#' must be Date class.
#'
#' @keywords internal
type_matches <- function(actual, expected) {
  switch(
    expected,
    "numeric"   = actual %in% c("numeric", "integer", "double"),
    "integer"   = actual == "integer",
    "character" = actual == "character",
    "Date"      = actual == "Date",
    actual == expected
  )
}


# ---- Content checks ----------------------------------------------------------

#' Check that key columns contain no NA values
#'
#' @inheritParams check_required_columns
#' @param columns Character vector of column names to check.
#'
#' @return Character vector of failure messages; empty if no NAs found.
#'
#' @keywords internal
check_no_na <- function(data, columns, table_name) {

  present_cols <- intersect(columns, names(data))
  if (length(present_cols) == 0) return(character(0))

  na_counts <- purrr::map_int(present_cols, ~ sum(is.na(data[[.x]])))
  names(na_counts) <- present_cols
  failing <- na_counts[na_counts > 0]
  if (length(failing) == 0) return(character(0))

  purrr::imap_chr(failing, function(n, col) {
    as.character(glue::glue(
      "{table_name}${col} contains {n} NA value(s)"
    ))
  })
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


#' Check that effort values are strictly positive
#'
#' @param catch_data See [validate_cpue_input()].
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_effort_positive <- function(catch_data) {

  if (!"effort_seconds" %in% names(catch_data)) return(character(0))

  effort <- catch_data$effort_seconds
  bad_n  <- sum(effort <= 0 | is.na(effort))
  if (bad_n == 0) return(character(0))

  as.character(glue::glue(
    "catch_data$effort_seconds has {bad_n} non-positive or NA value(s); ",
    "all records must have effort > 0"
  ))
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

  non_na <- counts[!is.na(counts)]

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


#' Check that every reach x date has at least one species record
#'
#' Empty strings and NA both fail this check. Whitespace-only strings
#' currently pass; tighten with `trimws()` if needed in future.
#'
#' @param catch_data See [validate_cpue_input()].
#'
#' @return Character vector of failure messages.
#'
#' @keywords internal
check_species_present <- function(catch_data) {

  required <- c("reach_id", "date", "species")
  if (!all(required %in% names(catch_data))) return(character(0))

  empty <- catch_data |>
    dplyr::group_by(.data$reach_id, .data$date) |>
    dplyr::summarise(
      any_species = any(
        !is.na(.data$species) & nzchar(.data$species)
      ),
      .groups = "drop"
    ) |>
    dplyr::filter(!.data$any_species)

  if (nrow(empty) == 0) return(character(0))

  purrr::pmap_chr(empty, function(reach_id, date, ...) {
    as.character(glue::glue(
      "No species recorded for reach_id='{reach_id}', date={date}"
    ))
  })
}


# ---- Optional column advisor -------------------------------------------------

#' Warn about missing optional columns
#'
#' Advisory only; never fails validation. Surfaces silently-absent
#' columns that change downstream behavior (e.g., missing `amperage`
#' means `effort_basis = "amp_seconds"` is unavailable).
#'
#' @inheritParams check_required_columns
#' @param optional Named character vector of optional columns and types.
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
