# Contributing

Your inputs and ideas are welcome. The goal is to make contributing to this
project as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of a checklist or a hook selector
- Submitting a fix
- Proposing a new checklist or hook id
- Becoming a maintainer

## The short version

| Stage | What runs | What you do |
| --- | --- | --- |
| Open as a **draft** | `Pre-commit` and `Tests` run on the same push, plus a `Labeler` pass and a `Post Pre-Commit Log` comment (see [`.github/workflows/pull-request.yml`](../.github/workflows/pull-request.yml)), and `SonarQube` runs SonarQube Cloud's quality gate (see [`.github/workflows/sonarqube.yml`](../.github/workflows/sonarqube.yml)); a fork's pull request cannot receive its token, so a maintainer pushes the branch here | Fix whatever `Pre-commit`, `Tests` or `SonarQube` report |
| **Mark ready for review** | CodeRabbit reviews (it skips drafts; see [`.coderabbit.yaml`](../.coderabbit.yaml)) | Address its comments, pushing fixes |
| Merge | `Pin Only` and `Review Verified` also have to be green (see [`docs/MERGE_PIPELINE.md`](MERGE_PIPELINE.md)) | Human pull requests wait for a maintainer; eligible bot and owner pull requests may merge automatically once every check is green and approval is present |

Opening as a draft first means the cheap, mechanical checks run before
CodeRabbit spends a review on a diff that pre-commit might still flag.
That job doesn't auto-fix or push anything back to your branch; a hook
that finds something wrong, even something it could fix locally, fails
the job, and you commit and push the fix yourself.

## GitHub Flow

