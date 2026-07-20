# ============================================================================
# Project:      electrocpue — Electrofishing CPUE Analyzer (R package)
# Script:       inst/shiny-app/app.R
# Author:       Travis Shepherd
# Description:  Standalone Shiny front-end for the electrocpue workflow:
#               validate -> estimate -> analyze -> summarize, on catch and
#               reach tables (bundled example data or user uploads).
# Logic:        Controls live in the sidebar; a "Run analysis" button drives
#               analyze_cpue(); the reach summary and figures recompute live
#               as the confidence level / p_min sliders move.
# Dependencies: shiny, bslib, ggplot2, DT, electrocpue (the package itself).
# ============================================================================

library(shiny)
library(bslib)
library(ggplot2)
library(DT)
library(electrocpue)

source("global.R")

# ---- UI --------------------------------------------------------------------
ui <- bslib::page_sidebar(
  title = "electrocpue — Electrofishing CPUE Analyzer",
  theme = bslib::bs_theme(version = 5, bootswatch = "flatly",
                          primary = TRITON_NAVY),

  sidebar = bslib::sidebar(
    width = 340,
    title = "Data & options",

    shiny::radioButtons(
      "source", "Data source",
      choices  = c("Bundled example" = "example", "Upload CSV/TSV" = "upload"),
      selected = "example"),

    shiny::conditionalPanel(
      "input.source == 'upload'",
      shiny::fileInput("catch_file", "Catch table",
                       accept = c(".csv", ".tsv", ".txt")),
      shiny::fileInput("reach_file", "Reach table",
                       accept = c(".csv", ".tsv", ".txt")),
      shiny::helpText(
        shiny::HTML(
          "<b>Catch</b> needs: reach_id, date, pass_number, species, count, ",
          "effort_seconds (+ amperage for amp-seconds).<br>",
          "<b>Reach</b> needs: reach_id, length_m (+ area_m2 for areal density).")),
      shiny::div(
        class = "d-flex gap-2",
        shiny::downloadLink("dl_catch", "example catch"),
        shiny::span(" | "),
        shiny::downloadLink("dl_reach", "example reach"))
    ),

    shiny::hr(),

    shiny::selectInput(
      "method", "Estimator",
      choices = c("Auto (Zippin → Carle-Strub)" = "auto",
                  "Zippin"                           = "zippin",
                  "Carle-Strub"                      = "carle_strub")),

    shiny::radioButtons(
      "effort", "Effort basis",
      choices = c("Seconds" = "seconds", "Amp-seconds" = "amp_seconds"),
      inline  = TRUE),

    shiny::sliderInput("level", "Confidence level",
                       min = 0.80, max = 0.99, value = 0.95, step = 0.01),

    shiny::sliderInput("p_min", "Minimum capture probability (p_min)",
                       min = 0.10, max = 0.70, value = 0.40, step = 0.05),
    shiny::helpText("Reaches whose capture probability falls below p_min are",
                    "flagged 'weak' rather than given an unreliable interval."),

    shiny::hr(),
    shiny::actionButton("run", "Run analysis", class = "btn-primary w-100",
                        icon = shiny::icon("play")),
    shiny::helpText(shiny::em(
      "Estimator and effort basis take effect on Run; the sliders update the",
      "summary and plots live."))
  ),

  bslib::navset_card_tab(
    id = "tabs",

    bslib::nav_panel(
      "Data & validation",
      shiny::uiOutput("validation_ui"),
      bslib::layout_columns(
        bslib::card(bslib::card_header("Catch table"),
                    with_spin(DT::DTOutput("catch_preview"))),
        bslib::card(bslib::card_header("Reach table"),
                    with_spin(DT::DTOutput("reach_preview")))
      )
    ),

    bslib::nav_panel(
      "Series results",
      shiny::p(shiny::helpText(
        "One row per reach × date × species: abundance N with its",
        "profile-likelihood interval [N low, N high], capture probability,",
        "density and CPUE.")),
      with_spin(DT::DTOutput("series_tbl"))
    ),

    bslib::nav_panel(
      "Reach summary",
      bslib::layout_columns(
        fill = FALSE,
        bslib::value_box("Reach × species groups",
                         shiny::textOutput("vb_groups"), theme = "primary"),
        bslib::value_box("Weak groups",
                         shiny::textOutput("vb_weak"), theme = "warning"),
        bslib::value_box("Mean density (fish/m)",
                         shiny::textOutput("vb_dens"), theme = "secondary")
      ),
      with_spin(DT::DTOutput("summary_tbl"))
    ),

    bslib::nav_panel(
      "Plots",
      bslib::card(bslib::card_header("Density with confidence intervals"),
                  with_spin(shiny::plotOutput("density_plot", height = "380px"))),
      bslib::card(bslib::card_header("Catch-per-unit-effort"),
                  with_spin(shiny::plotOutput("cpue_plot", height = "320px")))
    ),

    bslib::nav_panel(
      "About",
      shiny::div(
        class = "p-2", style = "max-width: 760px;",
        shiny::h4("What this app does"),
        shiny::p(
          "electrocpue turns multi-pass electrofishing records into",
          "abundance, density, and catch-per-unit-effort estimates. The",
          "workflow is four steps:",
          shiny::strong("validate → estimate → analyze → summarize.")),
        shiny::tags$ul(
          shiny::tags$li(shiny::strong("Estimate:"),
            "removal-depletion abundance per survey (Zippin or Carle-Strub),",
            "with a profile-likelihood interval that respects N ≥ catch and",
            "an 'identifiable' flag when the data cannot bound N from above."),
          shiny::tags$li(shiny::strong("Summarize:"),
            "repeat surveys are pooled to a reach × species mean with a",
            "random-effects (DerSimonian-Laird / Knapp-Hartung) interval.",
            "Groups resting on weak data are flagged, not faked.")),
        shiny::p(shiny::em(
          "Point estimates and standard errors match FSA::removal().")),
        shiny::hr(),
        shiny::p(shiny::HTML(
          paste0("electrocpue ",
                 as.character(utils::packageVersion("electrocpue")),
                 " &middot; Triton Environmental Consultants")))
      )
    )
  )
)

