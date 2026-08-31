# electrocpue (development version)

## Documentation

* Added a Bootstrap 5 `pkgdown` configuration with a curated API reference and
  the complete worked-example vignette.
* Added contribution guidelines covering development setup, generated files,
  statistical regression tests, package checks, and website validation.

## CI maintenance

* GitHub Actions now uses `actions/checkout@v6`, moving checkout to the
  Node.js 24 runtime and removing the Node.js 20 deprecation warnings emitted
  by the v0.3.0 release workflow.

# electrocpue 0.3.0

## Migration from 0.2.0

* All-zero removal series no longer assert `N = 0`. Use `catch_total` or
  `cpue` for the observed zero, and require `converged` before consuming `N`.
* An unbounded abundance interval now has `N_upr = Inf`, rather than exposing
  the finite internal search cap. Check `identifiable` (or `is.finite(N_upr)`)
  before treating the upper limit as bounded.

## Statistical interval corrections

* An all-zero removal series is now reported as unidentifiable (`N`, `p`, and
  abundance limits are `NA`; `converged` and `identifiable` are `FALSE`). The
  observed catch and CPUE remain zero, without treating no detections as proof
  of a zero population.
* Carle-Strub abundance limits now invert the same beta-weighted likelihood as
  the point estimate. Custom `alpha` and `beta` values therefore affect both,
  and every converged point estimate is contained by its reported limits. The
  `identifiable` flag remains data-based rather than being promoted by a prior.
* Profile-likelihood abundance intervals now evaluate the legitimate
  `p = 1` boundary correctly, so a high-capture estimate such as `N = catch`
  is contained in its own interval.
* Reach density pooling now uses modified Knapp-Hartung inference, including
  the conservative `q >= 1` safeguard and a half-fish continuity width for a
  discrete singleton profile interval. This prevents identical surveys from
  erasing measurement uncertainty and prevents zero-width inputs from
  producing `NaN` limits. The former factor-20 interval-width cap was removed.
* `density_per_m_mean` and `density_per_m2_mean` now report the same
  back-transformed random-effects geometric mean targeted by their log-scale
  intervals. `N_mean` remains the descriptive arithmetic abundance mean.
* Profile-likelihood abundance intervals now use constant-memory integer
  binary searches. Results match the former exhaustive candidate grid, while
  large valid catches no longer allocate vectors and matrices proportional to
  `50 * catch_total`.
* When a profile or weighted-likelihood interval remains admissible at its
  internal search cap, the public upper limit is now `Inf` and
  `identifiable = FALSE`; the implementation cap is no longer presented as a
  statistical bound.

## Audit hardening

* Validation now rejects empty input tables, duplicate
  `reach_metadata$reach_id` keys, and non-finite effort or sampled reach
  extents. The analysis join also guards metadata uniqueness when callers
  explicitly skip validation, preventing duplicated reach rows from silently
  reweighting summaries.
* Blank and whitespace-only `species` values are now rejected on every catch
  row, even when another row in the same survey has a valid species identifier.
* Removal counts, Carle-Strub priors, summary confidence levels, capture
  thresholds, and the analysis validation flag now reject malformed or
  non-finite values with package-classed errors.
* The Shiny app's CPUE plot now labels amp-second analyses correctly. Uploaded
  CSV/TSV parsing, helper plots, and the complete example-data server reactive
  path are covered by tests.
* `htmltools` and `tibble`, which the Shiny app calls directly, are now declared
  and checked as app dependencies. The minimum R version is now 4.2 because
  the locked `tritonIngest` dependency requires it.

## Standalone Shiny front-end

* **`run_app()` launches a bundled Shiny application** — a standalone
  front-end for the full validate → estimate → analyze → summarize
  workflow. Explore the bundled example data or upload your own catch and
  reach tables, pick an estimator and effort basis, and read back
  per-survey abundance with method-aligned likelihood intervals, pooled reach
  density and CPUE, and figures with confidence intervals. The confidence
  level and `p_min` sliders recompute the summary and plots live. The app
  lives under `inst/shiny-app`; its packages (shiny, bslib, DT, ggplot2,
  htmltools, tibble) are `Suggests`, so the estimation core stays
  dependency-light.

# electrocpue 0.2.0

## Confidence intervals rebuilt (profile-likelihood + random-effects pooling)

The depletion-summary confidence intervals were rebuilt after review found
the previous method produced impossible and unstable bounds. The new method
is verified by Monte-Carlo simulation.

* **Per-survey profile-likelihood intervals.** `estimate_population()` (and
  `zippin_estimate()` / `carle_strub_estimate()`) now return `N_lwr`/`N_upr` --
  profile-likelihood limits that respect `N >= catch` and the right-skew of
  the estimate -- plus an `identifiable` flag that is `FALSE` when the data
  cannot bound abundance from above (low capture probability). They replace
  reliance on the symmetric large-sample `N_se`, whose Wald interval could
  fall below the catch.
* **Reach intervals by random-effects pooling.** `summarize_cpue()` pools the
  well-identified surveys' profile uncertainty with between-survey variation
  on the log scale (DerSimonian-Laird with the Knapp-Hartung-Sidik-Jonkman
  variance), so the interval stays positive, carries each survey's depletion
  uncertainty, and does not explode at two visits. Verified reach-mean
  coverage is about 0.92-0.96 at capture probability >= 0.45; the ad-hoc
  truncation at zero is gone.
* **Weak reaches are flagged, not faked.** New `n_identified` and `weak`
  columns mark groups whose interval rests on fewer than two well-identified
  surveys, or whose capture probability falls below the new `p_min` argument
  (default `0.4`) -- where the removal estimate is biased and no interval is
  reliable. The estimand is stated as the reach mean density.

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