This project uses [GitHub Flow](https://guides.github.com/introduction/flow/index.html),
so all code changes happen through pull requests.

1. Fork the repo and create your branch from `main`.
2. Install [`pre-commit`](https://pre-commit.com/#install) if you don't have
   it yet, then run `make install` (or `pre-commit install`) in your clone.
   `git clone` does not carry hooks over, so do this in every clone,
   including throwaway ones.
3. Make your change. `make run` runs the same checklists this repo
   dogfoods on itself, at both the pre-commit and pre-push stages. By hand
   that is `pre-commit run --all-files`, then the same with
   `--hook-stage pre-push`; in a devcontainer-airlock workbench, use
   `l2-pre-commit` in place of `pre-commit`. See the repo's own
   [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) for exactly which
   ones run at which git stage.
4. If you're adding or changing a checklist, also check it against
   [`docs/hook-catalogue.md`](hook-catalogue.md): every hook id in
   [`.pre-commit-hooks.yaml`](../.pre-commit-hooks.yaml) needs a row there,
   and the row needs to state what the hook actually matches, not just what
   you intended it to match. `types:`/`types_or:` and `files:` are ANDed by
   pre-commit, not ORed; see that doc's "Why the selector matters" section
   before writing either.
5. Run `make test` (or `tests/run_tests.sh`) if your change touches a
   checklist, a script, or a template; see [`tests/README.md`](../tests/README.md)
   for what each phase needs installed and how to run just one of them.
6. Open the pull request as a **draft**. Mark it ready once it's green.
7. Adhere to [Conventional Commits](https://www.conventionalcommits.org/) for
   your commit messages and PR title; this repository is versioned with
   [Semantic Versioning](https://semver.org/). No ticket prefix: that's an
   opt-in override for consumers of this library, not a convention of this
   repository's own history.
8. Update the documentation accordingly, including
   [`docs/hook-catalogue.md`](hook-catalogue.md) and the README catalogue
   table if you touched a hook id.
9. Issue the pull request.

## Any contributions you make will be under the Apache License 2.0

In short, when you submit code changes, your submissions are understood to be
under the same [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
that covers the project. Feel free to contact the maintainer if that's a
concern.

## Report bugs using GitHub's issues

Bugs are tracked as
[GitHub issues](https://github.com/ivan-pinatti-labs/pre-commit-checklists/issues);
report one by
[opening a new issue](https://github.com/ivan-pinatti-labs/pre-commit-checklists/issues/new).

## Write bug reports with detail and background

A good bug report names the hook id, the `rev:` you have pinned, the file
that triggered (or should have triggered) it, and what you expected instead.

## Use a Consistent Coding Style

- 2 spaces for indentation, not tabs, matching [`.editorconfig`](../templates/.editorconfig).
- Shell scripts under `scripts/` use `#!/usr/bin/env bash` with the explicit
  `set -o errexit`, `set -o pipefail`, `set -o nounset` trio, and document
  every exit status code in a leading `#` comment block. `shellcheck`
  (`--severity=error`) and `shfmt` (`--indent 2`) run over them through
  `checklist-dev-shell` in this repo's own dogfood config.
- Run `make run` before pushing; it runs both the `pre-commit` and
  `pre-push` stage hooks this repo dogfoods on itself, over every file.

## Scripts

Helper scripts live flat in [`scripts/`](../scripts/), no subfolders, and
each is either wired up as a hook's `entry:` in
[`.pre-commit-hooks.yaml`](../.pre-commit-hooks.yaml) or run directly by a
contributor or consumer (`install.sh`). Follow the coding style above; the
`shell` phase of `tests/run_tests.sh` runs shellcheck plus behavioral tests
against everything under `scripts/*.sh`, so a new script needs a matching
test there, not just a passing lint.

## Coverage

Every line of every shell script has to run in
[`tests/scripts/script_units.sh`](../tests/scripts/script_units.sh), the
`units` phase, which replaces git, pre-commit, detect-secrets, curl and wget
with stubs so it needs nothing installed and touches no network. Nobody
lists the scripts: the Makefile's `SHELL_SCRIPTS` discovers every file git
would commit that ends in `.sh` or `.bash` or starts with an `sh`, `bash` or
`dash` shebang, outside `tests/`, and `make print-shell-scripts` prints the
set. `SHELL_EXCLUDE` (vendored shell, each with its reason) and `SHELL_EXTRA`
(shell no extension or shebang gives away) are the only hand edits, both
empty today, and `tests/tools/test_shell_discovery.py` keeps the rule from
turning back into a list. The Python
under [`tools/`](../tools/) (this repository's own tooling, which no consumer
gets) is held to every line and every branch by its tests under
`tests/tools/`, which also holds `test_python_version_pin.py`: it fails when
the Python version in CI, `sonar.python.version`, the Makefile's python
images, the `target-version` of the root `ruff.toml` and the consumer
templates stop agreeing, since nothing moves them
together. The other Python here, `tests/scripts/test_selector_lint.py`
and the fixtures, is test code and is not measured.

`make coverage` runs the shell cases under kcov and the Python tests under
coverage.py, each in a podman container that sees the source only as a tar
stream, and fails unless both reach 100%. It needs podman on `PATH`; in a
devcontainer-airlock workbench run it as `l2 --engine --net -- make
coverage`. It also runs as a pre-push hook, and the SonarQube job runs it on every
pull request. A new
script ships with cases that reach every line of it.

## Updating the Python test dependencies

`tests/requirements.in` carries the exact pins of the environment
`make coverage` tests `tools/` in and the Tests job runs the self-test
suite in, and `tests/requirements.txt` is a lock
compiled from it with every hash, which `pip install --require-hashes`
checks. Renovate bumps both. To change one by hand, edit the `.in` file and
regenerate the lock in a container, from the `tests/` directory:

```bash
podman run --rm -v "$PWD:/w:rw,Z" -w /w ghcr.io/astral-sh/uv:python3.14-trixie-slim \
  uv pip compile --generate-hashes --python-version=3.14 --exclude-newer=P7D \
  --output-file=requirements.txt requirements.in
```

That is the command in the lock's own header, which Renovate replays.
`--exclude-newer=P7D` leaves out anything released in the last seven days,
dependencies of dependencies included.

### A security fix younger than seven days

The seven day window also holds back a security release, and Renovate
cannot make an exception: it replays the header's command as written, so its
pull request for a vulnerability alert fails to regenerate the lock and says
so. Update that one package by hand, in the same container and from the
lock's directory, letting it past the window and asking for its newest
release (`--upgrade-package`; without it, uv keeps the version already in the
lock, so a vulnerable dependency of a dependency would not move):

```bash
podman run --rm -v "$PWD:/w:rw,Z" -w /w ghcr.io/astral-sh/uv:python3.14-trixie-slim \
  uv pip compile --generate-hashes --python-version=3.14 --exclude-newer=P7D \
  --exclude-newer-package "<package>=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --upgrade-package "<package>" \
  --output-file=requirements.txt requirements.in
```

Then edit the lock's header back to the standard command above, by hand,
removing `--exclude-newer-package` (uv does not record `--upgrade-package`
there). Left in, the per package date is fixed, so it would hold that
package at today's releases for good. Read the lock's diff before
committing: the other pins are kept as preferences, not guarantees, so uv
moves another package too when the fix needs it, and each such move gets
the same review as the fix. The next Renovate update replays the standard
command once the fix is past the window.

## License

By contributing, you agree that your contributions will be licensed under
the Apache License 2.0.

## References

This document was adapted from the GitHub Gist
<https://gist.github.com/briandk/3d2e8b3ec8daf5a27a62>.

---

See also: [README.md](../README.md), [docs/getting-started.md](getting-started.md),
[docs/hook-catalogue.md](hook-catalogue.md)
