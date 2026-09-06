# Check that every catch record identifies a species

Every row contributes a count to a species-specific removal series, so
an empty identifier cannot be rescued by another valid species elsewhere
in the same reach x date. Empty and whitespace-only strings fail. `NA`
values are reported by the shared required-column NA check.

## Usage

``` r
check_species_present(catch_data)
```

## Arguments

- catch_data:

  See
  [`validate_cpue_input()`](https://shepherd70.github.io/electrocpue/reference/validate_cpue_input.md).

## Value

Character vector of failure messages.
