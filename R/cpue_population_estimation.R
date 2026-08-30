#-------------------------------------------------------------------------------
# Project:      Electrofishing CPUE Analyzer (electrocpue)
# Report:       Engine package - population estimation module
# Script:       cpue_population_estimation.R
# Author:       Travis Shepherd
# Date:         2026-05-21
# Description:  K-pass removal-depletion population estimators for a single
#               reach x date x species catch series. Implements the Zippin
#               (1956, 1958) maximum-likelihood estimator and the Carle &
#               Strub (1978) weighted-likelihood (Bayesian) estimator, plus
#               an "auto" dispatcher that prefers Zippin and falls back to
#               Carle-Strub when the Zippin model fails.
# Logic:        Point estimates and variances follow the standard removal
#               formulae as implemented in the FSA package (Ogle), so results
#               are directly comparable to that reference. FSA is used only at
#               test time (Suggests); it is not a runtime dependency.
# Conventions:  For catch vector c_1..c_k:
#                 k = number of passes
#                 T = sum(c_i)                  (total removed)
#                 X = sum((k - i) * c_i)        (passes-remaining weighting)
#                 p = T / (k * N - X)           (per-pass capture probability)
# Edge cases:   single pass (k == 1)  -> N = NA, converged = FALSE, warning
#               zero total catch      -> N = NA, identifiable = FALSE (no signal)
#               Zippin model failure  -> N = NA, converged = FALSE, warning
#               runaway search        -> N = NA, converged = FALSE, warning
#                 (note = "no_convergence"; an extreme non-depleting series
#                  can land here rather than "assumption_violated")
#               non-depleting series  -> estimate returned but flagged
#                 converged = TRUE, note = "assumption_violated", warning,
#                 when any pass catches as many as the first, or more --
#                 checked for every method (auto / zippin / carle_strub)
# Dependencies: cli   - formatted warnings and errors
#               glue  - string interpolation
#-------------------------------------------------------------------------------


# ---- Public dispatcher -------------------------------------------------------

