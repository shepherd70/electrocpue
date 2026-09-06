# Reshape long catch data into per-series pass-count vectors

Collapses validated long-format catch data into one row per `reach_id` x
`date` x `species`, with an ordered numeric vector of per-pass catches.
Passes a species was not recorded on (but which were conducted at that
reach x date) are filled with zero, so the depletion series correctly
reflects a true zero catch rather than a dropped pass.

## Usage

``` r
build_pass_matrix(catch_data)
```

## Arguments

- catch_data:

  A validated long-format catch data frame (see
  [`validate_cpue_input()`](https://shepherd70.github.io/electrocpue/reference/validate_cpue_input.md)).
  Must contain `reach_id`, `date`, `pass_number`, `species`, and
  `count`.

## Value

A data frame with columns `reach_id`, `date`, `species`, `n_passes`, and
a list-column `counts` holding the pass-ordered catch vector for each
series.

## See also

Other analysis:
[`analyze_cpue()`](https://shepherd70.github.io/electrocpue/reference/analyze_cpue.md),
[`summarize_cpue()`](https://shepherd70.github.io/electrocpue/reference/summarize_cpue.md)

## Examples

``` r
catch <- data.frame(
  reach_id = "R1", date = as.Date("2025-06-01"),
  pass_number = c(1L, 2L, 3L), species = "BNT",
  count = c(45L, 18L, 7L), effort_seconds = 300
)
build_pass_matrix(catch)
#> # A tibble: 1 × 5
#>   reach_id date       species n_passes counts   
#>   <chr>    <date>     <chr>      <int> <list>   
#> 1 R1       2025-06-01 BNT            3 <dbl [3]>
```
