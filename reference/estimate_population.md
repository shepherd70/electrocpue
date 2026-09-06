# Estimate population size from K-pass removal data

Estimates abundance for a single removal series (one reach x date x
species) from successive-pass catch counts. Three methods are available:
the Zippin maximum-likelihood estimator, the Carle & Strub
weighted-likelihood estimator, and an `"auto"` mode that uses Zippin
when its model is valid and falls back to Carle & Strub otherwise.

## Usage

``` r
estimate_population(
  counts,
  method = c("auto", "zippin", "carle_strub"),
  alpha = 1,
  beta = 1,
  quiet = FALSE
)
```

## Arguments

- counts:

  Numeric vector of catches per pass, ordered pass 1, 2, ..., k. Must be
  finite, non-negative integers with no `NA`.

- method:

  One of `"auto"` (default), `"zippin"`, or `"carle_strub"`.

- alpha, beta:

  Prior parameters for the Carle & Strub estimator. Each must be one
  finite positive number. Both default to `1` (uniform prior), matching
  the original paper.

- quiet:

  Logical. If `TRUE`, suppress advisory warnings for non-convergent or
  single-pass series. Useful when estimating many series in a loop.
  Defaults to `FALSE`.

## Value

A one-row data frame with columns: `method`, `n_passes`, `catch_total`,
`N` (population estimate), `N_se`, `N_lwr`/`N_upr` (method-aligned
likelihood-ratio limits for `N`; Zippin uses the profile likelihood and
Carle & Strub uses its prior-weighted likelihood; both respect `N >= T`
and are asymmetric; `N_upr = Inf` explicitly marks an unbounded upper
limit), `p` (per-pass capture probability), `p_se`, `converged`
(logical), `identifiable` (logical; `FALSE` when either the data-only
profile likelihood or the reported method-aligned interval cannot bound
`N` from above – typically at low capture probability; an informative
prior never promotes data identifiability), and `note` (one of `"ok"`,
`"single_pass"`, `"zero_catch"`, `"model_failure"`, `"no_convergence"`,
`"assumption_violated"`).

## Details

Point estimates and variances follow the standard removal formulae
(Zippin 1956, 1958; Carle & Strub 1978) as implemented in the FSA
package, so results are directly comparable to
[`FSA::removal()`](https://fishr-core-team.github.io/FSA/reference/removal.html).

An all-zero catch series cannot identify abundance when capture
probability is unknown: at `p = 0`, every possible `N` has the same
maximized likelihood. It is therefore returned as `N = NA`,
`converged = FALSE`, and `identifiable = FALSE`. The observed catch and
CPUE remain zero downstream, but no zero population estimate or
zero-width abundance interval is asserted.

The removal model assumes catch declines across passes as the local
population is depleted, so the first pass should catch the most fish.
When some later pass catches as many as the first, or more, the
depletion assumption is violated: an estimator may still return a
numeric estimate, but it is not trustworthy. Such a series is flagged
with `note = "assumption_violated"` (and a warning) rather than `"ok"`.
The check spans every pass and applies to all methods, so `"auto"` flags
a non-depleting series whether Zippin converged on it or the Carle &
Strub fallback was used. (A non-depleting series so extreme that the
search does not converge is instead returned as
`note = "no_convergence"`, `N = NA`.)

## References

Zippin, C. (1956). An evaluation of the removal method of estimating
animal populations. Biometrics 12:163-189.

Zippin, C. (1958). The removal method of population estimation. Journal
of Wildlife Management 22:82-90.

Carle, F.L. & Strub, M.R. (1978). A new method for estimating population
size from removal data. Biometrics 34:621-630.

## See also

Other estimation:
[`carle_strub_estimate()`](https://shepherd70.github.io/electrocpue/reference/carle_strub_estimate.md),
[`zippin_estimate()`](https://shepherd70.github.io/electrocpue/reference/zippin_estimate.md)

## Examples

``` r
estimate_population(c(45, 18, 7))
#>   method n_passes catch_total  N     N_se N_lwr N_upr         p       p_se
#> 1 zippin        3          70 74 3.236594    70    83 0.6140351 0.06958281
#>   converged identifiable note
#> 1      TRUE         TRUE   ok
estimate_population(c(38, 26, 12), method = "carle_strub")
#>        method n_passes catch_total  N     N_se N_lwr N_upr         p       p_se
#> 1 carle_strub        3          76 91 9.687042    80   127 0.4444444 0.08516081
#>   converged identifiable note
#> 1      TRUE         TRUE   ok
```
