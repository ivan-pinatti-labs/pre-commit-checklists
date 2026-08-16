# Versioning contract

This library is versioned with [Semantic Versioning](https://semver.org/):
tags look like `v1.2.3`. Consumers pin to one of those tags in their own
`.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/ivan-pinatti/pre-commit-checklists
    rev: v1.2.3
    hooks:
      - id: checklist-basic
```

## Two different things both called "updating"

There are two independent version pins in play, and they move at
different times, by different commands, in different repos:

1. **The library pin** — the `rev:` in *your* `.pre-commit-config.yaml`,
   pointing at a tag of this repo.
2. **The upstream hook pins** — the `rev:` fields inside *this repo's*
   `checklists/checklist-*.yaml` files, pointing at tags of
   `pre-commit/pre-commit-hooks`, `astral-sh/ruff-pre-commit`, and so on.

Running `pre-commit autoupdate` in your repo only ever touches (1). It
rewrites the `rev:` next to `repo: https://github.com/ivan-pinatti/pre-commit-checklists`
to the latest tag of this library. It has no way to see inside a hook
that shells out to a nested `pre-commit run --config <checklist>.yaml`
(which is how every checklist hook id works — see
[`docs/hook-catalogue.md`](hook-catalogue.md)), so it cannot and does not
touch (2).

(2) only moves when **this repo** cuts a new release: its own
`make autoupdate` bumps every checklist's upstream hook pins, that
change gets reviewed and tagged, and the new tag is what your `rev:`
pin picks up the next time you run `pre-commit autoupdate` yourself.

## What this means in practice

- **To pick up a newer version of a linter this library wraps** (a newer
  ruff, a newer shellcheck, a newer markdownlint-cli2): wait for, or ask
  for, a new release of this library, then bump your `rev:` pin. You
  cannot get there by running `pre-commit autoupdate` alone; the pin it
  bumps is not the one that matters for that.
- **A patch release** (`v1.2.3` to `v1.2.4`) is a bug fix to a script, a
  checklist selector, or docs — no hook id is added, removed, or
  reworked in a way that changes what it matches.
- **A minor release** (`v1.2.0` to `v1.3.0`) can add a hook id or a
  checklist, or bump an upstream hook pin inside a checklist. Existing
  hook ids keep matching what they matched before.
- **A major release** (`v1.0.0` to `v2.0.0`) can remove or rename a hook
  id, or change what files an existing hook id matches. Check the
  release notes before bumping across one.
- Release notes list every checklist whose upstream pins moved, so you
  can tell whether bumping your `rev:` will also change formatter/linter
  output in your repo, independent of anything you configured yourself.

## Checking what you're pinned to

```shell
grep -A1 'ivan-pinatti/pre-commit-checklists' .pre-commit-config.yaml
```

Compare that `rev:` against the
[releases page](https://github.com/ivan-pinatti/pre-commit-checklists/releases)
to see how far behind you are and what changed since.
