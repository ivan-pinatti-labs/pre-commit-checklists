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
| `checklist-dev-dotenv` | [dotenv-linter/dotenv-linter](https://github.com/dotenv-linter/dotenv-linter) (Rust), run directly from its published image, not through its own `.pre-commit-hooks.yaml`; see [Which dotenv-linter](#which-dotenv-linter) below | `files: '(^\|/)\.env(\..+)?$'`, baked into the local hook itself | Docker or Podman on PATH |
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

## Which dotenv-linter

Two unrelated projects share the name "dotenv-linter":

- [dotenv-linter/dotenv-linter](https://github.com/dotenv-linter/dotenv-linter),
  Rust, 14 named checks, a `--ignore-checks CHECK_NAME[,CHECK_NAME...]`
  flag and a matching `DOTENV_LINTER_IGNORE_CHECKS` environment variable,
  an `--exclude` path flag, tagged releases up to v4.0.0.
- [wemake-services/dotenv-linter](https://github.com/wemake-services/dotenv-linter),
  Python, a wider rule set with no CLI flag to bypass one rule (only
  inline `# dotenv:disable[ViolationName]` comments in the `.env` file
  itself), tagged releases up to 0.9.0.

Both are actively maintained; this is not a maintenance-status pick.
`checklist-dev-dotenv` runs the Rust project, because that is what most
people mean by "dotenv-linter" and what an earlier version of this
checklist did not do: it ran the Python one, silently, and a consumer
migrating a real repo onto this library got nine findings on a normal
`.env.example` with no quick way to quiet any of them. If you adopted
`checklist-dev-dotenv` on an earlier release expecting the Python
project's rule set, this is a breaking change; see the release notes for
the version that made this switch.

The checklist does not consume the Rust project's own
`.pre-commit-hooks.yaml` (`language: docker`, building the image from
that repo's own Dockerfile on first use). That Dockerfile's
`FROM builder-${TARGETARCH}` line only resolves under BuildKit/buildx;
on a plain Docker Engine install with no buildx plugin, confirmed
`docker build` fails with "invalid reference format" before
dotenv-linter ever runs, an install-time failure with no obvious
connection to the tool it belongs to. `checklists/checklist-dev-dotenv.yaml`
instead runs the project's own published image
(`docker.io/dotenvlinter/dotenv-linter`) directly via `docker run` (or
`podman run`, whichever is on `PATH`), which needs no local image build
at all. That file's own header comment has the full reasoning, including
why the bind mount carries the `Z` SELinux relabel option: confirmed on
an SELinux-enforcing host that podman, without it, reports "Nothing to
check" and exits 0 on files it was never able to read, a false pass.

Because `checklist-dev-dotenv` still routes through
`scripts/run-checklist.sh` like every other checklist-* id (see
[the args: hazard](overrides.md#do-not-put-args-on-a-checklist--id-that-routes-through-run-checklistsh)),
there is no way to hand it `--ignore-checks` or `--exclude` from a
consumer's own `.pre-commit-config.yaml`, and the environment variable
does not help either: neither pre-commit's own `language: docker` support
nor this checklist's `docker run` invocation forwards the calling shell's
environment into the container. A consumer who needs either flag should
add dotenv-linter as their own hook entry pointed at the same image
instead of going through this checklist id; see
[`docs/overrides.md`](overrides.md#passing-a-flag-to-the-tool-a-checklist-wraps)
for the investigation behind why no config-only override exists.

Concretely, that means the same `repo: local` entry
`checklists/checklist-dev-dotenv.yaml` uses, copied into a consumer's
own `.pre-commit-config.yaml`, with the flag added:

```yaml
repos:
  - repo: local
    hooks:
      - id: dotenv-linter
        name: dotenv-linter (dotenv-linter/dotenv-linter, Rust)
        language: system
        files: '(^|/)\.env(\..+)?$'
        entry: >-
          bash -c '
          runtime=$(command -v docker || command -v podman) || {
          echo "dotenv-linter needs docker or podman on PATH." >&2;
          exit 1;
          };
          exec "${runtime}" run --rm -v "$(pwd):/src:ro,Z" -w /src
          docker.io/dotenvlinter/dotenv-linter:4.0.0 check --skip-updates
          --ignore-checks LowercaseKey,UnorderedKey "$@"
          ' --
```

Verified directly, through `pre-commit run` rather than the underlying
image alone: against a `.env` file with a lowercase key listed out of
order (`api_key` before `API_KEY`), `checklist-dev-dotenv`'s own entry
(no `--ignore-checks`) fails with one `LowercaseKey` and one
`UnorderedKey` finding; the entry above, with those two check names
added to `--ignore-checks`, passes the identical file with zero
findings. Swap in whatever check names, or an `--exclude` pattern, a
given repository needs; the
[dotenv-linter README](https://github.com/dotenv-linter/dotenv-linter)'s
"Available checks" list names every check `--ignore-checks` accepts.

## `stages:` depends on why you installed more than the pre-commit stage

`checklist-git-commit-msg` is the one id here that isn't meant to run at
the `pre-commit` git stage: it needs `stages: [commit-msg]`. Beyond
that one id, what `stages:` the rest of your hooks need depends on
*why* `default_install_hook_types` includes something beyond
`pre-commit`, and the two common reasons want opposite answers.
Pick the one that matches your setup; do not apply the first one by
default just because it is listed first.

### Installing `commit-msg` only, no re-sweep planned

If `commit-msg` is the only extra stage, and nothing is meant to run
your fast hooks again at any other stage, pin every *other* hook id to
an explicit `stages: [pre-commit]`. Without it, pre-commit runs each of
them again at the commit-msg stage too, which is wasted work at best;
at worst, a hook re-run outside the context it expects fails outright:
cspell does exactly this, exiting non-zero on a commit-msg-stage
invocation where it is handed zero matching files. Every shipped
template that enables `commit-msg` (`recommended.yaml`, `full.yaml`)
already sets `stages: [pre-commit]` on every hook that needs it; keep
doing that if you add more hooks of your own to either file.

### Re-sweeping the fast hooks at `pre-push` for CI parity

A different, equally legitimate setup installs `pre-push` too and
re-runs the same fast hooks there on purpose, so a single
`pre-commit run --all-files --hook-stage pre-push` gives CI one command
that exercises everything, matching what already ran locally at commit
time. Applying the previous section's advice here (`stages: [pre-commit]`
on every hook) is exactly wrong: pre-commit skips a hook at a stage it
is not pinned to without printing a failure, so every hook you pin to
`pre-commit` only stops answering to `--hook-stage pre-push` silently.
CI's one command then "passes" having actually run nothing, which is
worse than a failure, because nothing in the output says so. Confirmed
directly: a hook with no `stages:` key at all runs at both
`--hook-stage pre-commit` and `--hook-stage pre-push` once
`default_install_hook_types` includes both; a hook pinned to
`stages: [pre-commit]` runs at the first and is simply absent, with no
error, from the second.

For this setup, leave the hook ids you want re-swept with no `stages:`
key at all (pre-commit's default is every installed stage, which is
exactly the re-sweep you want), and reserve an explicit `stages:` for
the ids that must answer a different question at a different stage
rather than the same question again: `checklist-git-commit-msg`
(`stages: [commit-msg]`, as above regardless of setup), and, if you also
use it, `checklist-git-protected-branches`. That one checks which
branch `HEAD` is on right now rather than file content, so re-running it
at `pre-push` is not a repeat of the same answer, it can be a different
one (a `workflow_dispatch` CI run can legitimately be checked out on
`main`); pin it to `stages: [pre-commit]` so a push-time re-run of a
question about local commit intent does not fail a run that was never
about that.

## Every checklist-* id sets require_serial: true

Every checklist-* hook id in [`.pre-commit-hooks.yaml`](../.pre-commit-hooks.yaml)
carries `require_serial: true`. Without it, pre-commit is free to shard
the file list it hands a hook into up to one batch per CPU core, and
each batch pays for its own invocation of `scripts/run-checklist.sh`,
which itself starts a second, nested `pre-commit run` against a
checklist file in this library. On a repository with enough matching
files, that turns one checklist id into dozens of nested bootstraps
running in parallel instead of one.

Measured directly: 650 tracked files against `checklist-basic` with no
`require_serial`, on a 32-core machine, sharded into 31 batches (one
`check-added-large-files...Passed` line per batch, printed 31 times,
not once) and took 3.0 to 3.15 seconds across three runs. The identical
run with `require_serial: true` added produced one batch, one clean set
of status lines, and took 0.82 seconds across three runs, about 3.7
times faster here, on top of no longer looking like the same hook ran
dozens of times. On a small, non-sharding file count (5 files) the two
configurations measured the same (0.59 to 0.62 seconds either way):
`require_serial: true` costs nothing when there is nothing to shard, so
it is safe on every checklist-* id regardless of how many files a given
consumer repository hands it, including the file-scoped ones
(`checklist-dev-terraform`, `checklist-dev-typescript`, and so on) that
will rarely see more than a handful of matches in most repositories. It
is also safe at the other extreme: pre-commit still splits an argument
list too long for the operating system to exec in one call, regardless
of `require_serial`, it just runs those splits one after another
instead of in parallel, rather than raising an error. `require_serial`
only removes the splitting pre-commit otherwise does purely to spread
work across CPU cores.

This is set once, in `.pre-commit-hooks.yaml`, not repeated in
`templates/pre-commit-config/*.yaml`. Confirmed directly: a consumer
`.pre-commit-config.yaml` that references a hook id by `repo:` + `rev:`
and does not mention `require_serial` at all still inherits `true` from
the manifest, pre-commit only overrides the keys a consumer's own hook
entry actually sets. Every template here uses exactly that `repo:` +
`rev:` shape, so none of them need `require_serial:` written out; adding
it there would be redundant, not additive. A `repo: local` hook, which
does not read this library's manifest at all, is the one shape that
needs it stated explicitly; this repository's own dogfood
[`.pre-commit-config.yaml`](../.pre-commit-config.yaml) is exactly that
shape, and states it on every checklist-* id in that file for the same
reason.

## Adopting part of a bundled checklist

Three checklists bundle a plain validator together with a second tool
that a consumer may not want at all: `checklist-json` and
`checklist-yaml` also run Prettier, a formatter, not just a syntax
check; `checklist-markdown` also runs `markdown-link-check`, which needs
network access to do its job. A repository with generated or
vendor-owned JSON/YAML (a dashboard export, a lockfile-adjacent state
file) does not want Prettier rewriting it on every commit, and a
repository whose policy is that committing must not depend on network
reachability does not want a link checker deciding whether a commit
succeeds. `checklist-dev-shell` (shfmt) and `checklist-dev-python`
(ruff-format) bundle a formatter the same way, but neither has been
reported as friction the way the three above have: shfmt and ruff-format
are the idiomatic, expected companion to shellcheck and ruff-check for
most repositories in a way Prettier reformatting a Grafana export, or a
link checker requiring network access to lint markdown, are not.

There is no way today to adopt just the validator from any of these
checklist ids from a consumer's own `.pre-commit-config.yaml`. Three
ways to close that gap were considered:

- **Split the id** (for example `checklist-yaml` keeps check-yaml and
  yamllint, a new `checklist-yaml-format` adds Prettier on top). Gives a
  consumer a real choice at the config level, with no override needed.
  Costs a new hook id per split (more surface to document and keep
  selectors correct on, per the earlier section on why the selector
  matters), and is a deliberate, reviewed decision about this library's
  hook surface, not something to retrofit across several checklists
  inside one sprint that exists to document friction, not restructure
  the catalogue on the strength of one migration's findings.
- **Document a `SKIP` recipe.** `SKIP` is an environment variable
  `scripts/run-checklist.sh`'s nested `pre-commit run` inherits like any
  other subprocess does, so `SKIP=<inner-hook-id>` reaches the specific
  tool inside a checklist the same way it reaches a checklist id itself
  at the outer level. No new hook id, no config change, works today.
  Costs a consumer having to know and set the exact inner hook id
  (`prettier-json`, `prettier-yaml`, `markdown-link-check`), and only
  skips it, it does not select "check-yaml and yamllint but not
  Prettier" as a persistent, no-argument default the way a split id
  would.
- **Leave it as is and document the limitation.** Zero cost to this
  library, but leaves the gap open with no path out short of forking a
  checklist file.

The `SKIP` recipe is the smallest change that actually closes the gap
consumers hit, and it was verified rather than assumed: see
[`docs/overrides.md`](overrides.md#keeping-the-validator-dropping-the-formatter-or-network-check)
for the confirmed-working recipe. Splitting hook ids remains on the
table as a future, deliberate minor-version addition if demand for a
persistent default (rather than a per-commit or per-CI-job override)
shows up; it is not implemented here.
