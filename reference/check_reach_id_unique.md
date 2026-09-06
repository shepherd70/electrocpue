# Check that reach metadata contains one row per reach

A duplicate metadata key makes a downstream join multiply analysis rows,
silently reweighting the affected reach in summaries.

## Usage

``` r
check_reach_id_unique(reach_metadata)
```

## Arguments

- reach_metadata:

  See
  [`validate_cpue_input()`](https://shepherd70.github.io/electrocpue/reference/validate_cpue_input.md).

## Value

Character vector of failure messages.
