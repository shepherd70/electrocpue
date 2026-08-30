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
#               pooled on the log scale -- each survey's likelihood-based
#               interval combined with between-survey variation by
#               DerSimonian-Laird random effects + modified Knapp-Hartung
#               variance and a Student-t critical value. Positivity is
#               intrinsic (no catch floor). A group resting on < 2 well-
#               identified surveys is flagged weak. N_mean is a simple
#               arithmetic average over converged, depleting surveys; each
#               density_*_mean is the same back-transformed random-effects
#               geometric mean targeted by its interval. Assumption-violated
#               surveys are counted in n_assumption_violated; CPUE, model-free,
#               is averaged over every survey with a finite catch rate.
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
#' @param p_min Minimum estimated capture probability for a survey to enter
#'   the pooled density estimate and confidence interval. Surveys below it
#'   (where the removal estimate is biased) are held out and the reach is
#'   flagged `weak`. Defaults to `0.4`.
#'
#' @return A data frame with one row per group and columns: the grouping
#'   columns; `n_surveys`, `n_converged`, `prop_converged`,
#'   `n_assumption_violated`, `n_identified` (surveys entering the pooled
#'   estimate and interval), `weak` (logical; the pooled estimate rests on
#'   fewer than two well-identified surveys, or omits a survey that fed
#'   `N_mean`); `catch_total`; `N_mean`; pooled geometric means and lower/upper
#'   interval limits for `density_per_m` and `density_per_m2`; and `cpue_mean`.
#'   `N_mean` is the arithmetic mean over converged, depleting surveys. A
#'   density mean is the back-transformed random-effects estimate over the
#'   well-identified surveys and therefore has the same estimand and input set
#'   as its interval. When none qualifies, the density mean falls back to the
#'   arithmetic mean as a descriptive point value, its interval is `NA`, and
#'   `weak` is `TRUE`.
#'
#' @details
#' The estimand for each density column is the random-effects mean log density,
#' back-transformed to the original scale -- equivalently, a pooled geometric
#' mean. Each eligible survey contributes its method-aligned likelihood
#' interval (`N_lwr`/`N_upr`). For two or more surveys, within-survey
#' uncertainty is combined with DerSimonian-Laird between-survey variation
#' and a modified Knapp-Hartung Student-t interval. The modification bounds
#' the Knapp-Hartung variance multiplier below by one, preventing identical
#' survey estimates from erasing their nonzero measurement uncertainty. No
#' arbitrary width cap is applied to the statistical interval.
#'
#' At the default 95 percent level, a single eligible survey retains its
#' likelihood-based density interval exactly. At another requested level the
#' interval is rescaled from the supplied limits because the pass counts needed
#' to refit it are no longer present in `x`. A zero-width discrete likelihood
#' interval is expanded by half a fish on each side before conversion to a
#' log-scale standard error, avoiding infinite inverse-variance weights without
#' imposing an arbitrary relative variance floor.
#'
#' A survey enters the pooled density estimate and interval only when it
#' converged, did not violate the depletion assumption, was identifiable (its
#' abundance is bounded above), and had estimated capture probability at least
#' `p_min`. When fewer than two surveys qualify, or a survey contributing to
#' `N_mean` is held out, the group is flagged `weak`.
#'
#' @references
#' Röver, C., Knapp, G. & Friede, T. (2015). Hartung-Knapp-Sidik-Jonkman
#'   approach and its modification for random-effects meta-analysis with few
#'   studies. BMC Medical Research Methodology 15:99.
#'   \doi{10.1186/s12874-015-0091-1}
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
  if (!is.numeric(level) || length(level) != 1L || !is.finite(level) ||
      level <= 0 || level >= 1) {
    cli::cli_abort("{.arg level} must be a single number in (0, 1).",
                   class = "cpue_analysis_error")
  }
  if (!is.numeric(p_min) || length(p_min) != 1L || !is.finite(p_min) ||
      p_min < 0 || p_min >= 1) {
    cli::cli_abort("{.arg p_min} must be a single number in [0, 1).",
                   class = "cpue_analysis_error")
  }

  x |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by))) |>
    dplyr::group_modify(function(g, key) {
      conv     <- g$converged %in% TRUE
      violated <- conv & (g$note %in% "assumption_violated")
      # Point-estimate set: every converged, depleting survey. Zero-catch
      # surveys are deliberately non-converged because, with unknown capture
      # probability, they cannot identify abundance; their observed zero CPUE
      # remains available below.
      pt_use <- conv & !violated
      # Confidence-interval set: additionally require the survey be well
      # identified (data-only profile upper bounded) AND capture probability
      # >= p_min.
      # Below that the removal estimate is biased and no interval is reliable,
      # so the survey is held out of the interval and the reach is flagged weak.
      ci_use <- pt_use & (g$identifiable %in% TRUE) & !is.na(g$p) & g$p >= p_min
      n_id   <- sum(ci_use)
      weak   <- (n_id < 2) | (n_id < sum(pt_use))

      ci_m  <- .hksj_logci(g$density_per_m[ci_use],
                           (g$N_lwr / g$length_m)[ci_use],
                           (g$N_upr / g$length_m)[ci_use], level,
                           resolution = (1 / g$length_m)[ci_use])
      ci_m2 <- .hksj_logci(g$density_per_m2[ci_use],
                           (g$N_lwr / g$area_m2)[ci_use],
                           (g$N_upr / g$area_m2)[ci_use], level,
                           resolution = (1 / g$area_m2)[ci_use])

      # The density point and interval must estimate the same quantity from
      # the same surveys. A log-scale random-effects interval targets a pooled
      # geometric mean, returned by .hksj_logci() as `mean`; reporting the
      # arithmetic mean here would put a different estimand between those
      # limits. If no survey is eligible for an interval, retain the old
      # descriptive arithmetic point (with NA limits and weak = TRUE).
      density_m_mean <- if (ci_m[["n"]] > 0) {
        ci_m[["mean"]]
      } else if (any(pt_use)) {
        mean(g$density_per_m[pt_use])
      } else {
        NA_real_
      }
      density_m2_mean <- if (ci_m2[["n"]] > 0) {
        ci_m2[["mean"]]
      } else if (any(pt_use)) {
        mean(g$density_per_m2[pt_use])
      } else {
        NA_real_
      }

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
        density_per_m_mean    = density_m_mean,
        density_per_m_lwr     = ci_m[["lwr"]],
        density_per_m_upr     = ci_m[["upr"]],
        density_per_m2_mean   = density_m2_mean,
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
#' survey's likelihood-based uncertainty (`v_i`, from its `N_lwr`/`N_upr`)
#' with the between-survey (temporal) variation by DerSimonian-Laird random
#' effects. The modified Knapp-Hartung variance uses a Student-t critical value
#' and bounds its variance multiplier below by one, so identical point
#' estimates retain their within-survey uncertainty. No arbitrary cap is
#' applied to the interval width.
#'
#' @param d Per-survey density point estimates (well-identified surveys).
#' @param dl,du Per-survey likelihood-based density limits, aligned with
#'   `d`.
#' @param level Confidence level.
#' @param resolution Smallest density increment for each survey (one fish
#'   divided by reach length or area). Used only to give a zero-width discrete
#'   likelihood interval a half-unit continuity width. When `NULL`, a numerical
#'   fallback is used.
#' @param profile_level Confidence/support level of the supplied per-survey
#'   likelihood limits. The legacy argument name is retained for compatibility;
#'   [analyze_cpue()] currently supplies 95 percent limits.
#'
#' @return Named numeric vector `c(mean, lwr, upr, n)`; all `NA` (with
#'   `n = 0`) when no survey is usable.
#'
#' @references
#' Röver, C., Knapp, G. & Friede, T. (2015). Hartung-Knapp-Sidik-Jonkman
#'   approach and its modification for random-effects meta-analysis with few
#'   studies. BMC Medical Research Methodology 15:99.
#'   \doi{10.1186/s12874-015-0091-1}
#'
#' @keywords internal
.hksj_logci <- function(d, dl, du, level = 0.95, resolution = NULL,
                        profile_level = 0.95) {

  if (is.null(resolution)) {
    resolution <- pmax(abs(d), 1) * sqrt(.Machine$double.eps)
  } else if (length(resolution) == 1L) {
    resolution <- rep(resolution, length(d))
  } else if (length(resolution) != length(d)) {
    stop("resolution must have length 1 or the same length as d", call. = FALSE)
  }

  use <- is.finite(d) & d > 0 &
    is.finite(dl) & dl > 0 &
    is.finite(du) & du >= dl &
    dl <= d & d <= du &
    is.finite(resolution) & resolution > 0
  d <- d[use]; dl <- dl[use]; du <- du[use]; resolution <- resolution[use]
  ng <- length(d)
  if (ng == 0) return(c(mean = NA_real_, lwr = NA_real_, upr = NA_real_, n = 0))

  # A discrete likelihood support set can legitimately contain one integer,
  # but treating that set as a continuous zero-variance measurement gives an
  # infinite inverse-variance weight. Represent the singleton by its natural
  # half-fish boundaries before approximating a log-scale standard error.
  singleton <- du == dl
  dl[singleton] <- pmax(d[singleton] - resolution[singleton] / 2,
                        .Machine$double.xmin)
  du[singleton] <- d[singleton] + resolution[singleton] / 2

  z_source <- stats::qnorm(1 - (1 - profile_level) / 2)
  y <- log(d)
  # Use the larger side of an asymmetric likelihood interval. This produces a
  # conservative symmetric log-SE centred on the survey estimate and ensures
  # both source limits are represented.
  s <- pmax(y - log(dl), log(du) - y) / z_source
  v <- s^2

  if (ng == 1) {
    # At the source level preserve the actual asymmetric interval.
    # For a different requested level, rescale the conservative log-SE
    # approximation; the raw pass counts needed to refit exactly are no
    # longer present in analyze_cpue() output.
    if (isTRUE(all.equal(level, profile_level))) {
      return(c(mean = d, lwr = dl, upr = du, n = 1))
    }
    half <- stats::qnorm(1 - (1 - level) / 2) * s
    return(c(mean = d, lwr = exp(y - half), upr = exp(y + half), n = 1))
  }

  w0    <- 1 / v
  ybar0 <- sum(w0 * y) / sum(w0)
  Q     <- sum(w0 * (y - ybar0)^2)
  c1    <- sum(w0) - sum(w0^2) / sum(w0)
  tau2  <- max(0, (Q - (ng - 1)) / c1)        # DerSimonian-Laird between-survey variance
  w     <- 1 / (v + tau2)
  ybar  <- sum(w * y) / sum(w)
  q     <- sum(w * (y - ybar)^2) / (ng - 1)
  # Modified Knapp-Hartung: q < 1 can make the adjusted interval narrower
  # than the conventional random-effects interval and collapses to zero for
  # identical estimates. Bounding q below by one retains measurement error.
  se    <- sqrt(max(1, q) / sum(w))
  half  <- stats::qt(1 - (1 - level) / 2, ng - 1) * se

  c(mean = exp(ybar), lwr = exp(ybar - half), upr = exp(ybar + half), n = ng)
}
