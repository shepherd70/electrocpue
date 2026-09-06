# Validate a removal count vector

Programming-error guard (distinct from the ecological edge cases
single-pass / zero-catch, which are handled by the estimators and return
`NA` rather than aborting).

## Usage

``` r
.check_counts(counts)
```