#' Estimate population size from K-pass removal data
#'
#' Estimates abundance for a single removal series (one reach x date x
#' species) from successive-pass catch counts. Three methods are
#' available: the Zippin maximum-likelihood estimator, the Carle & Strub
#' weighted-likelihood estimator, and an `"auto"` mode that uses Zippin
#' when its model is valid and falls back to Carle & Strub otherwise.
#'
#' @param counts Numeric vector of catches per pass, ordered pass 1, 2,
#'   ..., k. Must be finite, non-negative integers with no `NA`.
#' @param method One of `"auto"` (default), `"zippin"`, or
#'   `"carle_strub"`.
#' @param alpha,beta Prior parameters for the Carle & Strub estimator.
#'   Each must be one finite positive number. Both default to `1` (uniform
#'   prior), matching the original paper.
#' @param quiet Logical. If `TRUE`, suppress advisory warnings for
#'   non-convergent or single-pass series. Useful when estimating many
#'   series in a loop. Defaults to `FALSE`.
#'
#' @return A one-row data frame with columns: `method`, `n_passes`,
#'   `catch_total`, `N` (population estimate), `N_se`, `N_lwr`/`N_upr`
#'   (method-aligned likelihood-ratio limits for `N`; Zippin uses the
#'   profile likelihood and Carle & Strub uses its prior-weighted likelihood;
#'   both respect `N >= T` and are asymmetric; `N_upr = Inf` explicitly marks
#'   an unbounded upper limit), `p` (per-pass capture probability), `p_se`,
#'   `converged` (logical), `identifiable` (logical; `FALSE` when either the
#'   data-only profile likelihood or the reported method-aligned interval
#'   cannot bound `N` from above -- typically at low capture probability;
#'   an informative prior never promotes data identifiability),
#'   and `note` (one of `"ok"`, `"single_pass"`, `"zero_catch"`,
#'   `"model_failure"`, `"no_convergence"`, `"assumption_violated"`).
#'
#' @details
#' Point estimates and variances follow the standard removal formulae
#' (Zippin 1956, 1958; Carle & Strub 1978) as implemented in the FSA
#' package, so results are directly comparable to `FSA::removal()`.
#'
#' An all-zero catch series cannot identify abundance when capture
#' probability is unknown: at `p = 0`, every possible `N` has the same
#' maximized likelihood. It is therefore returned as `N = NA`,
#' `converged = FALSE`, and `identifiable = FALSE`. The observed catch and
#' CPUE remain zero downstream, but no zero population estimate or
#' zero-width abundance interval is asserted.
#'
#' The removal model assumes catch declines across passes as the local
#' population is depleted, so the first pass should catch the most fish.
#' When some later pass catches as many as the first, or more, the
#' depletion assumption is violated: an estimator may still return a
#' numeric estimate, but it is not trustworthy. Such a series is flagged
#' with `note = "assumption_violated"` (and a warning) rather than `"ok"`.
#' The check spans every pass and applies to all methods, so `"auto"`
#' flags a non-depleting series whether Zippin converged on it or the
#' Carle & Strub fallback was used. (A non-depleting series so extreme that
#' the search does not converge is instead returned as
#' `note = "no_convergence"`, `N = NA`.)
#'
#' @references
#' Zippin, C. (1956). An evaluation of the removal method of estimating
#'   animal populations. Biometrics 12:163-189.
#'
#' Zippin, C. (1958). The removal method of population estimation.
#'   Journal of Wildlife Management 22:82-90.
#'
#' Carle, F.L. & Strub, M.R. (1978). A new method for estimating
#'   population size from removal data. Biometrics 34:621-630.
#'
#' @export
#' @family estimation
#'
#' @examples
#' estimate_population(c(45, 18, 7))
#' estimate_population(c(38, 26, 12), method = "carle_strub")
estimate_population <- function(counts,
                                method = c("auto", "zippin", "carle_strub"),
                                alpha = 1, beta = 1, quiet = FALSE) {

  method <- match.arg(method)

  if (method == "zippin") {
    return(zippin_estimate(counts, quiet = quiet))
  }
  if (method == "carle_strub") {
    return(carle_strub_estimate(counts, alpha = alpha, beta = beta, quiet = quiet))
  }

  # ---- auto: prefer Zippin, fall back to Carle-Strub on model failure ----
  z <- zippin_estimate(counts, quiet = TRUE)

  # No depletion estimator can infer abundance from an all-zero series when
  # capture probability is unknown. Do not send it to the fallback estimator:
  # both methods have the same structural absence of information.
  if (identical(z$note, "zero_catch")) {
    if (!quiet) .warn_zero_catch()
    return(z)
  }

  # A converged fit may still carry note = "assumption_violated" when the
  # catch does not decline across passes (zippin_estimate flags it), so surface
  # that warning here rather than returning a clean-looking result.
  if (isTRUE(z$converged)) {
    if (!quiet && identical(z$note, "assumption_violated")) {
      cli::cli_warn(c(
        "Catch does not decline across passes; the depletion assumption is violated.",
        "!" = "Zippin still converged, but the estimate is unreliable.",
        "i" = "Interpret with great caution (see the {.field note} column)."
      ))
    }
    return(z)
  }

  # Single-pass data cannot be rescued by any depletion method.
  if (identical(z$note, "single_pass")) {
    if (!quiet) {
      cli::cli_warn(
        "Single-pass series: depletion estimation is not possible; returning NA."
      )
    }
    return(z)
  }

  # Zippin model failure -> try the more robust Carle-Strub estimator. The
  # branches below are mutually exclusive on (converged, note), so their
  # order is irrelevant: failed outright, then the non-depleting flag, then
  # the residual weak-but-genuine depletion that only Carle-Strub rescued.
  cs <- carle_strub_estimate(counts, alpha = alpha, beta = beta, quiet = TRUE)
  if (!quiet) {
    if (!isTRUE(cs$converged)) {
      cli::cli_warn(
        "Both Zippin and Carle & Strub failed to produce a stable estimate; returning NA."
      )
    } else if (identical(cs$note, "assumption_violated")) {
      cli::cli_warn(c(
        "Zippin model failed; used Carle & Strub estimate instead.",
        "!" = "Catch does not decline across passes; the depletion assumption is violated.",
        "i" = "Interpret the estimate with great caution (see the {.field note} column)."
      ))
    } else {
      cli::cli_warn(c(
        "Zippin model failed; used Carle & Strub estimate instead.",
        "i" = "Catch series shows weak depletion; interpret with caution."
      ))
    }
  }
  cs
}


