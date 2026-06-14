#-------------------------------------------------------------------------------
# Project:      Electrofishing CPUE Analyzer (electrocpue)
# Report:       Engine package - summary module
# Script:       cpue_summary.R
# Author:       Travis Shepherd
# Date:         2026-05-21
# Description:  Rolls the per-survey output of analyze_cpue() up to a coarser
#               grain (by default reach x species, collapsing repeat survey
#               dates) and attaches confidence intervals to the density
#               estimates.
# Logic:        For each summary group, over the converged surveys:
#                 - single survey  -> Wald CI from the depletion standard error
#                 - >= 2 surveys   -> t-interval on the survey-level densities,
#                                     capturing total (biological + measurement)
#                                     between-survey variability
#               Lower interval limits are truncated at zero (density cannot be
#               negative). Non-converged surveys are excluded from the
#               abundance / density means and intervals but still counted in
#               n_surveys / prop_converged. CPUE, being a model-free observed
#               quantity, is averaged over every survey regardless of
#               convergence.
# Dependencies: dplyr  - grouped summarise via group_modify
#               stats  - qnorm, qt, sd
#               cli    - classed errors
#-------------------------------------------------------------------------------


#' Summarize CPUE analysis output to a coarser grain
#'
#' Aggregates the per-survey output of [analyze_cpue()] (one row per
#' reach x date x species) to a coarser grouping, by default
#' `reach_id` x `species`, collapsing repeat survey dates. Abundance and
#' density means and their confidence intervals are computed over the
#' converged surveys only; `cpue_mean`, a model-free observed quantity,
#' is averaged over all surveys.
#'
#' @param x A data frame produced by [analyze_cpue()].
#' @param by Character vector of grouping columns. Defaults to
#'   `c("reach_id", "species")`.
#' @param level Confidence level for the density intervals. Defaults to
#'   `0.95`.
#'
#' @return A data frame with one row per group and columns: the grouping
#'   columns; `n_surveys`, `n_converged`, `prop_converged`;
#'   `catch_total`; `N_mean`; mean and lower/upper interval limits for
#'   `density_per_m` and `density_per_m2`; and `cpue_mean`.
#'
#' @details
#' Interval method depends on the number of converged surveys in a
#' group. With a single survey, only the depletion estimate's standard
#' error is available, so a Wald (normal) interval is used. With two or
#' more surveys, a Student-t interval on the survey-level densities is
#' used, which reflects total between-survey variability (biological plus
#' measurement). Lower limits are truncated at zero.
#'
#' @export
#' @family analysis
#'
#' @examples
#' catch <- data.frame(
#'   reach_id = "R1", date = as.Date("2025-06-01"),
#'   pass_number = c(1L, 2L, 3L), species = "BNT",
#'   count = c(45L, 18L, 7L), effort_seconds = 300
#' )
#' meta <- data.frame(reach_id = "R1", length_m = 100)
#' summarize_cpue(analyze_cpue(catch, meta))
summarize_cpue <- function(x, by = c("reach_id", "species"), level = 0.95) {

  if (!is.data.frame(x)) {
    cli::cli_abort("{.arg x} must be a data frame from {.fn analyze_cpue}.",
                   class = "cpue_analysis_error")
  }
  needed <- c("converged", "catch_total", "N", "N_se", "length_m",
              "area_m2", "cpue", "density_per_m", "density_per_m2")
  missing_cols <- setdiff(c(by, needed), names(x))
  if (length(missing_cols) > 0) {
    cli::cli_abort(
      c("{.arg x} is missing column(s): {.field {missing_cols}}.",
        "i" = "Did it come from {.fn analyze_cpue}?"),
      class = "cpue_analysis_error"
    )
  }
  if (!is.numeric(level) || length(level) != 1 || level <= 0 || level >= 1) {
    cli::cli_abort("{.arg level} must be a single number in (0, 1).",
                   class = "cpue_analysis_error")
  }

  x |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
    dplyr::group_modify(function(g, key) {
      conv  <- g$converged %in% TRUE
      ci_m  <- .summary_ci(g$density_per_m[conv],
                           (g$N_se / g$length_m)[conv], level)
      ci_m2 <- .summary_ci(g$density_per_m2[conv],
                           (g$N_se / g$area_m2)[conv], level)
      data.frame(
        n_surveys           = nrow(g),
        n_converged         = sum(conv),
        prop_converged      = sum(conv) / nrow(g),
        catch_total         = sum(g$catch_total),
        N_mean              = if (any(conv)) mean(g$N[conv]) else NA_real_,
        density_per_m_mean  = ci_m[["mean"]],
        density_per_m_lwr   = ci_m[["lwr"]],
        density_per_m_upr   = ci_m[["upr"]],
        density_per_m2_mean = ci_m2[["mean"]],
        density_per_m2_lwr  = ci_m2[["lwr"]],
        density_per_m2_upr  = ci_m2[["upr"]],
        # CPUE (catch / effort) is a model-free observed quantity that does
        # not depend on whether the depletion estimator converged, so it is
        # averaged over all surveys, not just the converged ones.
        cpue_mean           = if (any(!is.na(g$cpue))) {
          mean(g$cpue, na.rm = TRUE)
        } else {
          NA_real_
        },
        stringsAsFactors    = FALSE
      )
    }) |>
    dplyr::ungroup() |>
    dplyr::arrange(dplyr::across(dplyr::all_of(by)))
}


#' Mean and confidence interval for a set of survey densities
#'
#' Wald interval from the supplied standard error when a single value is
#' present; Student-t interval on the values when two or more are
#' present. Lower limit truncated at zero.
#'
#' @param values Numeric density estimates (NA values are dropped).
#' @param ses Standard errors aligned with `values` (used only in the
#'   single-value case).
#' @param level Confidence level.
#'
#' @return Named numeric vector `c(mean, lwr, upr)`.
#'
#' @keywords internal
.summary_ci <- function(values, ses, level) {

  keep   <- !is.na(values)
  values <- values[keep]
  ses    <- ses[keep]
  k      <- length(values)

  if (k == 0) {
    return(c(mean = NA_real_, lwr = NA_real_, upr = NA_real_))
  }

  m <- mean(values)

  if (k == 1) {
    se <- ses[1]
    if (is.na(se)) return(c(mean = m, lwr = NA_real_, upr = NA_real_))
    z <- stats::qnorm(1 - (1 - level) / 2)
    return(c(mean = m, lwr = max(0, m - z * se), upr = m + z * se))
  }

  tcrit   <- stats::qt(1 - (1 - level) / 2, df = k - 1)
  se_mean <- stats::sd(values) / sqrt(k)
  c(mean = m, lwr = max(0, m - tcrit * se_mean), upr = m + tcrit * se_mean)
}
