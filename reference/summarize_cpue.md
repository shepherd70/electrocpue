# Summarize CPUE analysis output to a coarser grain

Aggregates the per-survey output of
[`analyze_cpue()`](https://shepherd70.github.io/electrocpue/reference/analyze_cpue.md)
(one row per reach x date x species) to a coarser grouping, by default
`reach_id` x `species`, collapsing repeat survey dates. Abundance and
density means and their confidence intervals are computed over the
usable surveys only – those that converged and whose depletion
assumption held; `cpue_mean`, a model-free observed quantity, is
averaged over all surveys with a finite catch rate.

## Usage

``` r
summarize_cpue(x, by = c("reach_id", "species"), level = 0.95, p_min = 0.4)
```

## Arguments

- x:

  A data frame produced by
  [`analyze_cpue()`](https://shepherd70.github.io/electrocpue/reference/analyze_cpue.md).

- by:

  Character vector of grouping columns. Defaults to
  `c("reach_id", "species")`.

- level:

  Confidence level for the density intervals. Defaults to `0.95`.

- p_min:

  Minimum estimated capture probability for a survey to enter the pooled
  density estimate and confidence interval. Surveys below it (where the
  removal estimate is biased) are held out and the reach is flagged
  `weak`. Defaults to `0.4`.

## Value

A data frame with one row per group and columns: the grouping columns;
`n_surveys`, `n_converged`, `prop_converged`, `n_assumption_violated`,
`n_identified` (surveys entering the pooled estimate and interval),
`weak` (logical; the pooled estimate rests on fewer than two
well-identified surveys, or omits a survey that fed `N_mean`);
`catch_total`; `N_mean`; pooled geometric means and lower/upper interval
limits for `density_per_m` and `density_per_m2`; and `cpue_mean`.
`N_mean` is the arithmetic mean over converged, depleting surveys. A
density mean is the back-transformed random-effects estimate over the
well-identified surveys and therefore has the same estimand and input
set as its interval. When none qualifies, the density mean falls back to
the arithmetic mean as a descriptive point value, its interval is `NA`,
and `weak` is `TRUE`.

## Details

The estimand for each density column is the random-effects mean log
density, back-transformed to the original scale – equivalently, a pooled
geometric mean. Each eligible survey contributes its method-aligned
likelihood interval (`N_lwr`/`N_upr`). For two or more surveys,
within-survey uncertainty is combined with DerSimonian-Laird
between-survey variation and a modified Knapp-Hartung Student-t
interval. The modification bounds the Knapp-Hartung variance multiplier
below by one, preventing identical survey estimates from erasing their
nonzero measurement uncertainty. No arbitrary width cap is applied to
the statistical interval.

At the default 95 percent level, a single eligible survey retains its
likelihood-based density interval exactly. At another requested level
the interval is rescaled from the supplied limits because the pass
counts needed to refit it are no longer present in `x`. A zero-width
discrete likelihood interval is expanded by half a fish on each side
before conversion to a log-scale standard error, avoiding infinite
inverse-variance weights without imposing an arbitrary relative variance
floor.

A survey enters the pooled density estimate and interval only when it
converged, did not violate the depletion assumption, was identifiable
(its abundance is bounded above), and had estimated capture probability
at least `p_min`. When fewer than two surveys qualify, or a survey
contributing to `N_mean` is held out, the group is flagged `weak`.

## References

Röver, C., Knapp, G. & Friede, T. (2015). Hartung-Knapp-Sidik-Jonkman
approach and its modification for random-effects meta-analysis with few
studies. BMC Medical Research Methodology 15:99.
[doi:10.1186/s12874-015-0091-1](https://doi.org/10.1186/s12874-015-0091-1)

## See also

Other analysis:
[`analyze_cpue()`](https://shepherd70.github.io/electrocpue/reference/analyze_cpue.md),
[`build_pass_matrix()`](https://shepherd70.github.io/electrocpue/reference/build_pass_matrix.md)

## Examples

``` r
catch <- data.frame(
  reach_id = "R1", date = as.Date("2025-06-01"),
  pass_number = c(1L, 2L, 3L), species = "BNT",
  count = c(45L, 18L, 7L), effort_seconds = 300
)
meta <- data.frame(reach_id = "R1", length_m = 100)
summarize_cpue(analyze_cpue(catch, meta))
#> # A tibble: 1 × 17
#>   reach_id species n_surveys n_converged prop_converged n_assumption_violated
#>   <chr>    <chr>       <int>       <int>          <dbl>                 <int>
#> 1 R1       BNT             1           1              1                     0
#> # ℹ 11 more variables: n_identified <int>, weak <lgl>, catch_total <dbl>,
#> #   N_mean <dbl>, density_per_m_mean <dbl>, density_per_m_lwr <dbl>,
#> #   density_per_m_upr <dbl>, density_per_m2_mean <dbl>,
#> #   density_per_m2_lwr <dbl>, density_per_m2_upr <dbl>, cpue_mean <dbl>
```
