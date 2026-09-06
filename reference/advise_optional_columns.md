# Warn about missing optional columns

Advisory only; never fails validation. Surfaces silently-absent columns
that change downstream behavior (e.g., missing `amperage` means
`effort_basis = "amp_seconds"` is unavailable).

## Usage

``` r
advise_optional_columns(data, optional, table_name)
```

## Arguments

- data:

  A data frame to check.

- optional:

  Named character vector of optional columns and types.

- table_name:

  Human-readable name of the table (used in warning messages).
