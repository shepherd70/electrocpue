# Check that reach extent columns are strictly positive

`length_m` is the denominator of linear density and must be a positive,
non-missing value for every reach; a `0`, negative, or `NA` length
otherwise passes type-checking and silently yields an
`Inf`/`NaN`/negative density downstream. `area_m2` is optional, so an
absent or `NA` value is allowed (it simply yields an `NA` areal
density), but where a value is present it must likewise be positive.

## Usage

``` r
check_reach_extent_positive(reach_metadata, used_reach_ids = NULL)
```

## Arguments

- reach_metadata:

  See
  [`validate_cpue_input()`](https://shepherd70.github.io/electrocpue/reference/validate_cpue_input.md).

- used_reach_ids:

  Optional vector of `reach_id`s referenced by `catch_data`. When
  supplied, only those reaches are checked; when `NULL` (the default),
  every row is checked.

## Value

Character vector of failure messages.

## Details

Only the reaches `catch_data` actually references are checked: a master
reach inventory may legitimately carry placeholder extents for reaches
not sampled this season, and those rows are dropped by the downstream
join in
[`analyze_cpue()`](https://shepherd70.github.io/electrocpue/reference/analyze_cpue.md)
before any density is computed.
