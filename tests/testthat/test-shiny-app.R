# Tests for the bundled Shiny front-end launcher, its helpers, and the core
# server reactive pipeline.

app_test_dir <- function() {
  system.file("shiny-app", package = "electrocpue")
}

source_app_helpers <- function() {
  app_dir <- app_test_dir()
  env <- new.env(parent = globalenv())
  sys.source(file.path(app_dir, "global.R"), envir = env)
  env
}

test_that("run_app is an exported function taking dots", {
  expect_true(is.function(run_app))
  expect_identical(names(formals(run_app)), "...")
})

test_that("bundled Shiny scripts parse", {
  app_dir <- app_test_dir()
  skip_if(app_dir == "", "shiny-app directory not available")

  expect_true(file.exists(file.path(app_dir, "app.R")))
  expect_true(file.exists(file.path(app_dir, "global.R")))
  expect_no_error(parse(file.path(app_dir, "global.R")))
  expect_no_error(parse(file.path(app_dir, "app.R")))
})

test_that("uploaded comma- and tab-separated dates are converted", {
  skip_if_not_installed("tibble")
  helpers <- source_app_helpers()
  input <- data.frame(
    reach_id = "R1", date = "2025-06-01", pass_number = 1L,
    species = "BNT", count = 3L, effort_seconds = 100
  )

  csv <- tempfile(fileext = ".csv")
  tsv <- tempfile(fileext = ".tsv")
  utils::write.csv(input, csv, row.names = FALSE)
  utils::write.table(input, tsv, sep = "\t", row.names = FALSE, quote = FALSE)

  csv_out <- helpers$read_upload(csv, "catch.csv")
  tsv_out <- helpers$read_upload(tsv, "catch.tsv")
  expect_s3_class(csv_out, "tbl_df")
  expect_s3_class(tsv_out, "tbl_df")
  expect_s3_class(csv_out$date, "Date")
  expect_s3_class(tsv_out$date, "Date")
})

test_that("CPUE plot labels the effort basis actually analyzed", {
  skip_if_not_installed("ggplot2")
  helpers <- source_app_helpers()
  summary <- data.frame(reach_id = "R1", species = "BNT", cpue_mean = 0.1)

  seconds <- helpers$plot_cpue(summary, "seconds")
  amp_seconds <- helpers$plot_cpue(summary, "amp_seconds")
  expect_match(seconds$labels$y, "effort-second", fixed = TRUE)
  expect_match(amp_seconds$labels$y, "amp-second", fixed = TRUE)
})

test_that("Shiny server runs the bundled analysis and summary reactives", {
  app_packages <- c("shiny", "bslib", "DT", "ggplot2", "htmltools", "tibble")
  for (package in app_packages) skip_if_not_installed(package)

  app_dir <- app_test_dir()
  old_dir <- setwd(app_dir)
  on.exit(setwd(old_dir), add = TRUE)
  app_env <- new.env(parent = globalenv())
  sys.source("app.R", envir = app_env)

  shiny::testServer(app_env$server, {
    session$setInputs(
      source = "example", method = "auto", effort = "seconds",
      level = 0.95, p_min = 0.40, run = 1
    )
    session$flushReact()

    validation <- validation_r()
    analysis <- analysis_r()
    summary <- summary_r()

    expect_true(validation$ok)
    expect_gt(nrow(analysis), 0)
    expect_gt(nrow(summary), 0)
    expect_true(all(analysis$effort_basis == "seconds"))

    converged <- analysis$converged %in% TRUE
    expect_true(all(analysis$N_lwr[converged] <= analysis$N[converged]))
    expect_true(all(analysis$N_upr[converged] >= analysis$N[converged]))

    finite_ci <- is.finite(summary$density_per_m_lwr) &
      is.finite(summary$density_per_m_upr)
    expect_true(all(
      summary$density_per_m_lwr[finite_ci] <=
        summary$density_per_m_mean[finite_ci]
    ))
    expect_true(all(
      summary$density_per_m_upr[finite_ci] >=
        summary$density_per_m_mean[finite_ci]
    ))
  })
})
