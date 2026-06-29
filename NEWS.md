# electrocpue (development version)

Fixes for the four major findings of the 2026-06 audit
(`docs/electrocpue-audit-2026-06.md`), with follow-up corrections from a
review of those fixes:

* **Declared R dependency now matches the code.** The package uses the
  native pipe `|>`, so `DESCRIPTION` now requires `R (>= 4.1.0)` instead
  of the inherited `R (>= 2.10)`, which would have let the package
  install on R 4.0.x and then fail to parse.
* **`validate_cpue_input()` now checks reach extent.**
  `check_reach_extent_positive()` rejects a `length_m` that is `0`,
  negative, or `NA` (and an `area_m2 <= 0` where the optional column is
  present), closing a gap that let those values pass validation and
  silently produce `Inf`/`NaN`/negative density downstream. The check is
  restricted to the reaches `catch_data` references, so a master reach
  inventory carrying placeholder extents for *unsampled* reaches is still
  accepted. Optional columns are now type-checked when present, and the
  positivity checks no longer abort the battery on a non-numeric column.
* **Non-depleting series are flagged for every method.** When the catch
  does not decline across passes -- any pass catching as many fish as the
  first, or more -- the estimate is returned with
  `note = "assumption_violated"` and a warning instead of `note = "ok"`.
  The check spans every pass (not just the first and last) and applies to
  `zippin`, `carle_strub`, and `auto` alike, so a non-depleting series is
  flagged whether or not Zippin happened to converge on it. (A series so
  extreme that the search itself does not converge is returned as
  `note = "no_convergence"`.)
* **The flag is honoured downstream.** `analyze_cpue()` now emits an
  aggregate warning when any series violates the assumption, and
  `summarize_cpue()` excludes `assumption_violated` surveys from the
  abundance and density means and intervals -- reporting them in a new
  `n_assumption_violated` column -- rather than blending their
  untrustworthy estimates into the group summary.
* **`summarize_cpue()` averages CPUE over all surveys.** Because observed
  CPUE (catch / effort) does not depend on the depletion fit, `cpue_mean`
  is averaged over every survey with a finite catch rate (an infinite
  rate from a zero-effort survey is dropped). Abundance and density means
  remain restricted to usable surveys.

Minor-finding cleanup from the same audit:

* **Amp-second effort guards its denominator.** `analyze_cpue()` now
  rejects a missing (`NA`) or non-positive `amperage` when
  `effort_basis = "amp_seconds"`, instead of silently producing an `NA`
  or meaningless catch rate.
* **Within-pass effort consistency is validated.** `validate_cpue_input()`
  now rejects a `reach_id` × `date` × `pass_number` whose species rows
  disagree on `effort_seconds` (or `amperage`) — a data-entry error
  `analyze_cpue()` would otherwise resolve silently by keeping the first
  value.
* **Documentation.** Clarified that the Carle & Strub standard errors are
  the Zippin large-sample approximation evaluated at the C&S point
  estimate; noted the very wide two-survey (df = 1) density interval;
  warned that `validate = FALSE` forgoes the contiguous-pass guard; and
  added the orphaned Zippin (1956) reference.

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
