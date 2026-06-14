# electrocpue (development version)

Fixes for the four major findings of the 2026-06 audit
(`docs/electrocpue-audit-2026-06.md`):

* **Declared R dependency now matches the code.** The package uses the
  native pipe `|>`, so `DESCRIPTION` now requires `R (>= 4.1.0)` instead
  of the inherited `R (>= 2.10)`, which would have let the package
  install on R 4.0.x and then fail to parse.
* **`validate_cpue_input()` now checks reach extent.** A new
  `check_reach_extent_positive()` rejects a `length_m` that is `0`,
  negative, or `NA` (and an `area_m2 <= 0` where the optional column is
  present), closing a gap that let those values pass validation and
  silently produce `Inf`/`NaN`/negative density downstream.
* **Carle & Strub flags non-depleting series.** When the catch does not
  decline across passes (final pass >= first), the estimator now returns
  `note = "assumption_violated"` with a warning instead of reporting
  `note = "ok"`; the `"auto"` dispatcher's fallback warning is likewise
  explicit that the depletion assumption is violated.
* **`summarize_cpue()` averages CPUE over all surveys.** Because observed
  CPUE (catch / effort) does not depend on whether the depletion
  estimator converged, `cpue_mean` is no longer restricted to converged
  surveys. Abundance and density means remain converged-only.

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
