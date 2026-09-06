# Package index

## End-to-end workflow

Validate, reshape, analyze, and summarize electrofishing surveys.

- [`validate_cpue_input()`](https://shepherd70.github.io/electrocpue/reference/validate_cpue_input.md)
  : Validate electrofishing input data
- [`build_pass_matrix()`](https://shepherd70.github.io/electrocpue/reference/build_pass_matrix.md)
  : Reshape long catch data into per-series pass-count vectors
- [`analyze_cpue()`](https://shepherd70.github.io/electrocpue/reference/analyze_cpue.md)
  : Analyze electrofishing CPUE end to end
- [`summarize_cpue()`](https://shepherd70.github.io/electrocpue/reference/summarize_cpue.md)
  : Summarize CPUE analysis output to a coarser grain

## Population estimation

Fit removal-depletion abundance estimators to a pass-count series.

- [`estimate_population()`](https://shepherd70.github.io/electrocpue/reference/estimate_population.md)
  : Estimate population size from K-pass removal data
- [`zippin_estimate()`](https://shepherd70.github.io/electrocpue/reference/zippin_estimate.md)
  : Zippin K-pass removal estimator
- [`carle_strub_estimate()`](https://shepherd70.github.io/electrocpue/reference/carle_strub_estimate.md)
  : Carle & Strub K-pass removal estimator

## Interactive application

- [`run_app()`](https://shepherd70.github.io/electrocpue/reference/run_app.md)
  : Launch the electrocpue Shiny application

## Example data

- [`example_catch`](https://shepherd70.github.io/electrocpue/reference/example_catch.md)
  : Example electrofishing catch records
- [`example_reach`](https://shepherd70.github.io/electrocpue/reference/example_reach.md)
  : Example reach metadata
