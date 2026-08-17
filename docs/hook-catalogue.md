# Hook catalogue

Source data for every hook id exposed in
[`.pre-commit-hooks.yaml`](../.pre-commit-hooks.yaml). Each id dispatches
to a checklist file under [`checklists/`](../checklists/) (or, for the
two git-message hooks, directly to a script under
[`scripts/`](../scripts/)). See that file for exact upstream `rev:`
pins, which move independently of this table; see
[`docs/versioning.md`](versioning.md).

The "Matches" column is what you must add yourself: `.pre-commit-hooks.yaml`
does not bake in a `types:`/`files:` selector for most ids (two
exceptions are noted), so a bare `- id: checklist-json` with no selector
runs against **every** file pre-commit hands it, which is usually not
what you want. Every template in
[`templates/pre-commit-config/`](../templates/pre-commit-config/)
already applies the selector shown here; this table exists so you can
build your own selection from scratch.

| Hook id | Runs | Matches | Requires |
| --- | --- | --- | --- |
| `checklist-basic` | check-added-large-files (max 1024kb), check-case-conflict, check-docstring-first, check-illegal-windows-names, check-merge-conflict, check-symlinks, destroyed-symlinks, end-of-file-fixer, mixed-line-ending, trailing-whitespace | all files (no selector needed) | none |
| `checklist-spell` | cspell, config from `.cspell.json` | all files cspell can read (no selector needed) | `.cspell.json` at repo root |
| `checklist-markdown` | markdownlint-cli2, markdown-link-check | `types: [markdown]` | `.markdownlint.yaml` for markdownlint-cli2's own rules |
| `checklist-json` | check-json, Prettier | `types: [json]` | Node (Prettier runs via `language: node`) |
| `checklist-yaml` | check-yaml, yamllint, Prettier | `types: [yaml]` | `.yamllint.yml`; Node for Prettier |
| `checklist-toml` | check-toml | `types: [toml]` | none |
| `checklist-xml` | check-xml | `types: [xml]` | none |
| `checklist-security-credentials` | detect-private-key, detect-secrets | all files (no selector needed) | `.secrets.baseline` at repo root, `scripts/install.sh` generates one |
| `checklist-git-valid-branches` | `scripts/check-branch-name.sh` | not file-based: `pass_filenames: false`, `always_run: true` | none |
| `checklist-git-commit-msg` | `scripts/check-commit-msg.sh` | `stages: [commit-msg]`, `files: ^\.git/COMMIT_EDITMSG$` | `default_install_hook_types` must include `commit-msg` |
| `checklist-git-protected-branches` | no-commit-to-branch, pattern `(?i)(develop\|staging\|main\|master)` | not file-based: `pass_filenames: false`, `always_run: true` | none |
| `checklist-github-actions` | actionlint-docker | `files: ^\.github/` | Docker (actionlint-docker runs in a container) |
| `checklist-dev-dotenv` | dotenv-linter | `files: '(^\|/)\.env(\..+)?$'` | none |
| `checklist-dev-editorconfig` | editorconfig-checker | all files subject to `.editorconfig` (no selector needed) | `.editorconfig` at repo root |
| `checklist-dev-shell` | check-executables-have-shebangs, check-shebang-scripts-are-executable, shellcheck (`--severity=error`), shfmt (`--indent 2`) | `types: [shell]` (the hook's own `.pre-commit-hooks.yaml` entry additionally bakes in `files: \.(sh\|bash)$`) | none |
| `checklist-dev-python` | check-ast, check-builtin-literals, debug-statements, name-tests-test (`--django`), requirements-txt-fixer, ruff-check (`--fix`), ruff-format | `files: '(\.py$\|(^\|/)requirements\.txt$)'` | none |
| `checklist-dev-terraform` | terraform-fmt, terraform-validate, tflint | `files: \.tf$` | Terraform CLI |
| `checklist-dev-javascript` | biome-check (`--indent-style=space --indent-width=2`) | `types: [javascript]` | Node (biome-check runs via `language: node`) |
| `checklist-dev-typescript` | biome-check (`--indent-style=space --indent-width=2`) | `files: \.ts$` | Node (biome-check runs via `language: node`) |
| `checklist-dev-docker` | hadolint-docker | `types: [dockerfile]` | Docker (hadolint-docker runs in a container) |

## Why the selector matters

Two defects in an earlier version of this checklist set came from
getting a selector wrong, not from the underlying tool: a
`types: [json]` selector on the dotenv checklist meant it never matched
a `.env` file (dotenv files aren't typed `json`), and `types_or: [python]`
combined with `files: ^requirements\.txt$` on the Python checklist
resolved to "a Python file literally named `requirements.txt`": pre-commit
ANDs `types`/`types_or` with `files`, it does not OR them. Both are
fixed in the table above and in every shipped template. If you write
your own selector for a hook id, prefer one `files:` regex over
combining `types:`/`types_or:` with `files:` unless you have checked
what the AND actually resolves to.

## Pin `stages:` too, if you install more than the pre-commit stage

`checklist-git-commit-msg` is the one id here that isn't meant to run at
the `pre-commit` git stage: it needs `stages: [commit-msg]`. If your
`default_install_hook_types` includes anything beyond `pre-commit`
(`commit-msg`, `pre-push`, ...), every *other* hook id also needs an
explicit `stages: [pre-commit]`, or pre-commit will run it again at
each of those other stages too. That's wasted work at best; at worst,
a hook re-run outside the context it expects can fail outright: cspell
does exactly this, exiting non-zero on a commit-msg-stage invocation
where it is handed zero matching files. Every shipped template that
enables `commit-msg` (`recommended.yaml`, `full.yaml`) already sets
`stages: [pre-commit]` on every hook that needs it; keep doing that if
you add more hooks of your own to either file.