# ---- Server ----------------------------------------------------------------
server <- function(input, output, session) {

  # -- Inputs: bundled example data or uploaded tables -----------------------
  catch_r <- shiny::reactive({
    if (identical(input$source, "example")) {
      electrocpue::example_catch
    } else {
      shiny::req(input$catch_file)
      read_upload(input$catch_file$datapath, input$catch_file$name)
    }
  })

  reach_r <- shiny::reactive({
    if (identical(input$source, "example")) {
      electrocpue::example_reach
    } else {
      shiny::req(input$reach_file)
      read_upload(input$reach_file$datapath, input$reach_file$name)
    }
  })

  # -- Validation ------------------------------------------------------------
  validation_r <- shiny::reactive({
    shiny::req(catch_r(), reach_r())
    tryCatch({
      electrocpue::validate_cpue_input(catch_r(), reach_r(), strict = FALSE)
      list(ok = TRUE, msg = sprintf(
        "Validation passed — %d catch rows across %d reaches, %d species.",
        nrow(catch_r()),
        dplyr::n_distinct(catch_r()$reach_id),
        dplyr::n_distinct(catch_r()$species)))
    }, error = function(e) {
      list(ok = FALSE, msg = conditionMessage(e))
    })
  })

  output$validation_ui <- shiny::renderUI({
    v <- validation_r()
    cls <- if (isTRUE(v$ok)) "alert alert-success" else "alert alert-danger"
    icon <- if (isTRUE(v$ok)) "✓ " else "⚠ "
    shiny::div(class = cls, role = "alert",
               shiny::HTML(paste0("<b>", icon, "</b>",
                                  gsub("\n", "<br>", htmltools::htmlEscape(v$msg)))))
  })

  output$catch_preview <- DT::renderDT({
    shiny::req(catch_r())
    DT::datatable(catch_r(), rownames = FALSE,
                  options = list(pageLength = 8, scrollX = TRUE))
  })

  output$reach_preview <- DT::renderDT({
    shiny::req(reach_r())
    DT::datatable(reach_r(), rownames = FALSE,
                  options = list(pageLength = 8, scrollX = TRUE))
  })

  # -- Analysis: runs only when the button is clicked ------------------------
  analysis_r <- shiny::eventReactive(input$run, {
    shiny::req(catch_r(), reach_r())
    tryCatch(
      shiny::withProgress(message = "Estimating abundance…", value = 0.5, {
        electrocpue::analyze_cpue(
          catch_r(), reach_r(),
          method       = input$method,
          effort_basis = input$effort,
          validate     = TRUE)
      }),
      error = function(e) {
        structure(list(error = conditionMessage(e)), class = "cpue_app_error")
      })
  })

  # -- Summary: recomputes live as level / p_min change ----------------------
  summary_r <- shiny::reactive({
    res <- analysis_r()
    shiny::req(res)
    if (inherits(res, "cpue_app_error")) return(res)
    tryCatch(
      electrocpue::summarize_cpue(res, level = input$level, p_min = input$p_min),
      error = function(e) {
        structure(list(error = conditionMessage(e)), class = "cpue_app_error")
      })
  })

  # Small helper: turn a not-yet-run / errored analysis into a friendly stop.
  need_analysis <- function(x) {
    shiny::validate(shiny::need(
      !is.null(x), "Click 'Run analysis' in the sidebar to compute estimates."))
    shiny::validate(shiny::need(
      !inherits(x, "cpue_app_error"),
      paste("Analysis could not run:",
            if (inherits(x, "cpue_app_error")) x$error else "")))
  }

  output$series_tbl <- DT::renderDT({
    res <- analysis_r()
    need_analysis(res)
    DT::datatable(fmt_series(res), rownames = FALSE,
                  options = list(pageLength = 10, scrollX = TRUE))
  })

  output$summary_tbl <- DT::renderDT({
    s <- summary_r()
    need_analysis(s)
    tbl <- DT::datatable(fmt_summary(s), rownames = FALSE,
                         options = list(pageLength = 10, scrollX = TRUE))
    DT::formatStyle(tbl, "Weak", target = "row",
                    backgroundColor = DT::styleEqual(TRUE, "#FDECEA"))
  })

  # -- Value boxes -----------------------------------------------------------
  output$vb_groups <- shiny::renderText({
    s <- summary_r(); shiny::req(!inherits(s, "cpue_app_error")); nrow(s)
  })
  output$vb_weak <- shiny::renderText({
    s <- summary_r(); shiny::req(!inherits(s, "cpue_app_error"))
    sum(s$weak, na.rm = TRUE)
  })
  output$vb_dens <- shiny::renderText({
    s <- summary_r(); shiny::req(!inherits(s, "cpue_app_error"))
    sprintf("%.2f", mean(s$density_per_m_mean, na.rm = TRUE))
  })

  # -- Figures ---------------------------------------------------------------
  output$density_plot <- shiny::renderPlot({
    s <- summary_r(); need_analysis(s); plot_density(s)
  })
  output$cpue_plot <- shiny::renderPlot({
    s <- summary_r(); need_analysis(s); plot_cpue(s)
  })

  # -- Example-data template downloads ---------------------------------------
  output$dl_catch <- shiny::downloadHandler(
    filename = function() "example_catch.csv",
    content  = function(file) utils::write.csv(electrocpue::example_catch,
                                               file, row.names = FALSE))
  output$dl_reach <- shiny::downloadHandler(
    filename = function() "example_reach.csv",
    content  = function(file) utils::write.csv(electrocpue::example_reach,
                                               file, row.names = FALSE))
}

shinyApp(ui, server)
