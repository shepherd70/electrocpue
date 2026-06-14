# electrocpue — Audit (2026-06)

Dimensions run: **Correctness**, **Security & provenance** (pi_audit + git), and
**Maintainability & dependencies** (core); plus the conditional dimensions that
fit an R estimator package — **Statistical validity** (depletion estimators,
variance, CI logic) and **R / package conventions** (DESCRIPTION/NAMESPACE
coherence, roxygen, tidyverse idiom, tests). Regulatory-defensibility and
financial-data dimensions were **not** run — `electrocpue` is a general-purpose
analysis tool, not a submission artifact or a money/market repo.

**Overall health: good.** This is a well-structured, thoroughly tested package
(198 tests, FSA cross-validation, error-message snapshots, documented edge-case
handling) with clean provenance and no injected content. The findings are not
about sloppiness; they are about a few places where the package's
"assumption-aware" promise and its input contract have gaps a careful reviewer
would want closed. The two that matter most: the declared R version
(`>= 2.10`) is inconsistent with the native pipe the code actually uses
(`>= 4.1`), and the validator never checks that the density denominator
`length_m` is positive — both let a problem through silently. On the statistics
side, the Carle–Strub estimator (and the `auto` fallback) will return a
`converged = TRUE, note = "ok"` estimate for catch series that *increase* across
passes, which violate the depletion model outright.

## Critical
- None.

## Major
- `DESCRIPTION` (`Depends: R (>= 2.10)`) vs. `R/cpue_analysis.R:67`,
  `R/cpue_data_validation.R`, `R/cpue_summary.R` — the code uses the native
  pipe `|>` in 27 places (R ≥ 4.1.0), but `DESCRIPTION` declares `R (>= 2.10)`
  (the usethis `LazyData` default). On R 4.0.x the dependency resolver would
  accept the package and it would then fail to parse. Fix: set
  `Depends: R (>= 4.1.0)`.
- `R/cpue_data_validation.R:102-136` (validator) → `R/cpue_analysis.R:219-220`
  (`density_per_m <- res$N / res$length_m`, `density_per_m2 <- res$N /
  res$area_m2`) — `length_m` is only *type*-checked, never checked for
  positivity or NA, and `area_m2` (optional) is not checked at all. A
  `length_m` of `0`, negative, or `NA` passes validation and silently yields
  `Inf`/`NaN`/negative density in a headline output column. Fix: add a domain
  check that `length_m > 0` (and `area_m2 > 0` where present), mirroring
  `check_effort_positive()`.
- `R/cpue_population_estimation.R:214-257` (`carle_strub_estimate`, and the
  `auto` fallback at `:109-123`) — a catch series that increases across passes
  (e.g. `c(10, 15, 20)`) grossly violates the constant-capture depletion
  assumption, yet Carle–Strub "converges" and returns `converged = TRUE,
  note = "ok"`. Called directly, `carle_strub_estimate()` issues **no** warning
  at all; only the `auto` path warns, and then only as "weak depletion." For a
  package that markets itself as "assumption-aware," there is no guard or
  distinct `note` (e.g. `"assumption_violated"`) distinguishing genuinely weak
  depletion from non-depleting/increasing data. Fix: detect a non-decreasing
  (or increasing) catch profile and flag it with a dedicated `note` and warning
  rather than reporting `"ok"`.
- `R/cpue_summary.R:103` — `cpue_mean` is computed over **converged surveys
  only** (`mean(g$cpue[conv])`). But CPUE (`catch_total / effort`) is a
  model-free observed quantity that does not depend on whether the depletion
  estimator converged. A survey whose depletion fit failed (single-pass,
  increasing catch, etc.) still has a perfectly valid observed CPUE, and it is
  silently dropped from the reach-level mean. Fix: compute `cpue_mean` over all
  surveys (CPUE is estimator-independent), or document the restriction
  explicitly if it is intentional.

## Minor
- `R/cpue_data_validation.R:50-53, 60-66` (optional columns) and
  `R/cpue_analysis.R:191` — optional columns (`amperage`, `voltage`, `area_m2`,
  …) are never type- or NA-checked. With `effort_basis = "amp_seconds"`, a
  present-but-NA `amperage` makes `amp_s = eff_s * amp` NA, propagating to an NA
  `effort_amp_seconds` and NA `cpue` with no warning. Fix: when basis is
  `amp_seconds`, check `amperage` is present, numeric, positive, and non-NA.
- `R/cpue_analysis.R:184-189` — per-pass effort/amperage are taken with
  `dplyr::first()`, assuming they are constant across the species rows of a
  pass. A data-entry discrepancy (two species rows of the same pass with
  different `effort_seconds`) is silently resolved to the first value. Fix:
  validate within-pass consistency of `effort_seconds`/`amperage`, or warn on
  disagreement.
