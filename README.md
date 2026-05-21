<!-- README.md is generated from README.Rmd. Please edit that file -->

# electrocpue

<!-- badges: start -->
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
#>   method n_passes catch_total  N     N_se         p       p_se converged note
#> 1 zippin        3          70 74 3.236594 0.6140351 0.06958281      TRUE   ok
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
summary with confidence intervals on density.

``` r
summarize_cpue(res)[, c("reach_id", "species", "n_surveys", "N_mean",
                        "density_per_m_mean", "density_per_m_lwr",
                        "density_per_m_upr")]
#> # A tibble: 8 × 7
#>   reach_id species n_surveys N_mean density_per_m_mean density_per_m_lwr
#>   <chr>    <chr>       <int>  <dbl>              <dbl>             <dbl>
#> 1 R01      BNT             2  150                1.25             0.0853
#> 2 R01      RBT             2   64.5              0.538            0
#> 3 R02      BNT             2   88                0.926            0
#> 4 R02      RBT             2  126.               1.32             0.452
#> 5 R03      BNT             2  200                1.33             0.486
#> 6 R03      RBT             2   48.5              0.323            0.196
#> 7 R04      BNT             2   60                0.75             0
#> 8 R04      RBT             2   97                1.21             0
#> # ℹ 1 more variable: density_per_m_upr <dbl>
```

## Learn more

See `vignette("electrocpue")` for a complete worked example, including
effort standardization by amp-seconds and plotting density with
confidence intervals.
