# Reach density interval by random-effects pooling on the log scale

Pools the well-identified surveys in a group into a reach-level density
interval. It works on the log scale, so the interval stays positive and
matches the right-skew of removal estimates, and it combines each
survey's likelihood-based uncertainty (`v_i`, from its `N_lwr`/`N_upr`)
with the between-survey (temporal) variation by DerSimonian-Laird random
effects. The modified Knapp-Hartung variance uses a Student-t critical
value and bounds its variance multiplier below by one, so identical
point estimates retain their within-survey uncertainty. No arbitrary cap
is applied to the interval width.

## Usage

``` r
.hksj_logci(d, dl, du, level = 0.95, resolution = NULL, profile_level = 0.95)
```

## Arguments

- d:

  Per-survey density point estimates (well-identified surveys).

- dl, du:

  Per-survey likelihood-based density limits, aligned with `d`.

- level:

  Confidence level.

- resolution:

  Smallest density increment for each survey (one fish divided by reach
  length or area). Used only to give a zero-width discrete likelihood
  interval a half-unit continuity width. When `NULL`, a numerical
  fallback is used.

- profile_level:

  Confidence/support level of the supplied per-survey likelihood limits.
  The legacy argument name is retained for compatibility;
  [`analyze_cpue()`](https://shepherd70.github.io/electrocpue/reference/analyze_cpue.md)
  currently supplies 95 percent limits.

## Value

Named numeric vector `c(mean, lwr, upr, n)`; all `NA` (with `n = 0`)
when no survey is usable.

## References

Röver, C., Knapp, G. & Friede, T. (2015). Hartung-Knapp-Sidik-Jonkman
approach and its modification for random-effects meta-analysis with few
studies. BMC Medical Research Methodology 15:99.
[doi:10.1186/s12874-015-0091-1](https://doi.org/10.1186/s12874-015-0091-1)