# ---- Search bound ------------------------------------------------------------

# Maximum iterations for the integer removal searches before declaring
# non-convergence. A backstop against a pathological (e.g. violently
# non-depleting) series rather than a tuning knob: real fisheries series
# converge in << 100 steps, so this leaves a ~four-order-of-magnitude safety
# margin. A search that exhausts it returns note = "no_convergence", N = NA.
.max_removal_iter <- 1e6


# ---- Zippin maximum-likelihood estimator -------------------------------------

#' Zippin K-pass removal estimator
#'
#' Maximum-likelihood depletion estimator assuming constant per-pass
#' capture probability (Zippin 1956, 1958).
#'
#' @inheritParams estimate_population
#'
#' @return A one-row data frame in the format described in
#'   [estimate_population()].
#'
#' @export
#' @family estimation
#'
#' @examples
#' zippin_estimate(c(45, 18, 7))
zippin_estimate <- function(counts, quiet = FALSE) {

  .check_counts(counts)

  k <- length(counts)
  T <- sum(counts)
  X <- sum((k - seq_len(k)) * counts)

  # Structural edge cases handled before fitting.
  if (k == 1L) {
    return(.warn_and_build("zippin", k, T, "single_pass", quiet,
      "Single-pass series: Zippin estimation requires >= 2 passes; returning NA."))
  }
  if (T == 0) {
    return(.zero_catch_estimate("zippin", k, quiet))
  }

  # Zippin model-failure condition (insufficient depletion). Matches the
  # check used by FSA::removal(): X <= ((T - 1)(k - 1) / 2) - 1.
  if (X <= (((T - 1) * (k - 1)) / 2) - 1) {
    return(.warn_and_build("zippin", k, T, "model_failure", quiet,
      "Zippin model failure: catch series shows insufficient depletion; returning NA."))
  }

  # Integer maximum-likelihood search with 0.5 continuity correction.
  N0   <- T
  iter <- 0L
  while ((N0 + 0.5) * ((k * N0 - X - T)^k) >= (N0 - T + 0.5) * ((k * N0 - X)^k)) {
    N0   <- N0 + 1
    iter <- iter + 1L
    # nocov start
    # Unreachable in practice: once a series passes the model-failure guard
    # above, this likelihood search converges within a few steps. Retained
    # as a hard stop against a pathological input we have not foreseen.
    if (iter > .max_removal_iter) {
      return(.warn_and_build("zippin", k, T, "no_convergence", quiet,
        "Zippin search failed to converge; returning NA."))
    }
    # nocov end
  }

  p <- T / (k * N0 - X)

  pci <- .profile_ci_N(counts)
  est <- .build_estimate(
    method = "zippin", k = k, T = T,
    N = N0, N_var = .zippin_no_var(N0, p, k),
    p = p, p_var = .zippin_p_var(N0, p, k),
    converged = TRUE, note = "ok",
    N_lwr = pci$lwr, N_upr = pci$upr, identifiable = pci$identifiable
  )
  .flag_non_depletion(est, counts, quiet, "Zippin")
}


# ---- Carle & Strub weighted-likelihood estimator -----------------------------

