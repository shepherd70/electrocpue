# ============================================================================
# Project:      electrocpue — Electrofishing CPUE Analyzer (R package)
# Script:       R/run_app.R
# Author:       Travis Shepherd
# Description:  Launcher for the bundled standalone Shiny front-end.
# Logic:        Resolves the app directory via system.file() so the app
#               travels with the installed package; guards the Suggested
#               UI packages so a missing one fails early with a clear message.
# Dependencies: shiny, bslib, DT, ggplot2 (all Suggests).
# ============================================================================

#' Launch the electrocpue Shiny application
#'
#' Opens the bundled standalone front-end for the electrocpue workflow
#' (validate, estimate, analyze, summarize). Explore the bundled example
#' data or upload your own catch and reach tables, choose an estimator and
#' effort basis, and read back per-survey abundance with profile-likelihood
#' intervals plus pooled reach density, CPUE, and figures.
#'
#' @details
#' The front-end lives under `inst/shiny-app` and depends on the
#' \pkg{shiny}, \pkg{bslib}, \pkg{DT}, and \pkg{ggplot2} packages, which are
#' listed under `Suggests`. Install any that are missing before calling this
#' function. Loading spinners are shown when \pkg{shinycssloaders} is also
#' installed, but it is optional.
#'
#' @param ... Additional arguments passed to [shiny::runApp()], for example
#'   `port` or `launch.browser`.
#'
#' @return Called for its side effect of starting the Shiny application; does
#'   not return a meaningful value.
#'
#' @examples
#' if (interactive()) {
#'   run_app()
#' }
#'
#' @export
run_app <- function(...) {
  needed  <- c("shiny", "bslib", "DT", "ggplot2")
  missing <- needed[!vapply(needed, requireNamespace, logical(1),
                            quietly = TRUE)]
  if (length(missing) > 0) {
    stop("The electrocpue Shiny app needs the ",
         paste(missing, collapse = ", "),
         " package(s); please install any that are missing.", call. = FALSE)
  }

  app_dir <- system.file("shiny-app", package = "electrocpue")
  if (app_dir == "" || !file.exists(file.path(app_dir, "app.R"))) {
    stop("Shiny app directory not found. Try reinstalling electrocpue.",
         call. = FALSE)
  }

  shiny::runApp(app_dir, ...)
}
