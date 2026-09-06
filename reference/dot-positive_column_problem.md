# Flag non-positive (and optionally NA) values in a numeric column

Shared by the positivity checks
([`check_effort_positive()`](https://shepherd70.github.io/electrocpue/reference/check_effort_positive.md)
and
[`check_reach_extent_positive()`](https://shepherd70.github.io/electrocpue/reference/check_reach_extent_positive.md)).
A non-numeric column returns no problem here: its wrong type is already
reported by the kernel type check, and comparing it would otherwise
misbehave or abort the battery mid-run (e.g. `factor <= 0` is all-`NA`,
so a downstream `if (bad_n > 0)` would error with "missing value where
TRUE/FALSE needed" before
[`validate_cpue_input()`](https://shepherd70.github.io/electrocpue/reference/validate_cpue_input.md)
could collate and abort once).

## Usage

``` r
.positive_column_problem(values, prefix, requirement, na_ok = FALSE)
```

## Arguments

- values:

  A vector; only acted on when numeric.

- prefix:

  Human-readable column reference for the message.

- requirement:

  Trailing clause stating the rule.

- na_ok:

  If `TRUE`, `NA` is permitted; if `FALSE` (default), `NA` is treated as
  a failure.

## Value

Character vector of failure messages (length 0 or 1).
