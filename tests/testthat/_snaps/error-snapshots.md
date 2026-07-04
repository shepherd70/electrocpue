# validate_cpue_input aborts with all failures listed at once

    Code
      validate_cpue_input(catch, snap_meta(), strict = FALSE)
    Condition
      Error:
      ! Input validation failed with 3 issue(s):
        x catch_data is missing required column(s): reach_id
        x catch_data$effort_seconds has 1 non-positive or NA value(s); all records must have effort > 0
        x catch_data$count contains 5 negative value(s)

# validate_cpue_input reports non-contiguous passes with location

    Code
      validate_cpue_input(catch, snap_meta(), strict = FALSE)
    Condition
      Error:
      ! Input validation failed with 1 issue(s):
        x Pass numbers are not contiguous from 1 at reach_id='R2', date=2025-06-01: found 1, 3

# validate_cpue_input truncates the orphan reach_id preview

    Code
      validate_cpue_input(rbind(catch, extra), snap_meta(), strict = FALSE)
    Condition
      Error:
      ! Input validation failed with 1 issue(s):
        x catch_data references reach_id(s) not in reach_metadata: ORPHAN_1, ORPHAN_2, ORPHAN_3, ORPHAN_4, ORPHAN_5 (and 2 more)

# validate_cpue_input advises about missing optional columns

    Code
      invisible(validate_cpue_input(snap_catch(), snap_meta(), strict = TRUE))
    Condition
      Warning:
      Optional column(s) missing from catch_data:
      i amperage, voltage
      i Some downstream features will be unavailable.
      Warning:
      Optional column(s) missing from reach_metadata:
      i mean_width_m, area_m2, habitat_class, crew, gear
      i Some downstream features will be unavailable.

# validate_cpue_input reports a non-positive reach length

    Code
      validate_cpue_input(snap_catch(), meta, strict = FALSE)
    Condition
      Error:
      ! Input validation failed with 1 issue(s):
        x reach_metadata$length_m has 1 non-positive or NA value(s); every reach must have length_m > 0

# validate_cpue_input reports within-pass effort disagreement

    Code
      validate_cpue_input(rbind(catch, extra), snap_meta(), strict = FALSE)
    Condition
      Error:
      ! Input validation failed with 1 issue(s):
        x catch_data$effort_seconds varies within 1 reach x date x pass group(s); it must be constant across the species rows of a pass

# single-pass series warns and returns NA

    Code
      invisible(estimate_population(c(5L)))
    Condition
      Warning:
      Single-pass series: depletion estimation is not possible; returning NA.

# auto falls back to Carle & Strub when Zippin fails

    Code
      invisible(estimate_population(c(2L, 5L, 9L)))
    Condition
      Warning:
      Zippin model failed; used Carle & Strub estimate instead.
      ! Catch does not decline across passes; the depletion assumption is violated.
      i Interpret the estimate with great caution (see the note column).

# zippin_estimate warns on insufficient depletion

    Code
      invisible(zippin_estimate(c(2L, 5L, 9L)))
    Condition
      Warning:
      Zippin model failure: catch series shows insufficient depletion; returning NA.

# carle_strub_estimate flags a non-depleting catch series

    Code
      invisible(carle_strub_estimate(c(2L, 5L, 9L)))
    Condition
      Warning:
      Carle & Strub: catch does not decline across passes (a later pass catches as many as the first, or more).
      ! The removal-depletion assumption is violated; the estimate is unreliable.
      i Inspect the catch series before using N (see the note column).

# carle_strub_estimate rejects non-positive priors

    Code
      carle_strub_estimate(c(5L, 3L), alpha = 0)
    Condition
      Error in `carle_strub_estimate()`:
      ! `alpha` and `beta` must be positive.

# estimate_population rejects non-integer counts

    Code
      estimate_population(c(4.5, 2))
    Condition
      Error in `.check_counts()`:
      ! `counts` must be whole numbers.

# estimate_population rejects negative counts

    Code
      estimate_population(c(-1L, 2L))
    Condition
      Error in `.check_counts()`:
      ! `counts` must be non-negative.

# build_pass_matrix reports missing reshape columns

    Code
      build_pass_matrix(catch)
    Condition
      Error in `build_pass_matrix()`:
      ! catch_data is missing column(s) required for reshaping: species.

# analyze_cpue rejects amp_seconds basis without amperage

    Code
      analyze_cpue(snap_catch(), snap_meta(), effort_basis = "amp_seconds")
    Condition
      Error in `analyze_cpue()`:
      ! `effort_basis = "amp_seconds"` requires an amperage column in `catch_data`.
      i Use `effort_basis = "seconds"` or add an amperage column.

# analyze_cpue rejects amp_seconds basis with an invalid amperage

    Code
      analyze_cpue(catch, snap_meta(), effort_basis = "amp_seconds", validate = FALSE)
    Condition
      Error in `analyze_cpue()`:
      ! amperage must be numeric, non-"NA", and positive for `effort_basis = "amp_seconds"`.
      i A missing or non-positive amperage gives an undefined amp-second effort.

# analyze_cpue warns when some series do not converge

    Code
      invisible(analyze_cpue(catch, snap_meta(), validate = FALSE))
    Condition
      Warning:
      1 of 2 series did not yield a usable estimate.
      i Inspect the converged and note columns.

# summarize_cpue rejects a non-data-frame input

    Code
      summarize_cpue(list(1, 2, 3))
    Condition
      Error in `summarize_cpue()`:
      ! `x` must be a data frame from `analyze_cpue()`.

# summarize_cpue reports missing analyze_cpue columns

    Code
      summarize_cpue(data.frame(reach_id = "R1"))
    Condition
      Error in `summarize_cpue()`:
      ! `x` is missing column(s): species, converged, identifiable, note, catch_total, N, N_lwr, N_upr, p, length_m, area_m2, cpue, density_per_m, and density_per_m2.
      i Did it come from `analyze_cpue()`?

# summarize_cpue rejects an out-of-range confidence level

    Code
      summarize_cpue(res, level = 1.5)
    Condition
      Error in `summarize_cpue()`:
      ! `level` must be a single number in (0, 1).

