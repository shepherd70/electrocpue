# Check effort and amperage are constant within each pass

`effort_seconds` – and `amperage` where present – describe a pass, not a
species, so they are recorded identically on every species row of a
given `reach_id` x `date` x `pass_number`. When those rows disagree it
is a data-entry error:
[`analyze_cpue()`](https://shepherd70.github.io/electrocpue/reference/analyze_cpue.md)
would otherwise resolve it silently with
[`dplyr::first()`](https://dplyr.tidyverse.org/reference/nth.html),
keeping one value and discarding the rest, so it is rejected here
instead.

## Usage

``` r
check_within_pass_consistency(catch_data)
```

## Arguments

- catch_data:

  See
  [`validate_cpue_input()`](https://shepherd70.github.io/electrocpue/reference/validate_cpue_input.md).

## Value

Character vector of failure messages.
