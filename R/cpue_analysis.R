#-------------------------------------------------------------------------------
# Project:      Electrofishing CPUE Analyzer (electrocpue)
# Report:       Engine package - analysis pipeline module
# Script:       cpue_analysis.R
# Author:       Travis Shepherd
# Date:         2026-05-21
# Description:  End-to-end analysis pipeline. Reshapes validated long-format
#               catch data into per-series pass-count vectors, runs removal
#               population estimation on each reach x date x species series,
#               standardizes effort, and expresses abundance as spatial
#               density. Returns one tidy row per reach x date x species.
# Logic:        1. (Optional) validate inputs via validate_cpue_input()
#               2. Reshape to pass-count vectors (build_pass_matrix), filling
#                  zeros for passes a species was absent from
#               3. Estimate population per series (estimate_population)
#               4. Aggregate per-pass effort to reach x date totals
#               5. Join reach extent; compute density per metre and per m^2
#               6. Compute effort-standardized catch rate in the chosen basis
# Dependencies: dplyr  - tidy data manipulation
#               purrr  - iteration over series
#               rlang  - .data pronoun
#               cli    - formatted warnings and errors
#-------------------------------------------------------------------------------


# ---- Reshaping ---------------------------------------------------------------

#' Reshape long catch data into per-series pass-count vectors
#'
#' Collapses validated long-format catch data into one row per
#' `reach_id` x `date` x `species`, with an ordered numeric vector of
#' per-pass catches. Passes a species was not recorded on (but which were
#' conducted at that reach x date) are filled with zero, so the depletion
#' series correctly reflects a true zero catch rather than a dropped pass.
#'
#' @param catch_data A validated long-format catch data frame (see
#'   [validate_cpue_input()]). Must contain `reach_id`, `date`,
#'   `pass_number`, `species`, and `count`.
#'
#' @return A data frame with columns `reach_id`, `date`, `species`,
#'   `n_passes`, and a list-column `counts` holding the pass-ordered
#'   catch vector for each series.
#'
#' @export
#' @family analysis
#' @importFrom rlang .data
#'
#' @examples
#' catch <- data.frame(
#'   reach_id = "R1", date = as.Date("2025-06-01"),
#'   pass_number = c(1L, 2L, 3L), species = "BNT",
#'   count = c(45L, 18L, 7L), effort_seconds = 300
#' )
#' build_pass_matrix(catch)
build_pass_matrix <- function(catch_data) {

  required <- c("reach_id", "date", "pass_number", "species", "count")
  if (!all(required %in% names(catch_data))) {
    cli::cli_abort(
      "catch_data is missing column(s) required for reshaping: \\
       {.field {setdiff(required, names(catch_data))}}.",
      class = "cpue_analysis_error"
    )
  }

  # Collapse any duplicate species x pass rows by summing counts.
  catch_agg <- catch_data |>
    dplyr::group_by(.data$reach_id, .data$date, .data$species, .data$pass_number) |>
    dplyr::summarise(count = sum(.data$count), .groups = "drop")

  # The set of passes actually conducted at each reach x date.
  passes_per_rd <- dplyr::distinct(
    catch_data, .data$reach_id, .data$date, .data$pass_number
  )

  # Complete grid: every species crossed with every conducted pass.
  grid <- catch_data |>
    dplyr::distinct(.data$reach_id, .data$date, .data$species) |>
    dplyr::inner_join(
      passes_per_rd,
      by = c("reach_id", "date"),
      relationship = "many-to-many"
    )

  grid |>
    dplyr::left_join(
      catch_agg,
      by = c("reach_id", "date", "species", "pass_number")
    ) |>
    dplyr::mutate(count = dplyr::coalesce(.data$count, 0)) |>
    dplyr::arrange(.data$reach_id, .data$date, .data$species, .data$pass_number) |>
    dplyr::group_by(.data$reach_id, .data$date, .data$species) |>
    dplyr::summarise(
      n_passes = dplyr::n(),
      counts   = list(.data$count),
      .groups  = "drop"
    )
}


