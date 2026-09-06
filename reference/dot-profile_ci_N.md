# Profile-likelihood confidence interval for removal abundance

Inverts the constant-capture-probability removal likelihood to bracket
the abundance `N`. Unlike the symmetric large-sample Wald interval from
`N_se`, the profile limits respect the hard lower boundary `N >= T` (the
total catch – a reach cannot hold fewer fish than were removed from it)
and the right-skew of the estimate, and they widen honestly when
depletion is weak.

## Usage

``` r
.profile_ci_N(counts, level = 0.95, cap_mult = 50)
```

## Arguments

- counts:

  Pass-ordered catch vector (length \>= 2, `sum(counts) > 0`).

- level:

  Confidence level. Defaults to `0.95`.

- cap_mult:

  Upper search bound as a multiple of the total catch.

## Value

A list with `lwr`, `upr` (abundance limits; `upr = Inf` when the profile
remains admissible at the internal search cap) and `identifiable`
(logical).

## Details

The search runs `N` up to `cap_mult * T`, using integer binary searches
over the unimodal profile likelihood rather than allocating every
candidate abundance. Its memory use is therefore constant even for very
large catches. If the likelihood is still admissible at that cap the
upper limit is unbounded – the data cannot bound abundance from above,
which happens at low capture probability – and `upr = Inf`,
`identifiable = FALSE` are returned so downstream summaries can flag the
series without exposing the finite search cap as a statistical limit.