#' Carle & Strub K-pass removal estimator
#'
#' Weighted-likelihood (Bayesian, uniform-prior) depletion estimator
#' (Carle & Strub 1978). More robust than Zippin when depletion is weak,
#' and the recommended default for routine use.
#'
#' The reported standard errors (`N_se`, `p_se`) are the Zippin
#' large-sample variance formulae evaluated at the Carle & Strub point
#' estimate, which is what `FSA::removal()` returns. Carle & Strub do not
#' derive a separate variance, so this is the conventional approximation
#' rather than an exact Carle & Strub standard error.
#'
#' The abundance limits use a likelihood-ratio inversion of the same
#' beta-weighted likelihood that produces the Carle & Strub point estimate.
#' Consequently custom `alpha` and `beta` values affect both the point and its
#' limits; a converged point estimate is always contained by its reported
#' interval. These are weighted-likelihood limits, not Zippin profile limits.
#' The `identifiable` flag requires both the weighted interval and the
#' data-only profile to be bounded: a prior may regularize the weighted
#' interval, but it cannot turn a weak catch series into informative depletion
#' data. An unbounded weighted upper limit is returned as `Inf`, never as the
#' finite internal search cap.
#'
#' Unlike Zippin, Carle & Strub does not reject a non-depleting series
#' outright: when the catch does not decline across passes (some later
#' pass catches as many fish as the first, or more) it can still converge
#' to a numeric estimate. That estimate is returned, but flagged with
#' `note = "assumption_violated"` and a warning rather than `note = "ok"`,
#' because the depletion assumption it rests on has failed.
#'
#' @inheritParams estimate_population
#'
#' @return A one-row data frame in the format described in
#'   [estimate_population()].
#'
#' @export
#' @family estimation
#'
#' @examples
#' carle_strub_estimate(c(45, 18, 7))
carle_strub_estimate <- function(counts, alpha = 1, beta = 1, quiet = FALSE) {

  .check_counts(counts)
  valid_prior <- function(x) {
    is.numeric(x) && length(x) == 1L && is.finite(x) && x > 0
  }
  if (!valid_prior(alpha) || !valid_prior(beta)) {
    cli::cli_abort(
      "{.arg alpha} and {.arg beta} must each be one finite positive number.",
      class = "cpue_estimation_error"
    )
  }

  k <- length(counts)
  T <- sum(counts)
  X <- sum((k - seq_len(k)) * counts)

  if (k == 1L) {
    return(.warn_and_build("carle_strub", k, T, "single_pass", quiet,
      "Single-pass series: Carle & Strub estimation requires >= 2 passes; returning NA."))
  }
  if (T == 0) {
    return(.zero_catch_estimate("carle_strub", k, quiet))
  }

  # Posterior-mode integer search (Carle & Strub 1978, eq. for N-hat).
  i    <- seq_len(k)
  N0   <- T
  iter <- 0L
  while (((N0 + 1) / (N0 - T + 1)) *
         prod((k * N0 - X - T + beta + k - i) /
              (k * N0 - X + alpha + beta + k - i)) >= 1) {
    N0   <- N0 + 1
    iter <- iter + 1L
    if (iter > .max_removal_iter) {
      return(.warn_and_build("carle_strub", k, T, "no_convergence", quiet,
        "Carle & Strub search did not converge (no depletion signal); returning NA."))
    }
  }

  p <- T / (k * N0 - X)

  # Convergence reached. The point estimate is numerically produced, but a
  # removal series should show net decline as the local population is
  # removed; .flag_non_depletion() downgrades note to "assumption_violated"
  # (with a warning) when it does not, rather than reporting a clean "ok".
  wci <- .carle_strub_ci_N(counts, N_hat = N0, alpha = alpha, beta = beta)
  data_identifiable <- .profile_ci_N(counts)$identifiable
  est <- .build_estimate(
    method = "carle_strub", k = k, T = T,
    N = N0, N_var = .zippin_no_var(N0, p, k),
    p = p, p_var = .zippin_p_var(N0, p, k),
    converged = TRUE, note = "ok",
    N_lwr = wci$lwr, N_upr = wci$upr,
    identifiable = wci$identifiable && data_identifiable
  )
  .flag_non_depletion(est, counts, quiet, "Carle & Strub")
}


# ---- Variance helpers (Zippin large-sample formulae) -------------------------

