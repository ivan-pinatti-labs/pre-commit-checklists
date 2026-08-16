# Getting started

This library ships pre-commit hook ids grouped into checklists (file
hygiene, spelling, per-language linting, secrets scanning, and git
message/branch guards), plus the config files those checklists expect to
find in your repo. You add one `repo:` entry to your own
`.pre-commit-config.yaml` and select the hook ids you want.

## Requirements

- [`pre-commit`](https://pre-commit.com/#install) itself.
- [`detect-secrets`](https://github.com/Yelp/detect-secrets), if you use
  `checklist-security-credentials` (recommended, and in every template
  here).
- `git`, obviously, and for the per-language checklists, whatever
  toolchain that language needs (Node for JavaScript/TypeScript,
  Terraform for the Terraform checklist, and so on) — see
  [`docs/hook-catalogue.md`](hook-catalogue.md) for exactly what each
  hook shells out to.

## Option A: `scripts/install.sh`

Clone this library, then run its bootstrap script against your repo:

```shell
git clone https://github.com/ivan-pinatti/pre-commit-checklists
cd pre-commit-checklists
./scripts/install.sh --target /path/to/your-repo --template recommended
```

`--template` is any file in
[`templates/pre-commit-config/`](../templates/pre-commit-config/) by
name, without the `.yaml` extension: `minimal`, `recommended`, `full`,
`python`, `shell`, `terraform`, `javascript`, `typescript`.

The script:

1. Copies the chosen `.pre-commit-config.yaml` and the supporting tool
   configs (`.editorconfig`, `.cspell.json`, `.yamllint.yml`,
   `.markdownlint.yaml`, `.lycheeignore`, `.mega-linter.yml`) into your
   repo, without clobbering files that already exist (pass `--force` to
   overwrite).
2. Appends the MegaLinter/pre-commit log entries from
   [`templates/gitignore.fragment`](../templates/gitignore.fragment) to
   your `.gitignore`.
3. Generates `.secrets.baseline` with `detect-secrets scan`.
4. Runs `pre-commit install` in your repo, which also wires up the
   `commit-msg` git hook stage if the template you chose uses it.

Run `./scripts/install.sh --help` for the full flag list.

## Option B: by hand

1. Copy one file from
   [`templates/pre-commit-config/`](../templates/pre-commit-config/) to
   `.pre-commit-config.yaml` at the root of your repo.
2. Update the `rev:` pin to the
   [latest release tag](https://github.com/ivan-pinatti/pre-commit-checklists/releases)
   — see [`docs/versioning.md`](versioning.md) for what that pin means.
3. Copy the supporting tool configs you need from
   [`templates/`](../templates/) into your repo root.
4. Generate a secrets baseline:

   ```shell
   detect-secrets scan --exclude-files '\.git/' > .secrets.baseline
   chmod 600 .secrets.baseline
   ```

5. Install the hooks:

   ```shell
   pre-commit install
   ```

## First run

```shell
pre-commit run --all-files
```

Expect the first run to reformat or fail on pre-existing files —
`checklist-basic`'s `end-of-file-fixer` and `trailing-whitespace`, or a
language checklist's formatter, will happily rewrite a whole codebase the
first time it sees it. Review the diff, commit it separately from your
next real change, and you're set: every future commit only sees the
files it touches.

## Customizing what runs

- Drop a hook id you don't want from your `.pre-commit-config.yaml`, or
  add one from [`docs/hook-catalogue.md`](hook-catalogue.md) that isn't
  in the template you started from.
- To require ticket ids in branch names and commit messages instead of
  plain [Conventional Commits](https://www.conventionalcommits.org/), or
  to change which linter finding gets ignored where, see
  [`docs/overrides.md`](overrides.md).
- To run MegaLinter alongside these checklists, see
  [`docs/megalinter.md`](megalinter.md).

## Upgrading later

`pre-commit autoupdate` in your repo bumps the `rev:` pin on this
library, but not the hook versions pinned inside the checklists
themselves. See [`docs/versioning.md`](versioning.md) for why, and what
moves those.
