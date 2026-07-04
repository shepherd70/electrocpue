# electrocpue — Development Task Tracker

Package: `electrocpue` v0.2.0  
Goal: Multi-pass electrofishing CPUE analysis toolkit for R

Status legend: `[ ]` not started · `[~]` in progress · `[x]` complete

---

## Milestone 1 — Core Estimation Engine

### Input Validation
- [x] Define required/optional column contracts for catch and reach metadata tables
- [x] Implement `validate_cpue_input()` with all 9 check helpers
- [x] Add classed error (`cpue_validation_error`) and advisory warnings for optional columns
- [x] Roxygen2 documentation for all exported and internal functions
- [x] Write real `testthat` tests for `validate_cpue_input()` (42 tests, FAIL 0 WARN 0)

### Population Estimation
- [x] Implement Zippin maximum-likelihood depletion estimator (matches `FSA::removal()` exactly)
- [x] Implement Carle–Strub depletion estimator (posterior-mode search, α=β=1)
- [x] Handle zero-catch / single-pass edge cases gracefully (single-pass → NA+warn; zero catch → N=0; model failure → NA+warn)
- [x] Export a unified `estimate_population()` dispatcher (auto: Zippin → Carle–Strub fallback)
- [x] Document and test estimation functions (92 tests incl. FSA cross-validation)

### Effort Standardization
- [x] Raw effort (seconds) CPUE calculation — built into `analyze_cpue()` via `effort_basis = "seconds"`
- [x] Amp-second effort standardization — `effort_basis = "amp_seconds"` (errors clearly if amperage column absent)
- [x] Effort aggregated per pass (not double-counted across species) before standardization
- [x] Document and test (effort folded into `analyze_cpue()`; no separate `standardize_effort()` needed)

---

## Milestone 2 — Analysis Utilities

### Multi-pass Data Wrangling
- [x] Helper to reshape long catch data into per-series pass-count vectors (`build_pass_matrix()`; fills zeros for passes a species was absent from, sums duplicate species×pass rows)
- [x] End-to-end pipeline `analyze_cpue()` — validation → reshape → estimation → effort standardization → density, one tidy row per reach × date × species
- [x] Absence handling: missing pass rows treated as true zeros in the depletion series

### Summary & Reporting
- [x] `summarize_cpue()` — reach × species rollups with density CIs (Wald for single survey, t-interval for repeat surveys; lower limit truncated at 0)
- [x] Tidy output format compatible with `ggplot2` / `dplyr` pipelines (one row per group; verified with a ggplot error-bar figure in the vignette)
- [x] Bundled example data: `example_catch` (48 rows) + `example_reach` (4 reaches), generated reproducibly via `data-raw/make_example_data.R`
- [x] Vignette source: `vignettes/electrocpue.Rmd` (full validate → estimate → analyze → summarize → plot walkthrough); R code verified to run. **Note:** HTML rendering needs pandoc, which is absent in this environment — vignette builds on CRAN/pkgdown/a pandoc-equipped machine.

---

## Milestone 3 — Package Polish

### Testing & QA
- [x] Achieve ≥ 80% test coverage across all modules — **100%** (all four files). Added `test-defensive-branches.R` (23 tests) covering input-guard aborts, both-estimators-fail, CS single-pass/runaway, non-finite variance guards, and validation helper guards. The one genuinely unreachable branch (Zippin iteration cap) is marked `# nocov` with an explanatory comment.
- [x] Add snapshot tests for error message formatting — `tests/testthat/test-error-snapshots.R` (16 snapshots in `_snaps/error-snapshots.md`) pinning the fully rendered text of every user-facing abort/warning across validation, estimation, analysis, and summary. Captured under testthat's reproducible output so they're platform-stable.
- [x] Run `R CMD check` with zero warnings/notes — 0 errors / 0 warnings locally; only NOTE is the environmental "unable to verify current time" clock quirk. (Vignette build skipped locally — pandoc absent. Still to confirm on Windows + macOS CI with pandoc.)

### Documentation & README
- [x] Replace README.Rmd boilerplate with real package description and quick-start example (README.Rmd + matching static README.md with verified output)
- [ ] Add `pkgdown` site configuration (optional)
- [ ] Add `CONTRIBUTING.md` guidelines