#' Large-sample variance of the Zippin abundance estimate
#' @keywords internal
.zippin_no_var <- function(N0, p, k) {
  q   <- 1 - p
  num <- N0 * (1 - q^k) * (q^k)
  den <- ((1 - q^k)^2) - ((p * k)^2) * q^(k - 1)
  if (!is.finite(den) || den <= 0) return(NA_real_)
  num / den
}

#' Large-sample variance of the Zippin capture-probability estimate
#' @keywords internal
.zippin_p_var <- function(N0, p, k) {
  q   <- 1 - p
  num <- ((q * p)^2) * (1 - q^k)
  den <- N0 * (q * ((1 - q^k)^2) - ((p * k)^2) * (q^k))
  if (!is.finite(den) || den <= 0) return(NA_real_)
  num / den
}


# ---- Result construction and input checks ------------------------------------

#' Validate a removal count vector
#'
#' Programming-error guard (distinct from the ecological edge cases
#' single-pass / zero-catch, which are handled by the estimators and
#' return `NA` rather than aborting).
#'
#' @keywords internal
.check_counts <- function(counts) {
  if (!is.numeric(counts) || length(counts) < 1L) {
    cli::cli_abort("{.arg counts} must be a non-empty numeric vector.",
                   class = "cpue_estimation_error")
  }
  if (anyNA(counts)) {
    cli::cli_abort("{.arg counts} must not contain NA.",
                   class = "cpue_estimation_error")
  }
  if (any(!is.finite(counts))) {
    cli::cli_abort("{.arg counts} must contain only finite values.",
                   class = "cpue_estimation_error")
  }
  if (any(counts < 0)) {
    cli::cli_abort("{.arg counts} must be non-negative.",
                   class = "cpue_estimation_error")
  }
  if (any(counts != round(counts))) {
    cli::cli_abort("{.arg counts} must be whole numbers.",
                   class = "cpue_estimation_error")
  }
  invisible(TRUE)
}

#' Assemble the standard one-row estimate result
#' @keywords internal
.build_estimate <- function(method, k, T, N, N_var, p, p_var, converged, note,
                            N_lwr = NA_real_, N_upr = NA_real_,
                            identifiable = FALSE) {
  data.frame(
    method       = method,
    n_passes     = as.integer(k),
    catch_total  = as.numeric(T),
    N            = as.numeric(N),
    N_se         = if (is.na(N_var)) NA_real_ else sqrt(N_var),
    N_lwr        = as.numeric(N_lwr),
    N_upr        = as.numeric(N_upr),
    p            = as.numeric(p),
    p_se         = if (is.na(p_var)) NA_real_ else sqrt(p_var),
    converged    = converged,
    identifiable = identifiable,
    note         = note,
    stringsAsFactors = FALSE
  )
}

#' Build a non-convergent / single-pass result and optionally warn
#' @keywords internal
.warn_and_build <- function(method, k, T, note, quiet, message) {
  if (!quiet) cli::cli_warn(message)
  .build_estimate(method, k, T, N = NA_real_, N_var = NA_real_,
                  p = NA_real_, p_var = NA_real_, converged = FALSE, note = note)
}

#' Warn that a zero-catch series cannot identify abundance
#' @keywords internal
.warn_zero_catch <- function() {
  cli::cli_warn(c(
    "Zero-catch series: abundance cannot be identified; returning NA.",
    "i" = "With unknown capture probability, no detections do not establish a zero population."
  ))
}

#' Build the unidentifiable zero-catch result
#'
#' The observed catch is zero, but with unknown capture probability the
#' removal likelihood is flat in `N` at `p = 0`. Consequently there is no
#' population estimate or finite abundance interval.
#' @keywords internal
.zero_catch_estimate <- function(method, k, quiet = FALSE) {
  if (!quiet) .warn_zero_catch()
  .build_estimate(method, k, T = 0, N = NA_real_, N_var = NA_real_,
                  p = NA_real_, p_var = NA_real_, converged = FALSE,
                  note = "zero_catch", identifiable = FALSE)
}

