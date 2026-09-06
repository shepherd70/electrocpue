# Validate electrofishing input data

Runs the full battery of input validation checks against catch and reach
metadata tables. Every check runs regardless of earlier failures, so the
returned error lists every problem at once rather than surfacing them
one at a time.

## Usage

``` r
validate_cpue_input(catch_data, reach_metadata, strict = TRUE)
```

## Arguments

- catch_data:

  A long-format catch data frame. Required columns: `reach_id` (chr),
  `date` (Date), `pass_number` (int), `species` (chr), `count` (int),
  `effort_seconds` (num). Optional columns: `amperage` (num), `voltage`
  (num).

- reach_metadata:

  A reach metadata data frame. Required columns: `reach_id` (chr),
  `length_m` (num). Optional columns: `mean_width_m`, `area_m2`,
  `habitat_class`, `crew`, `gear`.

- strict:

  Logical. If `TRUE` (default), missing optional columns trigger
  advisory warnings; if `FALSE`, missing optionals are silent.

## Value

Invisibly returns `TRUE` if all validation checks pass. Otherwise aborts
with a classed error of class `"cpue_validation_error"` (also
`"triton_validation_error"`) whose `failures` field contains the
character vector of all detected problems.

## Details

Both tables must contain at least one row, and `reach_metadata` must
contain exactly one row per `reach_id`. Effort and sampled reach extents
used as denominators must be finite and positive; `area_m2` may be `NA`
when it is unavailable. Every catch row must have a non-missing,
non-blank species identifier.

## Examples

``` r
if (FALSE) { # \dontrun{
validate_cpue_input(catch_data, reach_metadata)
} # }
```
