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
#               zero total catch      -> N = 0,  converged = TRUE  (no detections)
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
#'   ..., k. Must be non-negative integers with no `NA`.
#' @param method One of `"auto"` (default), `"zippin"`, or
#'   `"carle_strub"`.
#' @param alpha,beta Prior parameters for the Carle & Strub estimator.
#'   Both default to `1` (uniform prior), matching the original paper.
#' @param quiet Logical. If `TRUE`, suppress advisory warnings for
#'   non-convergent or single-pass series. Useful when estimating many
#'   series in a loop. Defaults to `FALSE`.
#'
#' @return A one-row data frame with columns: `method`, `n_passes`,
#'   `catch_total`, `N` (population estimate), `N_se`, `p` (per-pass
#'   capture probability), `p_se`, `converged` (logical), and `note`
#'   (one of `"ok"`, `"single_pass"`, `"zero_catch"`, `"model_failure"`,
#'   `"no_convergence"`, `"assumption_violated"`).
#'
#' @details
#' Point estimates and variances follow the standard removal formulae
#' (Zippin 1956, 1958; Carle & Strub 1978) as implemented in the FSA
#' package, so results are directly comparable to `FSA::removal()`. A
#' zero total catch is reported as `N = 0` (no fish detected -> zero
#' density) rather than as a model failure, which is the more useful
#' convention for downstream CPUE work.
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

  # Converged Zippin fit (includes the trivial zero-catch case) wins. A
  # converged fit may still carry note = "assumption_violated" when the
  # catch does not decline across passes (zippin_estimate flags it), so
  # surface that warning here rather than returning a clean-looking result.
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
    return(.zero_catch_estimate("zippin", k))
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

  est <- .build_estimate(
    method = "zippin", k = k, T = T,
    N = N0, N_var = .zippin_no_var(N0, p, k),
    p = p, p_var = .zippin_p_var(N0, p, k),
    converged = TRUE, note = "ok"
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
  if (alpha <= 0 || beta <= 0) {
    cli::cli_abort("{.arg alpha} and {.arg beta} must be positive.",
                   class = "cpue_estimation_error")
  }

  k <- length(counts)
  T <- sum(counts)
  X <- sum((k - seq_len(k)) * counts)

  if (k == 1L) {
    return(.warn_and_build("carle_strub", k, T, "single_pass", quiet,
      "Single-pass series: Carle & Strub estimation requires >= 2 passes; returning NA."))
  }
  if (T == 0) {
    return(.zero_catch_estimate("carle_strub", k))
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
  est <- .build_estimate(
    method = "carle_strub", k = k, T = T,
    N = N0, N_var = .zippin_no_var(N0, p, k),
    p = p, p_var = .zippin_p_var(N0, p, k),
    converged = TRUE, note = "ok"
  )
  .flag_non_depletion(est, counts, quiet, "Carle & Strub")
}


# ---- Variance helpers (Zippin large-sample formulae) -------------------------

# Maximum iterations for the integer removal searches before declaring
# non-convergence. Generous; real fisheries series converge in << 100.
.max_removal_iter <- 1e6

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
.build_estimate <- function(method, k, T, N, N_var, p, p_var, converged, note) {
  data.frame(
    method      = method,
    n_passes    = as.integer(k),
    catch_total = as.numeric(T),
    N           = as.numeric(N),
    N_se        = if (is.na(N_var)) NA_real_ else sqrt(N_var),
    p           = as.numeric(p),
    p_se        = if (is.na(p_var)) NA_real_ else sqrt(p_var),
    converged   = converged,
    note        = note,
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

#' Build the zero-catch result (no detections -> zero density)
#' @keywords internal
.zero_catch_estimate <- function(method, k) {
  .build_estimate(method, k, T = 0, N = 0, N_var = 0,
                  p = NA_real_, p_var = NA_real_, converged = TRUE,
                  note = "zero_catch")
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