### Release Prep
- [x] Bump version to `0.1.0` for first stable release (also fixed placeholder maintainer email; NEWS.md rewritten for 0.1.0)
- [x] Add CI: `.github/workflows/R-CMD-check.yaml` (full check incl. vignette via pandoc on macOS/Windows/Linux; README badge added)
- [x] Release PR #1 (`release/v0.1.0` → `main`) merged via merge commit `3c46b15`. **CI green on all 5 jobs** (macOS, Windows, Linux × R release/devel/oldrel) — vignette render confirmed under pandoc, closing the local gap.
- [x] ~~Complete `cran-comments.md` if targeting CRAN submission~~ — **Won't do
  (2026-07-04): CRAN is not a target.** electrocpue distributes via GitHub/`pak`.
  This also resolves the dependency caveat as won't-fix: `Imports: tritonIngest`
  is a GitHub-only package pulled via `Remotes:`, which CRAN does not permit —
  but that only matters for CRAN, so no CRAN-submission of tritonIngest,
  vendoring, or `Suggests`-with-guard rework is needed. (2026-06 audit, Minor.)
- [x] Tag `v0.1.0` — annotated tag at `2dcee27` (an ancestor of `main`) pushed to GitHub.

---

## Milestone 4 — Cross-package consolidation (complete)

### Shared validation kernel (cross-repo with `tritonmr`)
- [x] Extract the generic input-validation kernel — `check_required_columns()`, `check_column_types()`, `type_matches()`, `check_no_na()`, and the collect-then-abort pattern in `validate_cpue_input()` (`R/cpue_data_validation.R`) — into the shared layer rather than hand-rolling it here. Done: the kernel now lives in `tritonIngest` (v0.3.1, added in `tritonIngest` commit 8c49515). electrocpue's *domain* rules stay local (pass-contiguity, effort-positive, counts-nonneg-integer, reach-id consistency, species-present).
- [x] Add `tritonIngest` to `Imports` and reroute `validate_cpue_input()` to call the shared kernel; preserve the classed `cpue_validation_error` and the collect-all-then-abort UX. Done in commit `6e6c764`. **Imports pins `tritonIngest (>= 0.3.1)`** — the kernel functions exist only from 0.3.1, so an older install must fail at resolve time, not with a confusing runtime "not an exported object" error.
- [x] Coordinate with `tritonmr`: `tritonmr/R/data_validation.R::validate_capture_history()` hand-rolled the same required-cols/type/NA kernel but **aborted on the first violation** (electrocpue collects all failures first). Unify on one shared kernel + one failure-UX contract so the mark-recapture/CPUE programs validate consistently. (Source: C:\dev refactor audit, finding H1.) **Done on `tritonmr` `main`** in commit `091a97e` ("refactor(validation): delegate generic schema checks to tritonIngest kernel"): `validate_capture_history()` now delegates generic checks to the `tritonIngest` kernel and raises a collect-all classed error `c("tritonmr_validation_error", "triton_validation_error")` via `tritonIngest::validation_abort()`, mirroring electrocpue's `c("cpue_validation_error", "triton_validation_error")` — the shared `triton_validation_error` superclass is the unifying contract. The earlier `feature/unify-validation-failure-ux` PR #1 was closed **unmerged**; the change reached `main` via `091a97e`. Note: `tritonmr` now pins `tritonIngest (>= 0.4.0)` (Remotes `@v0.4.2`), ahead of electrocpue's `>= 0.3.1` pin — see version-divergence note below.

---

## Milestone 5 — Post-release hardening: audit remediation + CI rebuild (v0.2.0)

### 2026-06 audit remediation (PR #8)
- [x] Close all four **Major** findings — native-pipe R-version dependency
  (`R >= 4.1.0`), reach-extent validation (`check_reach_extent_positive()`),
  non-depleting-series flagging across every method, and honouring that flag
  downstream in `analyze_cpue()` / `summarize_cpue()`. (See NEWS 0.2.0.)
- [x] Close the **Minor** findings — amp-second denominator guard, within-pass
  effort-consistency validation, and documentation clarifications.
- [x] Security & provenance clean — `pi_audit` (1 MEDIUM triaged false-positive)
  and commit provenance. (`docs/electrocpue-audit-2026-06.md`.)

### Confidence-interval rebuild (PR #9)
- [x] Per-survey **profile-likelihood** intervals — `N_lwr`/`N_upr` respecting
  `N >= catch`, plus an `identifiable` flag — replacing the impossible/unstable
  symmetric Wald bounds. `.profile_ci_N()` in `R/cpue_population_estimation.R`.