# ---- Full pipeline -----------------------------------------------------------

#' Analyze electrofishing CPUE end to end
#'
#' Validates inputs, estimates removal-depletion abundance for every
#' `reach_id` x `date` x `species` series, standardizes effort, and
#' expresses abundance as spatial density. Returns one tidy row per
#' series, ready for summarizing or plotting.
#'
#' @param catch_data A long-format catch data frame (see
#'   [validate_cpue_input()]).
#' @param reach_metadata A reach metadata data frame with at least
#'   `reach_id` and `length_m`; `area_m2` is used for areal density when
#'   present.
#' @param method Removal estimator passed to [estimate_population()]:
#'   `"auto"` (default), `"zippin"`, or `"carle_strub"`.
#' @param effort_basis Denominator for the effort-standardized catch
#'   rate: `"seconds"` (default) or `"amp_seconds"`. The latter requires
#'   an `amperage` column in `catch_data` whose values are all present
#'   (non-`NA`) and positive.
#' @param alpha,beta Carle & Strub prior parameters (see
#'   [estimate_population()]).
#' @param validate Logical. If `TRUE` (default), run
#'   [validate_cpue_input()] first. Set `FALSE` only when inputs are
#'   already known to be valid: validation also guards structural
#'   assumptions the pipeline relies on -- notably pass numbers being
#'   contiguous from 1 -- and skipping it on, say, non-contiguous passes
#'   (1, 2, 4) lets them collapse into a silently wrong depletion series.
#'
#' @return A data frame with one row per `reach_id` x `date` x `species`
#'   and columns: keys (`reach_id`, `date`, `species`); estimation
#'   (`method`, `n_passes`, `catch_total`, `N`, `N_se`, `p`, `p_se`,
#'   `converged`, `note`); reach extent (`length_m`, `area_m2`); effort
#'   (`effort_seconds`, `effort_amp_seconds`, `effort_basis`, `cpue`);
#'   and density (`density_per_m`, `density_per_m2`). `area_m2`-dependent
#'   columns are `NA` when areal metadata is absent.
#'
#' @export
#' @family analysis
#' @importFrom rlang .data
#'
#' @examples
#' catch <- data.frame(
#'   reach_id = "R1", date = as.Date("2025-06-01"),
#'   pass_number = c(1L, 2L, 3L), species = "BNT",
#'   count = c(45L, 18L, 7L), effort_seconds = 300
#' )
#' meta <- data.frame(reach_id = "R1", length_m = 100)
#' analyze_cpue(catch, meta)
analyze_cpue <- function(catch_data, reach_metadata,
                         method = c("auto", "zippin", "carle_strub"),
                         effort_basis = c("seconds", "amp_seconds"),
                         alpha = 1, beta = 1, validate = TRUE) {

  method       <- match.arg(method)
  effort_basis <- match.arg(effort_basis)

  if (isTRUE(validate)) {
    validate_cpue_input(catch_data, reach_metadata, strict = FALSE)
  }

  has_amp  <- "amperage" %in% names(catch_data)
  has_area <- "area_m2"  %in% names(reach_metadata)

  if (effort_basis == "amp_seconds" && !has_amp) {
    cli::cli_abort(
      c("{.code effort_basis = \"amp_seconds\"} requires an {.field amperage} column in {.arg catch_data}.",
        "i" = "Use {.code effort_basis = \"seconds\"} or add an amperage column."),
      class = "cpue_analysis_error"
    )
  }

  # With amp_seconds the amperage column is the effort multiplier, so an
  # absent (NA) or non-positive value would silently yield an NA or
  # non-positive amp-second effort and a meaningless CPUE. Reject it up front
  # rather than propagating the problem into the output.
  if (effort_basis == "amp_seconds" &&
      (!is.numeric(catch_data$amperage) ||
       anyNA(catch_data$amperage) ||
       any(catch_data$amperage <= 0))) {
    cli::cli_abort(
      c("{.field amperage} must be numeric, non-{.val NA}, and positive for {.code effort_basis = \"amp_seconds\"}.",
        "i" = "A missing or non-positive amperage gives an undefined amp-second effort."),
      class = "cpue_analysis_error"
    )
  }

  # ---- 1. Reshape and estimate per series ----
  pm   <- build_pass_matrix(catch_data)
  ests <- purrr::list_rbind(purrr::map(
    pm$counts,
    function(cv) estimate_population(cv, method = method,
                                     alpha = alpha, beta = beta, quiet = TRUE)
  ))
  res <- dplyr::bind_cols(
    dplyr::select(pm, "reach_id", "date", "species"),
    ests
  )

  # ---- 2. Aggregate per-pass effort to reach x date totals ----
  # Effort is a property of a pass, duplicated across species rows, so it
  # is collapsed per pass before summing to avoid double counting.
  effort <- catch_data |>
    dplyr::group_by(.data$reach_id, .data$date, .data$pass_number) |>
    dplyr::summarise(
      eff_s = dplyr::first(.data$effort_seconds),
      amp   = if (has_amp) dplyr::first(.data$amperage) else NA_real_,
      .groups = "drop"
    ) |>
    dplyr::mutate(amp_s = .data$eff_s * .data$amp) |>
    dplyr::group_by(.data$reach_id, .data$date) |>
    dplyr::summarise(
      effort_seconds     = sum(.data$eff_s),
      effort_amp_seconds = sum(.data$amp_s),
      .groups = "drop"
    )

  res <- dplyr::left_join(res, effort, by = c("reach_id", "date"))

  # ---- 3. Join reach extent ----
  meta_keep <- c("reach_id", "length_m", if (has_area) "area_m2")
  res <- dplyr::left_join(
    res,
    dplyr::select(reach_metadata, dplyr::all_of(meta_keep)),
    by = "reach_id"
  )
  if (!has_area) res$area_m2 <- NA_real_

  # ---- 4. Derived metrics ----
  effort_used <- if (effort_basis == "seconds") {
    res$effort_seconds
  } else {
    res$effort_amp_seconds
  }

  res$effort_basis   <- effort_basis
  res$cpue           <- res$catch_total / effort_used
  res$density_per_m  <- res$N / res$length_m
  res$density_per_m2 <- res$N / res$area_m2

  # ---- 5. Aggregated advisories ----
  # A non-converged series yielded no estimate; an assumption_violated one
  # converged to a number that is not trustworthy. The per-series estimator
  # ran quietly (quiet = TRUE), so both are surfaced here once, in aggregate,
  # rather than as per-series warnings.
  n_fail <- sum(!res$converged)
  if (n_fail > 0) {
    cli::cli_warn(c(
      "{n_fail} of {nrow(res)} series did not yield a usable estimate.",
      "i" = "Inspect the {.field converged} and {.field note} columns."
    ))
  }
  n_violated <- sum(res$note == "assumption_violated")
  if (n_violated > 0) {
    cli::cli_warn(c(
      "{n_violated} of {nrow(res)} series violate the depletion assumption (catch does not decline across passes).",
      "!" = "Their abundance and density estimates are unreliable.",
      "i" = "Inspect the {.field note} column; these are excluded from {.fn summarize_cpue} means."
    ))
  }

  # ---- 6. Order columns ----
  res[, c(
    "reach_id", "date", "species",
    "method", "n_passes", "catch_total",
    "N", "N_se", "p", "p_se", "converged", "note",
    "length_m", "area_m2",
    "effort_seconds", "effort_amp_seconds", "effort_basis", "cpue",
    "density_per_m", "density_per_m2"
  )]
}