- `R/cpue_population_estimation.R:253-254` — the Carle–Strub result reuses the
  Zippin large-sample variance helpers (`.zippin_no_var`, `.zippin_p_var`)
  evaluated at the C–S point estimate. This matches `FSA::removal()` (the
  cross-validation tests assert it to 1e-4), so it is not a numerical error, but
  the C–S function's own roxygen does not state that its SE is the Zippin-form
  approximation. Fix: note this in the `@details`/`@return` of
  `carle_strub_estimate()`.
- `R/cpue_summary.R:146-148` — for ≥ 2 surveys the t-interval uses only the
  between-survey SD and ignores the per-survey depletion SEs entirely; at the
  common n = 2 case (df = 1, t₀.₉₇₅ ≈ 12.7) the interval is extremely wide. The
  behaviour is documented, but the n = 2 instability is worth an explicit
  caveat in the `@details`. 
- `R/cpue_population_estimation.R:238-247` (and `:171-183`) — the Carle–Strub
  integer search has no cheap pre-guard against non-depleting input, so a
  degenerate series (e.g. `c(1, 1000000)`) iterates up to
  `.max_removal_iter = 1e6` before bailing; large `N0` can also drive
  `(k*N0 - X)^k` to `Inf`, where the loop guard `Inf >= Inf` stays `TRUE`.
  Bounded and tested, but wasteful. Fix: add a monotonicity/`X` pre-check (as
  Zippin has) or lower the cap.
- `R/cpue_analysis.R:154-156` + `build_pass_matrix()` — with `validate = FALSE`,
  non-contiguous pass numbering (e.g. 1, 2, 4) is not caught and
  `build_pass_matrix()` collapses it into a 3-element vector treated as passes
  1-3, producing a silently wrong depletion series. Guarded by default
  (`validate = TRUE`); note the escape-hatch risk in the `validate` param docs.
- `R/cpue_population_estimation.R:57-70` — the `@details` cite "Zippin 1956,
  1958" (and the header block cites 1956), but `@references` lists only the 1958
  paper. Orphan in-text citation. Fix: add the 1956 reference (Zippin, C. 1956,
  *Biometrics* 12:163-189) or drop the 1956 mention.
- `DESCRIPTION` (`Imports: tritonIngest`, `Remotes: github::shepherd70/…`) — a
  hard `Imports` on a GitHub-only package, with `Remotes`, is fine for
  GitHub/`pak` distribution but blocks CRAN installability. Relevant because
  `TASKS.md` still lists a `cran-comments.md` item. Note it if CRAN is a goal.
- `R/cpue_population_estimation.R` (throughout) — `T` and `X` as variable names
  trip `lintr::T_and_F_symbol_linter` (`T` shadows the `TRUE` alias). It is
  intentional, matches the removal-method notation, and is documented in the
  header Conventions block; flagged only for convention completeness.
- `R/cpue_population_estimation.R:264` — `.max_removal_iter` is defined *after*
  the two functions that reference it. Harmless (all top-level bindings exist at
  load before any call), but reads out of order; consider hoisting it above
  `zippin_estimate()`.
- `TASKS.md:90` — "`README.Rmd` is still template boilerplate — update before
  any public announcement" contradicts the completed item at `TASKS.md:57` and
  the actual file: `README.Rmd` is a real quick-start. Stale note; remove it.

## Security & provenance
- **pi_audit:** 1 MEDIUM, triaged as a **false positive** —
  `R/cpue_data_validation.R:319` ("Surfaces silently-absent columns…") matched
  the *secretly/silently* agent-text heuristic; it is ordinary roxygen prose,
  not injected instruction. No instruction-override, shell/exfil, invisible
  Unicode, HTML-comment payloads, or secrets found. `git fsck` rc=0; working
  tree clean.
- **Provenance:** clean. All commits are authored by Travis Shepherd /
  `shepherd70` (`shepherd70@gmail.com` and the standard GitHub PR-merge identity
  `134653832+shepherd70@users.noreply.github.com`); committer `GitHub
  <noreply@github.com>` appears only on merge commits, as expected. The only
  `Co-Authored-By` trailers are Claude models (Fable 5, Opus 4.8, Sonnet 4.6),
  consistent with Claude Code-assisted commits. No unfamiliar co-authors or
  suspicious author/committer email splits.

## Could not verify
- The Zippin/Carle–Strub agreement with `FSA::removal()` rests on the
  Suggests-only `FSA` package; the test suite was read but **not executed** in
  this findings pass.
- Vignette HTML render requires pandoc (absent locally per `TASKS.md`); CI is
  reported green but was not re-run here.
- Whether CRAN is actually a target — this sets the severity of the
  `Remotes`/GitHub-`Imports` note.