#' Flag a converged estimate whose catch series does not deplete
#'
#' The removal model assumes catch declines across passes as the local
#' population is removed, so the first pass should catch the most fish.
#' When any later pass catches as many as the first, or more, that
#' assumption has failed: the estimate is numerically valid but not
#' trustworthy, so it is returned with `note = "assumption_violated"` (and
#' an advisory warning) rather than `"ok"`. The test spans every pass, not
#' just the endpoints, so an interior pass that spikes above the first
#' pass is caught too.
#'
#' Applied identically by [zippin_estimate()] and [carle_strub_estimate()]
#' on their converged paths, so the flag does not depend on which estimator
#' produced the number -- in particular `method = "auto"` flags a
#' non-depleting series whether Zippin converged on it or the Carle & Strub
#' fallback was used.
#'
#' @param est A converged one-row estimate from [.build_estimate()].
#' @param counts The pass-ordered catch vector (length >= 2 here).
#' @param quiet Suppress the advisory warning.
#' @param estimator Human-readable estimator name for the warning.
#'
#' @return `est`, with `note` set to `"assumption_violated"` when the
#'   series does not deplete; otherwise unchanged.
#'
#' @keywords internal
.flag_non_depletion <- function(est, counts, quiet, estimator) {

  if (any(counts[-1L] >= counts[1L])) {
    est$note <- "assumption_violated"
    if (!quiet) {
      cli::cli_warn(c(
        "{estimator}: catch does not decline across passes (a later pass catches as many as the first, or more).",
        "!" = "The removal-depletion assumption is violated; the estimate is unreliable.",
        "i" = "Inspect the catch series before using N (see the {.field note} column)."
      ))
    }
  }

  est
}

#' Carle & Strub weighted-likelihood interval for removal abundance
#'
#' Inverts the same beta-weighted removal likelihood whose adjacent-value
#' ratio is used by [carle_strub_estimate()] to locate its integer point
#' estimate. Keeping the prior parameters in the interval calculation avoids
#' reporting limits from a different model that may not contain the estimate.
#'
#' The weighted likelihood, up to terms constant in `N`, is
#' `N! / (N - T)! * B(T + alpha, k * N - X - T + beta)`. The likelihood-ratio
#' acceptance set is searched with constant-memory integer binary searches.
#'
#' @param counts Pass-ordered catch vector (length >= 2, `sum(counts) > 0`).
#' @param N_hat Carle & Strub integer point estimate.
#' @param alpha,beta Positive beta-prior parameters.
#' @param level Confidence/support level. Defaults to `0.95`.
#' @param cap_mult Search-cap multiplier applied to both total catch and the
#'   point estimate. Including the point estimate is essential for strongly
#'   informative custom priors that move `N_hat` well beyond total catch.
#'
#' @return A list with `lwr`, `upr` (abundance limits; `upr = Inf` when the
#'   weighted likelihood remains admissible at the internal search cap) and
#'   `identifiable` (logical).
#'
#' @keywords internal
.carle_strub_ci_N <- function(counts, N_hat, alpha = 1, beta = 1,
                              level = 0.95, cap_mult = 50) {

  k <- length(counts)
  T <- sum(counts)
  X <- sum((k - seq_len(k)) * counts)
  cap <- floor(max(T * cap_mult, T + 300,
                   N_hat * cap_mult, N_hat + 300))

  loglik <- function(N) {
    failures <- k * N - X - T
    if (!is.finite(N) || N < T || failures < 0) return(-Inf)

    lgamma(N + 1) - lgamma(N - T + 1) +
      lbeta(T + alpha, failures + beta)
  }

  mode_ll <- loglik(N_hat)
  cutoff <- mode_ll - stats::qchisq(level, 1) / 2
  inside <- function(N) loglik(N) >= cutoff

  # The weighted likelihood is unimodal around N_hat. Find the first and last
  # accepted integers without allocating the potentially very large grid.
  lo <- T
  hi <- N_hat
  while (lo < hi) {
    mid <- floor((lo + hi) / 2)
    if (inside(mid)) hi <- mid else lo <- mid + 1
  }
  lwr <- lo

  if (inside(cap)) {
    upr <- Inf
    identifiable <- FALSE
  } else {
    lo <- N_hat
    hi <- cap
    while (lo < hi) {
      mid <- ceiling((lo + hi) / 2)
      if (inside(mid)) lo <- mid else hi <- mid - 1
    }
    upr <- lo
    identifiable <- TRUE
  }

  list(lwr = lwr, upr = upr, identifiable = identifiable)
}

