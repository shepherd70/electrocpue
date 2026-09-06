# Flag a converged estimate whose catch series does not deplete

The removal model assumes catch declines across passes as the local
population is removed, so the first pass should catch the most fish.
When any later pass catches as many as the first, or more, that
assumption has failed: the estimate is numerically valid but not
trustworthy, so it is returned with `note = "assumption_violated"` (and
an advisory warning) rather than `"ok"`. The test spans every pass, not
just the endpoints, so an interior pass that spikes above the first pass
is caught too.

## Usage

``` r
.flag_non_depletion(est, counts, quiet, estimator)
```

## Arguments

- est:

  A converged one-row estimate from
  [`.build_estimate()`](https://shepherd70.github.io/electrocpue/reference/dot-build_estimate.md).

- counts:

  The pass-ordered catch vector (length \>= 2 here).

- quiet:

  Suppress the advisory warning.

- estimator:

  Human-readable estimator name for the warning.

## Value

`est`, with `note` set to `"assumption_violated"` when the series does
not deplete; otherwise unchanged.

## Details

Applied identically by
[`zippin_estimate()`](https://shepherd70.github.io/electrocpue/reference/zippin_estimate.md)
and
[`carle_strub_estimate()`](https://shepherd70.github.io/electrocpue/reference/carle_strub_estimate.md)
on their converged paths, so the flag does not depend on which estimator
produced the number – in particular `method = "auto"` flags a
non-depleting series whether Zippin converged on it or the Carle & Strub
fallback was used.
