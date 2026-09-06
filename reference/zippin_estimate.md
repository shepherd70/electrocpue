# Zippin K-pass removal estimator

Maximum-likelihood depletion estimator assuming constant per-pass
capture probability (Zippin 1956, 1958).

## Usage

``` r
zippin_estimate(counts, quiet = FALSE)
```

## Arguments

- counts:

  Numeric vector of catches per pass, ordered pass 1, 2, ..., k. Must be
  finite, non-negative integers with no `NA`.

- quiet:

  Logical. If `TRUE`, suppress advisory warnings for non-convergent or
  single-pass series. Useful when estimating many series in a loop.
  Defaults to `FALSE`.

## Value

A one-row data frame in the format described in
[`estimate_population()`](https://shepherd70.github.io/electrocpue/reference/estimate_population.md).

## See also

Other estimation:
[`carle_strub_estimate()`](https://shepherd70.github.io/electrocpue/reference/carle_strub_estimate.md),
[`estimate_population()`](https://shepherd70.github.io/electrocpue/reference/estimate_population.md)

## Examples

``` r
zippin_estimate(c(45, 18, 7))
#>   method n_passes catch_total  N     N_se N_lwr N_upr         p       p_se
#> 1 zippin        3          70 74 3.236594    70    83 0.6140351 0.06958281
#>   converged identifiable note
#> 1      TRUE         TRUE   ok
```
