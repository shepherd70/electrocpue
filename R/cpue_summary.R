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
# Logic:        Estimand: the reach mean density. For each summary group the
#               well-identified surveys (converged, depletion assumption held,
#               abundance bounded above, capture probability >= p_min) are
#               pooled on the log scale -- each survey's profile-likelihood
#               interval combined with between-survey variation by
#               DerSimonian-Laird random effects + Knapp-Hartung variance, a
#               Student-t critical value, and a x20 half-width cap. Positivity
#               is intrinsic (no catch floor). A group resting on < 2 well-
#               identified surveys is flagged weak. Point means (N_mean,
#               density_*_mean) are simple averages over the converged,
#               depleting surveys; assumption-violated surveys are counted in
#               n_assumption_violated; CPUE, model-free, is averaged over every
#               survey with a finite catch rate.
# Dependencies: dplyr  - grouped summarise via group_modify
#               stats  - qnorm, qt
#               cli    - classed errors
#-------------------------------------------------------------------------------


#' Summarize CPUE analysis output to a coarser grain
#'
#' Aggregates the per-survey output of [analyze_cpue()] (one row per
#' reach x date x species) to a coarser grouping, by default
#' `reach_id` x `species`, collapsing repeat survey dates. Abundance and
#' density means and their confidence intervals are computed over the
#' usable surveys only -- those that converged and whose depletion
#' assumption held; `cpue_mean`, a model-free observed quantity, is
#' averaged over all surveys with a finite catch rate.
#'
#' @param x A data frame produced by [analyze_cpue()].
#' @param by Character vector of grouping columns. Defaults to
#'   `c("reach_id", "species")`.
#' @param level Confidence level for the density intervals. Defaults to
#'   `0.95`.
#'
#' @return A data frame with one row per group and columns: the grouping
#'   columns; `n_surveys`, `n_converged`, `prop_converged`,
#'   `n_assumption_violated`; `catch_total`; `N_mean`; mean and
#'   lower/upper interval limits for `density_per_m` and `density_per_m2`;
#'   and `cpue_mean`.
#'
#' @details
#' Interval method depends on the number of usable surveys in a group
#' (converged and not flagged `assumption_violated`). With a single
#' survey, only the depletion estimate's standard error is available, so a
#' Wald (normal) interval is used. With two or more surveys, a Student-t
#' interval on the survey-level densities is used, which reflects total
#' between-survey variability (biological plus measurement). Lower limits
#' are truncated at zero.
#'
#' With exactly two usable surveys the t-interval has a single degree of
#' freedom (`t_{0.975}` is about 12.7), so the interval is very wide and
#' is better read as a weak bound than a precise one; precision improves
#' quickly as more surveys enter the group.
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
summarize_cpue <- function(x, by = c("reach_id", "species"),
                           level = 0.95, p_min = 0.40) {

  if (!is.data.frame(x)) {
    cli::cli_abort("{.arg x} must be a data frame from {.fn analyze_cpue}.",
                   class = "cpue_analysis_error")
  }
  needed <- c("converged", "identifiable", "note", "catch_total", "N",
              "N_lwr", "N_upr", "p", "length_m", "area_m2", "cpue",
              "density_per_m", "density_per_m2")
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
  if (!is.numeric(p_min) || length(p_min) != 1 || p_min < 0 || p_min >= 1) {
    cli::cli_abort("{.arg p_min} must be a single number in [0, 1).",
                   class = "cpue_analysis_error")
  }

  x |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
    dplyr::group_modify(function(g, key) {
      conv     <- g$converged %in% TRUE
      violated <- conv & (g$note %in% "assumption_violated")
      # Point-estimate set: every converged, depleting survey -- includes the
      # weakly identified and zero-catch ones, so a reach always shows a number.
      pt_use <- conv & !violated
      # Confidence-interval set: additionally require the survey be well
      # identified (profile upper bounded) AND capture probability >= p_min.
      # Below that the removal estimate is biased and no interval is reliable,
      # so the survey is held out of the interval and the reach is flagged weak.
      ci_use <- pt_use & (g$identifiable %in% TRUE) & !is.na(g$p) & g$p >= p_min
      n_id   <- sum(ci_use)
      weak   <- (n_id < 2) | (n_id < sum(pt_use))

      ci_m  <- .hksj_logci(g$density_per_m[ci_use],
                           (g$N_lwr / g$length_m)[ci_use],
                           (g$N_upr / g$length_m)[ci_use], level)
      ci_m2 <- .hksj_logci(g$density_per_m2[ci_use],
                           (g$N_lwr / g$area_m2)[ci_use],
                           (g$N_upr / g$area_m2)[ci_use], level)

      # CPUE (catch / effort) is a model-free observed quantity that does not
      # depend on the depletion fit, so it is averaged over every survey with a
      # finite catch rate (is.finite() also drops an Inf from a zero-effort
      # amp_seconds survey).
      cpue_finite <- g$cpue[is.finite(g$cpue)]
      data.frame(
        n_surveys             = nrow(g),
        n_converged           = sum(conv),
        prop_converged        = sum(conv) / nrow(g),
        n_assumption_violated = sum(violated),
        n_identified          = n_id,
        weak                  = weak,
        catch_total           = sum(g$catch_total),
        N_mean                = if (any(pt_use)) mean(g$N[pt_use]) else NA_real_,
        density_per_m_mean    = if (any(pt_use)) mean(g$density_per_m[pt_use]) else NA_real_,
        density_per_m_lwr     = ci_m[["lwr"]],
        density_per_m_upr     = ci_m[["upr"]],
        density_per_m2_mean   = if (any(pt_use)) mean(g$density_per_m2[pt_use]) else NA_real_,
        density_per_m2_lwr    = ci_m2[["lwr"]],
        density_per_m2_upr    = ci_m2[["upr"]],
        cpue_mean             = if (length(cpue_finite)) mean(cpue_finite) else NA_real_,
        stringsAsFactors      = FALSE
      )
    }) |>
    dplyr::ungroup() |>
    dplyr::arrange(dplyr::across(dplyr::all_of(by)))
}


