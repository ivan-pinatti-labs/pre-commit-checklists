# Contributing

Your inputs and ideas are welcome. The goal is to make contributing to this
project as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of a checklist or a hook selector
- Submitting a fix
- Proposing a new checklist or hook id
- Becoming a maintainer

## GitHub Flow

This project uses [GitHub Flow](https://guides.github.com/introduction/flow/index.html),
so all code changes happen through pull requests.

1. Fork the repo and create your branch from `main`.
2. Install [`pre-commit`](https://pre-commit.com/#install) if you don't have
   it yet, then run `make install` (or `pre-commit install`) in your clone.
   `git clone` does not carry hooks over, so do this in every clone,
   including throwaway ones.
3. Make your change. `make run` (or `pre-commit run --all-files`) runs the
   same checklists this repo dogfoods on itself; see the repo's own
   [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) for exactly which
   ones and at which git stage.
4. If you're adding or changing a checklist, also check it against
   [`docs/hook-catalogue.md`](hook-catalogue.md): every hook id in
   [`.pre-commit-hooks.yaml`](../.pre-commit-hooks.yaml) needs a row there,
   and the row needs to state what the hook actually matches, not just what
   you intended it to match. `types:`/`types_or:` and `files:` are ANDed by
   pre-commit, not ORed; see that doc's "Why the selector matters" section
   before writing either.
5. Open the pull request as a **draft**. Mark it ready once it's green.
6. Adhere to [Conventional Commits](https://www.conventionalcommits.org/) for
   your commit messages and PR title; this repository is versioned with
   [Semantic Versioning](https://semver.org/). No ticket prefix: that's an
   opt-in override for consumers of this library, not a convention of this
   repository's own history.
7. Update the documentation accordingly, including
   [`docs/hook-catalogue.md`](hook-catalogue.md) and the README catalogue
   table if you touched a hook id.
8. Issue the pull request.

## Any contributions you make will be under the Apache License 2.0

In short, when you submit code changes, your submissions are understood to be
under the same [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
that covers the project. Feel free to contact the maintainer if that's a
concern.

## Report bugs using GitHub's issues

Bugs are tracked as
[GitHub issues](https://github.com/ivan-pinatti/pre-commit-checklists/issues);
report one by
[opening a new issue](https://github.com/ivan-pinatti/pre-commit-checklists/issues/new).

## Write bug reports with detail and background

A good bug report names the hook id, the `rev:` you have pinned, the file
that triggered (or should have triggered) it, and what you expected instead.

## Use a Consistent Coding Style

- 2 spaces for indentation, not tabs, matching [`.editorconfig`](../templates/.editorconfig).
- Shell scripts under `scripts/` use `#!/usr/bin/env bash` with the explicit
  `set -o errexit`, `set -o pipefail`, `set -o nounset` trio, and document
  every exit status code in a leading comment. `shellcheck`
  (`--severity=error`) and `shfmt` (`--indent 2`) run over them through
  `checklist-dev-shell` in this repo's own dogfood config.
- Run `make run` before pushing; it runs both the `pre-commit` and
  `pre-push` stage hooks this repo dogfoods on itself, over every file.

## License

By contributing, you agree that your contributions will be licensed under
the Apache License 2.0.

## References

This document was adapted from the GitHub Gist
<https://gist.github.com/briandk/3d2e8b3ec8daf5a27a62>.

---

See also: [README.md](../README.md), [docs/getting-started.md](getting-started.md),
[docs/hook-catalogue.md](hook-catalogue.md)