#' Profile-likelihood confidence interval for removal abundance
#'
#' Inverts the constant-capture-probability removal likelihood to bracket
#' the abundance `N`. Unlike the symmetric large-sample Wald interval from
#' `N_se`, the profile limits respect the hard lower boundary `N >= T` (the
#' total catch -- a reach cannot hold fewer fish than were removed from it)
#' and the right-skew of the estimate, and they widen honestly when
#' depletion is weak.
#'
#' The search runs `N` up to `cap_mult * T`, using integer binary searches
#' over the unimodal profile likelihood rather than allocating every
#' candidate abundance. Its memory use is therefore constant even for very
#' large catches. If the likelihood is still
#' admissible at that cap the upper limit is unbounded -- the data cannot
#' bound abundance from above, which happens at low capture probability --
#' and `upr = Inf`, `identifiable = FALSE` are returned so downstream summaries
#' can flag the series without exposing the finite search cap as a statistical
#' limit.
#'
#' @param counts Pass-ordered catch vector (length >= 2, `sum(counts) > 0`).
#' @param level Confidence level. Defaults to `0.95`.
#' @param cap_mult Upper search bound as a multiple of the total catch.
#'
#' @return A list with `lwr`, `upr` (abundance limits; `upr = Inf` when the
#'   profile remains admissible at the internal search cap) and `identifiable`
#'   (logical).
#'
#' @keywords internal
.profile_ci_N <- function(counts, level = 0.95, cap_mult = 50) {

  k <- length(counts)
  T <- sum(counts)
  R <- c(0, cumsum(counts)[-k])              # fish removed before each pass
  X <- sum(R)                                # == sum((k - i) * counts)
  cap <- floor(max(T * cap_mult, T + 300))

  # Scalar profile log-likelihood (terms constant in N dropped). Keeping this
  # scalar is important: the former T:cap grid allocated several vectors and
  # a k-by-length(grid) matrix, so a perfectly valid large catch could exhaust
  # memory before estimation began.
  loglik <- function(N) {
    denom <- k * N - X
    if (!is.finite(N) || N < T || denom < T) return(-Inf)

    term <- sum(
      lgamma(N - R + 1) - lgamma(N - R - counts + 1)
    )

    # At p = 1, the limiting contribution from uncaptured fish is zero.
    # Evaluate it directly instead of forming 0 * log(0).
    if (denom == T) return(term)

    phat <- T / denom
    term + T * log(phat) + (denom - T) * log1p(-phat)
  }

  # Locate the first integer mode of the unimodal profile. On a flat pair,
  # move left to match which.max() on the former exhaustive grid.
  lo <- T
  hi <- cap
  while (lo < hi) {
    mid <- floor((lo + hi) / 2)
    if (loglik(mid + 1) > loglik(mid)) lo <- mid + 1 else hi <- mid
  }
  mode <- lo
  cutoff <- loglik(mode) - stats::qchisq(level, 1) / 2
  inside <- function(N) loglik(N) >= cutoff

  # The likelihood-ratio acceptance set is contiguous around the mode. Find
  # its first and last integer with two more binary searches.
  lo <- T
  hi <- mode
  while (lo < hi) {
    mid <- floor((lo + hi) / 2)
    if (inside(mid)) hi <- mid else lo <- mid + 1
  }
  lwr <- lo

  if (inside(cap)) {
    upr <- Inf
    identifiable <- FALSE
  } else {
    lo <- mode
    hi <- cap
    while (lo < hi) {
      mid <- ceiling((lo + hi) / 2)
      if (inside(mid)) lo <- mid else hi <- mid - 1
    }
    upr <- lo
    identifiable <- TRUE
  }

  list(lwr = lwr, upr = upr, identifiable = identifiable)
}
