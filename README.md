<!-- README.md is generated from README.Rmd. Please edit that file -->

# electrocpue

<!-- badges: start -->
[![R-CMD-check](https://github.com/shepherd70/electrocpue/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/shepherd70/electrocpue/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

`electrocpue` turns raw multi-pass electrofishing records into
abundance, density, and catch-per-unit-effort (CPUE) estimates. It
provides assumption-aware removal-depletion population estimators
(Zippin and Carle & Strub), effort standardization (raw seconds or
amp-seconds), and tidy, plot-ready output.

Point estimates and standard errors match `FSA::removal()`, so results
are directly comparable to that reference implementation — but FSA is
only a test-time dependency, not required at runtime.

## Installation

You can install the development version of electrocpue from
[GitHub](https://github.com/shepherd70/electrocpue) with:

``` r
# install.packages("pak")
pak::pak("shepherd70/electrocpue")
```

## Workflow

The package follows a four-step workflow: **validate → estimate →
analyze → summarize**.

``` r
library(electrocpue)
```

### Estimate a single removal series

`estimate_population()` works on a vector of per-pass catches. The
default `"auto"` method uses the Zippin maximum-likelihood estimator and
falls back to Carle & Strub when the Zippin model fails.

``` r
estimate_population(c(45, 18, 7))
#>   method n_passes catch_total  N     N_se N_lwr N_upr         p       p_se
#> 1 zippin        3          70 74 3.236594    70    83 0.6140351 0.06958281
#>   converged identifiable note
#> 1      TRUE         TRUE   ok
```

### Analyze a whole dataset

`analyze_cpue()` validates the inputs, estimates abundance for every
reach × date × species series, standardizes effort, and converts
abundance to density. It returns one tidy row per series.

``` r
res <- analyze_cpue(example_catch, example_reach)
head(res[, c("reach_id", "date", "species", "N", "N_se", "density_per_m", "cpue")])
#> # A tibble: 6 × 7
#>   reach_id date       species     N  N_se density_per_m   cpue
#>   <chr>    <date>     <chr>   <dbl> <dbl>         <dbl>  <dbl>
#> 1 R01      2025-06-15 BNT       161  8.47         1.34  0.0982
#> 2 R01      2025-06-15 RBT        58  1.97         0.483 0.0385
#> 3 R01      2025-08-20 BNT       139  2.91         1.16  0.0930
#> 4 R01      2025-08-20 RBT        71  2.68         0.592 0.0468
#> 5 R02      2025-06-15 BNT        95  8.61         1     0.0696
#> 6 R02      2025-06-15 RBT       119  9.29         1.25  0.0877
```

### Summarize repeat surveys

`summarize_cpue()` rolls repeat survey dates up to a reach × species
summary. Density is reported as a random-effects pooled geometric mean
with a modified Knapp-Hartung confidence interval.

``` r
summarize_cpue(res)[, c("reach_id", "species", "n_surveys", "N_mean",
                        "density_per_m_mean", "density_per_m_lwr",
                        "density_per_m_upr")]
#> # A tibble: 8 × 7
#>   reach_id species n_surveys N_mean density_per_m_mean density_per_m_lwr
#>   <chr>    <chr>       <int>  <dbl>              <dbl>             <dbl>
#> 1 R01      BNT             2  150                1.23             0.491
#> 2 R01      RBT             2   64.5              0.533            0.148
#> 3 R02      BNT             2   88                0.919            0.271
#> 4 R02      RBT             2  126.               1.31             0.460
#> 5 R03      BNT             2  200                1.36             0.692
#> 6 R03      RBT             2   48.5              0.320            0.221
#> 7 R04      BNT             2   60                0.748            0.259
#> 8 R04      RBT             2   97                1.16             0.0826
#> # ℹ 1 more variable: density_per_m_upr <dbl>
```

## Learn more

See `vignette("electrocpue")` for a complete worked example, including
effort standardization by amp-seconds and plotting density with
confidence intervals.
