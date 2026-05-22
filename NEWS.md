# electrocpue 0.1.0

First feature-complete release. The package now supports the full
workflow from raw multi-pass electrofishing records to reach-level
density and CPUE summaries.

## Data validation

* `validate_cpue_input()` runs a full battery of structural and content
  checks on catch and reach-metadata tables, reporting every problem at
  once via a classed `cpue_validation_error`.

## Population estimation

* `estimate_population()` dispatches between the Zippin and Carle & Strub
  removal-depletion estimators, with an `"auto"` mode that prefers Zippin
  and falls back to Carle & Strub on model failure.
* `zippin_estimate()` and `carle_strub_estimate()` expose the individual
  estimators. Point estimates and standard errors match
  `FSA::removal()`; FSA is a test-time dependency only.
* Edge cases follow clear conventions: single-pass series return `NA`
  with a warning, zero total catch returns `N = 0`, and non-convergent
  series return `NA` with a warning.

## Analysis pipeline

* `analyze_cpue()` wires validation, reshaping, estimation, effort
  standardization, and density calculation into a single call, returning
  one tidy row per reach × date × species.
* `build_pass_matrix()` reshapes long catch data into per-series
  pass-count vectors, filling absent passes with zero and summing
  duplicate species × pass rows.
* Effort can be standardized by raw seconds or amp-seconds, and is
  aggregated per pass to avoid double counting across species.

## Summaries

* `summarize_cpue()` rolls repeat surveys up to reach × species with
  confidence intervals on density (Wald for a single survey, t-interval
  for repeat surveys).

## Data and documentation

* Added bundled example datasets `example_catch` and `example_reach`.
* Added the `vignette("electrocpue")` end-to-end walkthrough.
