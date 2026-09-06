# Launch the electrocpue Shiny application

Opens the bundled standalone front-end for the electrocpue workflow
(validate, estimate, analyze, summarize). Explore the bundled example
data or upload your own catch and reach tables, choose an estimator and
effort basis, and read back per-survey abundance with method-aligned
likelihood intervals plus pooled reach density, CPUE, and figures.

## Usage

``` r
run_app(...)
```

## Arguments

- ...:

  Additional arguments passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html), for
  example `port` or `launch.browser`.

## Value

Called for its side effect of starting the Shiny application; does not
return a meaningful value.

## Details

The front-end lives under `inst/shiny-app` and depends on the shiny,
bslib, DT, ggplot2, htmltools, and tibble packages, which are listed
under `Suggests`. Install any that are missing before calling this
function. Loading spinners are shown when shinycssloaders is also
installed, but it is optional.

## Examples

``` r
if (interactive()) {
  run_app()
}
```
