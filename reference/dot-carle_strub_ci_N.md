# Carle & Strub weighted-likelihood interval for removal abundance

Inverts the same beta-weighted removal likelihood whose adjacent-value
ratio is used by
[`carle_strub_estimate()`](https://shepherd70.github.io/electrocpue/reference/carle_strub_estimate.md)
to locate its integer point estimate. Keeping the prior parameters in
the interval calculation avoids reporting limits from a different model
that may not contain the estimate.

## Usage

``` r
.carle_strub_ci_N(
  counts,
  N_hat,
  alpha = 1,
  beta = 1,
  level = 0.95,
  cap_mult = 50
)
```

## Arguments

- counts:

  Pass-ordered catch vector (length \>= 2, `sum(counts) > 0`).

- N_hat:

  Carle & Strub integer point estimate.

- alpha, beta:

  Positive beta-prior parameters.

- level:

  Confidence/support level. Defaults to `0.95`.

- cap_mult:

  Search-cap multiplier applied to both total catch and the point
  estimate. Including the point estimate is essential for strongly
  informative custom priors that move `N_hat` well beyond total catch.

## Value

A list with `lwr`, `upr` (abundance limits; `upr = Inf` when the
weighted likelihood remains admissible at the internal search cap) and
`identifiable` (logical).

## Details

The weighted likelihood, up to terms constant in `N`, is
`N! / (N - T)! * B(T + alpha, k * N - X - T + beta)`. The
likelihood-ratio acceptance set is searched with constant-memory integer
binary searches.
