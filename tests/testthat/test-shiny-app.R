# Tests for the bundled Shiny front-end launcher. The app itself is not
# driven headlessly here; these guard the contract (exported launcher) and
# that the bundled scripts are syntactically valid R.

test_that("run_app is an exported function taking dots", {
  expect_true(is.function(run_app))
  expect_identical(names(formals(run_app)), "...")
})

test_that("bundled Shiny scripts parse", {
  app_dir <- system.file("shiny-app", package = "electrocpue")
  skip_if(app_dir == "", "shiny-app directory not available")

  expect_true(file.exists(file.path(app_dir, "app.R")))
  expect_true(file.exists(file.path(app_dir, "global.R")))
  expect_no_error(parse(file.path(app_dir, "global.R")))
  expect_no_error(parse(file.path(app_dir, "app.R")))
})
