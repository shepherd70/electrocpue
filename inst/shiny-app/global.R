# ============================================================================
# Project:      electrocpue — Electrofishing CPUE Analyzer (R package)
# Script:       inst/shiny-app/global.R
# Author:       Travis Shepherd
# Description:  Shared setup for the bundled Shiny app: project ggplot theme,
#               table/plot helpers, and small utilities. Sourced by app.R
#               before the UI/server are defined.
# Dependencies: ggplot2, dplyr; shinycssloaders (optional, for spinners).
# ============================================================================

TRITON_NAVY  <- "#1B3D5A"   # primary brand colour, matches sibling apps
TRITON_AMBER <- "#E1701A"   # accent for "weak"/caution states

# ---- Project ggplot theme --------------------------------------------------
# theme_bw base with a navy strip and bottom legend, consistent with the
# program's other figures (see the reporting conventions).
theme_electrocpue <- function(base_size = 13) {
  ggplot2::theme_bw(base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = TRITON_NAVY, colour = NA),
      strip.text       = ggplot2::element_text(colour = "white", face = "bold"),
      legend.position  = "bottom",
      plot.title       = ggplot2::element_text(face = "bold")
    )
}

# ---- Small utilities -------------------------------------------------------

# Wrap a UI output in a loading spinner when shinycssloaders is available,
# otherwise return it unchanged (keeps shinycssloaders a soft dependency).
with_spin <- function(ui_el) {
  if (requireNamespace("shinycssloaders", quietly = TRUE)) {
    shinycssloaders::withSpinner(ui_el, color = TRITON_NAVY, type = 4)
  } else {
    ui_el
  }
}

# Read an uploaded catch/reach table (CSV or TSV), coercing a `date` column.
read_upload <- function(path, filename = path) {
  ext <- tolower(tools::file_ext(filename))
  sep <- if (ext %in% c("tsv", "tab", "txt")) "\t" else ","
  df  <- utils::read.csv(path, sep = sep, stringsAsFactors = FALSE,
                         check.names = TRUE)
  if ("date" %in% names(df)) {
    df$date <- as.Date(df$date)
  }
  tibble::as_tibble(df)
}

# A placeholder plot used when there is nothing to show yet.
empty_plot <- function(msg) {
  ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0, y = 0, label = msg,
                      size = 5, colour = "grey40") +
    ggplot2::theme_void()
}

# ---- Display formatters (raw pipeline output -> human-readable tables) ------

fmt_series <- function(df) {
  dplyr::transmute(
    df,
    Reach          = .data$reach_id,
    Date           = .data$date,
    Species        = .data$species,
    Method         = .data$method,
    Passes         = .data$n_passes,
    Catch          = .data$catch_total,
    N              = round(.data$N),
    `N low`        = round(.data$N_lwr),
    `N high`       = round(.data$N_upr),
    Identifiable   = .data$identifiable,
    p              = round(.data$p, 3),
    `Density (/m)` = round(.data$density_per_m, 3),
    CPUE           = round(.data$cpue, 4),
    Note           = .data$note
  )
}

fmt_summary <- function(df) {
  dplyr::transmute(
    df,
    Reach          = .data$reach_id,
    Species        = .data$species,
    Surveys        = .data$n_surveys,
    `Well-ID'd`    = .data$n_identified,
    Weak           = .data$weak,
    `N mean`       = round(.data$N_mean, 1),
    `Density (/m)` = round(.data$density_per_m_mean, 3),
    `Dens. low`    = round(.data$density_per_m_lwr, 3),
    `Dens. high`   = round(.data$density_per_m_upr, 3),
    `CPUE mean`    = round(.data$cpue_mean, 4)
  )
}

# ---- Figures ---------------------------------------------------------------

# Reach density (fish/m) with confidence intervals, faceted by species and
# coloured by whether the group is well-identified or weak.
plot_density <- function(summ) {
  if (is.null(summ) || nrow(summ) == 0) {
    return(empty_plot("No summary to plot."))
  }
  d <- summ
  d$lwr <- ifelse(is.finite(d$density_per_m_lwr), d$density_per_m_lwr, NA_real_)
  d$upr <- ifelse(is.finite(d$density_per_m_upr), d$density_per_m_upr, NA_real_)
  d$Reliability <- ifelse(!is.na(d$weak) & d$weak,
                          "Weak", "Well-identified")

  ggplot2::ggplot(d, ggplot2::aes(x = .data$reach_id,
                                  y = .data$density_per_m_mean)) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$lwr, ymax = .data$upr),
      width = 0.2, colour = "grey55", na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(colour = .data$Reliability), size = 3) +
    ggplot2::facet_wrap(~ .data$species, scales = "free_y") +
    ggplot2::scale_colour_manual(
      values = c("Well-identified" = TRITON_NAVY, "Weak" = TRITON_AMBER)) +
    ggplot2::labs(
      x = "Reach", y = "Density (fish / m)", colour = NULL,
      title = "Reach density with confidence intervals") +
    theme_electrocpue()
}

# Mean catch-per-unit-effort by reach, dodged by species.
plot_cpue <- function(summ) {
  if (is.null(summ) || nrow(summ) == 0) {
    return(empty_plot("No summary to plot."))
  }
  ggplot2::ggplot(summ, ggplot2::aes(x = .data$reach_id, y = .data$cpue_mean,
                                     fill = .data$species)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.7),
                      width = 0.6) +
    ggplot2::scale_fill_viridis_d(option = "D", end = 0.85) +
    ggplot2::labs(
      x = "Reach", y = "Mean CPUE (catch / effort-second)", fill = "Species",
      title = "Catch-per-unit-effort by reach") +
    theme_electrocpue()
}