#' Reach density interval by random-effects pooling on the log scale
#'
#' Pools the well-identified surveys in a group into a reach-level density
#' interval. It works on the log scale, so the interval stays positive and
#' matches the right-skew of removal estimates, and it combines each
#' survey's profile-likelihood uncertainty (`v_i`, from its `N_lwr`/`N_upr`)
#' with the between-survey (temporal) variation by DerSimonian-Laird random
#' effects. The Knapp-Hartung-Sidik-Jonkman variance and a Student-t
#' critical value keep coverage near nominal at the very small number of
#' surveys typical of a monitoring season (simulation: ~0.92-0.95 at two
#' visits). The multiplicative half-width is capped at a factor of 20 so a
#' single discordant pair cannot produce an unbounded bar.
#'
#' @param d Per-survey density point estimates (well-identified surveys).
#' @param dl,du Per-survey profile-likelihood density limits, aligned with
#'   `d`.
#' @param level Confidence level.
#'
#' @return Named numeric vector `c(mean, lwr, upr, n)`; all `NA` (with
#'   `n = 0`) when no survey is usable.
#'
#' @keywords internal
.hksj_logci <- function(d, dl, du, level = 0.95) {

  use <- is.finite(d) & d > 0 & is.finite(dl) & dl > 0 & is.finite(du) & du >= dl
  d <- d[use]; dl <- dl[use]; du <- du[use]
  ng <- length(d)
  if (ng == 0) return(c(mean = NA_real_, lwr = NA_real_, upr = NA_real_, n = 0))

  z <- stats::qnorm(1 - (1 - level) / 2)
  y <- log(d)
  s <- (log(du) - log(dl)) / (2 * z)          # per-survey log-SE from the profile CI
  v <- s^2

  if (ng == 1) {
    return(c(mean = exp(y), lwr = exp(y - z * s), upr = exp(y + z * s), n = 1))
  }

  w0    <- 1 / v
  ybar0 <- sum(w0 * y) / sum(w0)
  Q     <- sum(w0 * (y - ybar0)^2)
  c1    <- sum(w0) - sum(w0^2) / sum(w0)
  tau2  <- max(0, (Q - (ng - 1)) / c1)        # DerSimonian-Laird between-survey variance
  w     <- 1 / (v + tau2)
  ybar  <- sum(w * y) / sum(w)
  se    <- sqrt(sum(w * (y - ybar)^2) / ((ng - 1) * sum(w)))  # Knapp-Hartung
  half  <- min(stats::qt(1 - (1 - level) / 2, ng - 1) * se, log(20))

  c(mean = exp(ybar), lwr = exp(ybar - half), upr = exp(ybar + half), n = ng)
}
