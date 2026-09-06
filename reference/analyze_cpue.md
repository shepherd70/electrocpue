# Analyze electrofishing CPUE end to end

Validates inputs, estimates removal-depletion abundance for every
`reach_id` x `date` x `species` series, standardizes effort, and
expresses abundance as spatial density. Returns one tidy row per series,
ready for summarizing or plotting.

## Usage

``` r
analyze_cpue(
  catch_data,
  reach_metadata,
  method = c("auto", "zippin", "carle_strub"),
  effort_basis = c("seconds", "amp_seconds"),
  alpha = 1,
  beta = 1,
  validate = TRUE
)
```

## Arguments

- catch_data:

  A long-format catch data frame (see
  [`validate_cpue_input()`](https://shepherd70.github.io/electrocpue/reference/validate_cpue_input.md)).

- reach_metadata:

  A reach metadata data frame with at least `reach_id` and `length_m`;
  `area_m2` is used for areal density when present.

- method:

  Removal estimator passed to
  [`estimate_population()`](https://shepherd70.github.io/electrocpue/reference/estimate_population.md):
  `"auto"` (default), `"zippin"`, or `"carle_strub"`.

- effort_basis:

  Denominator for the effort-standardized catch rate: `"seconds"`
  (default) or `"amp_seconds"`. The latter requires an `amperage` column
  in `catch_data` whose values are all present (non-`NA`), finite, and
  positive.

- alpha, beta:

  Carle & Strub prior parameters (see
  [`estimate_population()`](https://shepherd70.github.io/electrocpue/reference/estimate_population.md)).

- validate:

  Logical. If `TRUE` (default), run
  [`validate_cpue_input()`](https://shepherd70.github.io/electrocpue/reference/validate_cpue_input.md)
  first. Set `FALSE` only when inputs are already known to be valid:
  validation also guards structural assumptions the pipeline relies on –
  notably pass numbers being contiguous from 1 – and skipping it on,
  say, non-contiguous passes (1, 2, 4) lets them collapse into a
  silently wrong depletion series.

## Value

A data frame with one row per `reach_id` x `date` x `species` and
columns: keys (`reach_id`, `date`, `species`); estimation (`method`,
`n_passes`, `catch_total`, `N`, `N_se`, `N_lwr`, `N_upr`, `p`, `p_se`,
`converged`, `identifiable`, `note`); reach extent (`length_m`,
`area_m2`); effort (`effort_seconds`, `effort_amp_seconds`,
`effort_basis`, `cpue`); and density (`density_per_m`,
`density_per_m2`). `area_m2`-dependent columns are `NA` when areal
metadata is absent.

## See also

Other analysis:
[`build_pass_matrix()`](https://shepherd70.github.io/electrocpue/reference/build_pass_matrix.md),
[`summarize_cpue()`](https://shepherd70.github.io/electrocpue/reference/summarize_cpue.md)

## Examples

``` r
catch <- data.frame(
  reach_id = "R1", date = as.Date("2025-06-01"),
  pass_number = c(1L, 2L, 3L), species = "BNT",
  count = c(45L, 18L, 7L), effort_seconds = 300
)
meta <- data.frame(reach_id = "R1", length_m = 100)
analyze_cpue(catch, meta)
#> # A tibble: 1 × 23
#>   reach_id date       species method n_passes catch_total     N  N_se N_lwr
#>   <chr>    <date>     <chr>   <chr>     <int>       <dbl> <dbl> <dbl> <dbl>
#> 1 R1       2025-06-01 BNT     zippin        3          70    74  3.24    70
#> # ℹ 14 more variables: N_upr <dbl>, p <dbl>, p_se <dbl>, converged <lgl>,
#> #   identifiable <lgl>, note <chr>, length_m <dbl>, area_m2 <dbl>,
#> #   effort_seconds <dbl>, effort_amp_seconds <dbl>, effort_basis <chr>,
#> #   cpue <dbl>, density_per_m <dbl>, density_per_m2 <dbl>
```
