# MegaLinter guide

[MegaLinter](https://megalinter.io/) is a separate multi-linter tool this
library also ships a starter config for
([`templates/.mega-linter.yml`](../templates/.mega-linter.yml)). It is
not a checklist hook id and does not run through `pre-commit run` — it
auto-detects the linters relevant to your codebase and runs all of them,
which makes it heavier than any one checklist here. Most repos run it at
the `pre-push` git stage or in CI rather than on every commit; see the
commented-out example at the bottom of
[`templates/pre-commit-config/full.yaml`](../templates/pre-commit-config/full.yaml)
for wiring it up as a `pre-push` hook via pre-commit itself, or run it
directly as described below.

## Requirements

- Docker, or Node.js with `@megalinter/megalinter` installed globally
  (`npm install -g @megalinter/megalinter`) if you'd rather not use
  Docker locally.

## Running it locally

```shell
npx mega-linter-runner --flavor cupcake
```

Or, scoped to one descriptor while you're rolling it out (see below):

```shell
npx mega-linter-runner --env "ENABLE=MARKDOWN" --fix
```

## Configuration

Copy `templates/.mega-linter.yml` to `.mega-linter.yml` at your repo
root (`scripts/install.sh` does this for you). The starter ships with:

```yaml
APPLY_FIXES: all
DISABLE_ERRORS: true # flip to false once the codebase is green
FLAVOR_SUGGESTIONS: false
PRINT_ALL_FILES: false
SHOW_ELAPSED_TIME: true
VALIDATE_ALL_CODEBASE: false
```

`DISABLE_ERRORS: true` is deliberate for a first rollout: MegaLinter will
still report and auto-fix what it can, but a finding won't fail your
build. Once you've worked through the findings on your existing
codebase, flip it to `false` so new findings actually block.

Enable or disable specific descriptors or linters either in this file or
on the command line:

```yaml
# .mega-linter.yml
DISABLE:
  - CLOJURE
ENABLE:
  - BASH
DISABLE_LINTERS:
  - REPOSITORY_DEVSKIM
```

```shell
npx mega-linter-runner --env "ENABLE=BASH"
```

The full list of descriptors, linters, and every other config key lives
on the [official site](https://megalinter.io/latest/config-file/).

## Rolling it out gradually

Running every descriptor MegaLinter can detect, on a codebase that has
never seen it, tends to surface far more findings than one PR should
carry. A pattern that keeps each PR reviewable:

1. Pick one descriptor (`MARKDOWN`, `BASH`, `YAML`, ...).
2. Run it with `--fix`, on a branch of its own.
3. Review and merge that branch.
4. Repeat for the next descriptor.
5. Once every descriptor you care about is clean, flip
   `DISABLE_ERRORS: false`.

## Overriding a specific finding

See [`docs/overrides.md`](overrides.md) for inline-ignore syntax across
the tools this library wraps, including MegaLinter's own linters.
