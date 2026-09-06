# Check that pass numbers are contiguous from 1 within each reach x date

Multi-pass depletion requires a complete sequential pass series. A reach
with passes (1, 2, 4) cannot be estimated; nor can one starting at pass
2.

## Usage

``` r
check_pass_contiguity(catch_data)
```

## Arguments

- catch_data:

  See
  [`validate_cpue_input()`](https://shepherd70.github.io/electrocpue/reference/validate_cpue_input.md).

## Value

Character vector of failure messages.
