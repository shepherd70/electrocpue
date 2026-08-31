# Contributing to electrocpue

Thanks for helping improve electrocpue. Bug reports, documentation fixes,
tests, and focused code changes are all welcome.

## Before opening a pull request

- Search the [issue tracker](https://github.com/shepherd70/electrocpue/issues)
  for related work. Open an issue first when a change would alter the public
  API, input contract, or statistical behavior.
- Keep pull requests focused on one problem. Include the reason for the change,
  any user-visible consequences, and the checks you ran.
- Do not include confidential field data in issues, fixtures, snapshots, or
  examples. Reduce reproductions to synthetic or anonymized data.

## Development setup

electrocpue requires R 4.2 or newer and uses `renv` to record its development
dependencies. From the repository root, restore the project library with:

```sh
Rscript --vanilla -e 'if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")'
Rscript --vanilla -e 'renv::restore()'
```

The first command is only needed when `renv` is not already installed. The
GitHub-only `tritonIngest` dependency is pinned in both `DESCRIPTION` and
`renv.lock`, so keep those declarations aligned when changing its version.

Pandoc is needed to build the vignette and README. A LaTeX installation is
needed only to reproduce the PDF-reference-manual CI job.

## Making changes

- Follow the style of the surrounding R code and use roxygen comments for
  function documentation.
- Add or update `testthat` coverage for every behavior change. Statistical
  changes should include representative estimates, boundary cases, and failure
  or non-identifiability cases where applicable.
- Update `NEWS.md` for user-visible changes and `TASKS.md` when completing a
  tracked item.
- Edit `README.Rmd`, not the generated `README.md`. Edit roxygen comments, not
  generated files in `man/` or `NAMESPACE`.
- Keep optional Shiny and plotting dependencies guarded with
  `requireNamespace()` unless they become runtime requirements.

Regenerate affected documentation with:

```sh
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'rmarkdown::render("README.Rmd", output_format = "github_document")'
```

Run only the command relevant to the files you changed. Review generated diffs
before committing them.

## Checks

At minimum, run the test suite:

```sh
Rscript -e 'testthat::test_local()'
```

Before requesting review, also build and check the source package:

```sh
R CMD build .
R CMD check --no-manual electrocpue_*.tar.gz
```

For website changes, install `pkgdown` if needed and validate the site metadata:

```sh
Rscript -e 'pkgdown::check_pkgdown()'
Rscript -e 'pkgdown::build_site()'
```

Pull requests run package checks on macOS, Windows, and multiple Linux/R
versions, plus a Linux PDF-manual build. Please investigate every failure,
including failures that occur only on one platform.
