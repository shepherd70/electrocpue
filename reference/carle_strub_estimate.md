# Carle & Strub K-pass removal estimator

Weighted-likelihood (Bayesian, uniform-prior) depletion estimator (Carle
& Strub 1978). More robust than Zippin when depletion is weak, and the
recommended default for routine use.

## Usage

``` r
carle_strub_estimate(counts, alpha = 1, beta = 1, quiet = FALSE)
```

## Arguments

- counts:

  Numeric vector of catches per pass, ordered pass 1, 2, ..., k. Must be
  finite, non-negative integers with no `NA`.

- alpha, beta:

  Prior parameters for the Carle & Strub estimator. Each must be one
  finite positive number. Both default to `1` (uniform prior), matching
  the original paper.

- quiet:

  Logical. If `TRUE`, suppress advisory warnings for non-convergent or
  single-pass series. Useful when estimating many series in a loop.
  Defaults to `FALSE`.

## Value

A one-row data frame in the format described in
[`estimate_population()`](https://shepherd70.github.io/electrocpue/reference/estimate_population.md).

## Details

The reported standard errors (`N_se`, `p_se`) are the Zippin
large-sample variance formulae evaluated at the Carle & Strub point
estimate, which is what
[`FSA::removal()`](https://fishr-core-team.github.io/FSA/reference/removal.html)
returns. Carle & Strub do not derive a separate variance, so this is the
conventional approximation rather than an exact Carle & Strub standard
error.

The abundance limits use a likelihood-ratio inversion of the same
beta-weighted likelihood that produces the Carle & Strub point estimate.
Consequently custom `alpha` and `beta` values affect both the point and
its limits; a converged point estimate is always contained by its
reported interval. These are weighted-likelihood limits, not Zippin
profile limits. The `identifiable` flag requires both the weighted
interval and the data-only profile to be bounded: a prior may regularize
the weighted interval, but it cannot turn a weak catch series into
informative depletion data. An unbounded weighted upper limit is
returned as `Inf`, never as the finite internal search cap.

Unlike Zippin, Carle & Strub does not reject a non-depleting series
outright: when the catch does not decline across passes (some later pass
catches as many fish as the first, or more) it can still converge to a
numeric estimate. That estimate is returned, but flagged with
`note = "assumption_violated"` and a warning rather than `note = "ok"`,
because the depletion assumption it rests on has failed.

## See also

Other estimation:
[`estimate_population()`](https://shepherd70.github.io/electrocpue/reference/estimate_population.md),
[`zippin_estimate()`](https://shepherd70.github.io/electrocpue/reference/zippin_estimate.md)

## Examples

``` r
carle_strub_estimate(c(45, 18, 7))
#>        method n_passes catch_total  N     N_se N_lwr N_upr         p      p_se
#> 1 carle_strub        3          70 73 2.906892    70    83 0.6306306 0.0679861
#>   converged identifiable note
#> 1      TRUE         TRUE   ok
```
