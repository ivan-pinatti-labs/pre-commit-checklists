# Contributing

Your input and ideas are welcome. The goal is to make contributing to this
project as easy and transparent as possible, whether that means:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing a new feature
- Becoming a maintainer

## The short version

| Stage | What runs | What you do |
| --- | --- | --- |
| Open as a **draft** | CI or pre-commit hooks, if this repo has any | Fix what they report |
| **Mark ready for review** | Review, once checks are green | Address the feedback |
| Merge | | |

<!-- Replace the "What runs" column once this repository's actual
  checks exist, and whether review waits for a draft to be marked
  ready. Delete the table if that distinction does not apply here. -->

## GitHub Flow

This project uses [GitHub Flow](https://guides.github.com/introduction/flow/index.html),
so all code changes happen through pull requests.

1. Fork the repo and create your branch from the default branch
  (usually `main`).
2. If this repository uses [`pre-commit`](https://pre-commit.com/#install)
  (check for a `.pre-commit-config.yaml` at the root), install it and run
  `pre-commit install` in your clone. `git clone` does not carry hooks over,
  so do this in every clone, including throwaway ones.
3. Make your change, and add or update tests if the project has a test suite.
4. Run whatever checks this repository documents (pre-commit hooks, a test
  suite, CI) before opening the pull request, so obvious problems are caught
  before a reviewer sees them.
5. Open the pull request as a **draft** if those checks take a while to run;
  mark it ready once it is green.
6. Use [Conventional Commits](https://www.conventionalcommits.org/) for
  commit messages and the pull request title, unless this repository
  documents a different convention.
7. Update the documentation if your change affects it.
8. Issue the pull request.

## Any contributions you make will be under this project's license

In short, when you submit code changes, your submissions are understood to
be under the same license that covers this project. See the `LICENSE` file
at the root of this repository; contact a maintainer first if that is a
concern.

## Report bugs using GitHub's issues

Bugs are tracked as GitHub issues. Report one by opening a new issue; the
bug report template will prompt for the details that help the most.

## Write bug reports with detail and background

A good bug report explains what you expected to happen, what actually
happened instead, and the smallest set of steps that reproduces it.

## Use a Consistent Coding Style

Match whatever `.editorconfig`, linter, or formatter configuration already
lives in this repository. If none exists yet, ask a maintainer before
introducing one, rather than mixing styles across a single pull request.

## Scripts

If this repository ships helper scripts (commonly under `scripts/`), match
whatever is already there: a consistent naming scheme, a shebang line
appropriate to the language, and, for shell scripts, a strict-mode preamble
such as `set -euo pipefail`. Document what a script does and, if it can fail
in more than one way, what each exit status means. Never commit secrets or
another environment's live state; commit a sanitized example file instead.

## License

By contributing, you agree that your contributions will be licensed under
this project's license.

## References

This document was adapted from the GitHub Gist
<https://gist.github.com/briandk/3d2e8b3ec8daf5a27a62>.