- [x] Reach intervals via **DerSimonian–Laird + Knapp–Hartung–Sidik–Jonkman**
  random-effects pooling on the log scale — `.hksj_logci()`; new `n_identified`,
  `weak`, and `p_min` (default `0.4`) columns. Monte-Carlo reach-mean coverage
  ~0.92–0.96 at capture probability ≥ 0.45.
- [x] Squash-merged to `main` (`2eb271d`); **CI green on all 5 platforms**
  (macOS/Windows/Ubuntu × R release/devel/oldrel-1) — the earlier red CI was a
  transient GitHub Actions billing block, not the code.

### v0.2.0 release
- [x] Bump `DESCRIPTION` to `0.2.0`; promote NEWS "development version" → `0.2.0`.
- [x] Reconcile the conflicting roxygen version fields — both now `7.3.2`.
  (Machine has roxygen 8.0.0; repo pins 7.3.2 and man pages are hand-edited, not
  regenerated, to avoid whole-tree churn.)
- [x] CRAN ruled **out of scope** (2026-07-04) — GitHub/`pak` distribution only;
  see Release Prep above.
- [ ] **Deferred — refresh `renv.lock`.** Still pins `tritonIngest 0.3.1`, but
  `DESCRIPTION` requires `>= 0.4.0` (Remotes `@v0.4.2`, SHA `7cc669c`). Harmless
  today — CI installs from `DESCRIPTION`, not the lock — and the renv library is
  not materialized here, so a correct refresh needs `renv::restore()` +
  install `tritonIngest@v0.4.2` + `renv::snapshot()` rather than a hand-edit that
  could mis-transcribe the dependency's metadata. Revisit when next touching renv.
- [ ] Tag `v0.2.0` and merge the release PR (pending review + green CI).

---

## Notes

- Validation module is fully tested (42 tests, all passing clean).
- Population estimation engine complete: `R/cpue_population_estimation.R` exports `estimate_population()`, `zippin_estimate()`, `carle_strub_estimate()`. Point estimates and SEs match `FSA::removal()` to within 1e-4 across all tested cases. FSA added to Suggests as a test-time reference only (not a runtime dependency).
- Phase 2 complete: `R/cpue_analysis.R` exports `build_pass_matrix()` and `analyze_cpue()`. Output is one tidy row per reach × date × species with depletion estimates, length/areal density, and effort-standardized CPUE.
- Design decision honored: both `density_per_m` and `density_per_m2` always present (NA where area metadata absent), keeping the output rectangular.
- Phase 3 complete: `R/cpue_summary.R` exports `summarize_cpue()`. Bundled `example_catch`/`example_reach` datasets documented in `R/data.R`. Vignette source in `vignettes/electrocpue.Rmd`.
- Full suite (v0.2.0): 245 tests, FAIL 0 / WARN 0 / SKIP 3 (the 3 skips are the
  `FSA::removal()` reference cross-checks; FSA is a Suggests-only test dependency
  and is absent locally — expected, not a regression). Was 198/0/0 at 0.1.0.
- **Pandoc caveat:** not installed in this environment, so the vignette can't render to HTML here and local `R CMD check` runs with `vignettes = FALSE`. Confirm vignette rendering on a pandoc-equipped machine before release.
- Version bumped to **0.1.0**; maintainer email fixed (`shepherd70@gmail.com`); NEWS.md rewritten; README is now a real quick-start.
- **Remaining before tagging v0.1.0:** (1) measure coverage once `covr` available; (2) confirm full check incl. vignette on pandoc-equipped CI (Windows + macOS); (3) optional `cran-comments.md` / `CONTRIBUTING.md`; (4) commit + tag `v0.1.0`.
- `README.Rmd` has been rewritten as a real quick-start (description, badges, three verified worked examples) and matches the rendered `README.md`.
- **tritonIngest version alignment:** electrocpue now pins `tritonIngest (>= 0.4.0)` (Remotes `@v0.4.2`), matching `tritonmr`, so the two consumers build against one shared kernel version. (Bumped from the earlier `>= 0.3.1` pin; resolves the version-divergence decision noted during the renv/tracker pass.)
- **v0.2.0 (2026-07-04):** shipped the profile-likelihood CI rebuild (PR #9) and
  the 2026-06 audit remediation (PR #8). `DESCRIPTION` at `0.2.0`; NEWS promoted;
  roxygen fields reconciled to `7.3.2`. CRAN ruled out (GitHub/`pak` only). The
  `renv.lock` tritonIngest refresh stays deferred — see Milestone 5.
