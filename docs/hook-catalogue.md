# Hook catalogue

<!-- cspell:words zizmor zizmorcore artipacked -->

Source data for every hook id exposed in
[`.pre-commit-hooks.yaml`](../.pre-commit-hooks.yaml). Each id dispatches
to a checklist file under [`checklists/`](../checklists/) (or, for the
two git-message hooks, directly to a script under
[`scripts/`](../scripts/)). See that file for exact upstream `rev:`
pins, which move independently of this table; see
[`docs/versioning.md`](versioning.md).

The "Matches" column is what you must add yourself: `.pre-commit-hooks.yaml`
does not bake in a `types:`/`files:` selector for most ids (the one
exception is noted), so a bare `- id: checklist-json` with no selector
runs against **every** file pre-commit hands it, which is usually not
what you want. Every template in
[`templates/pre-commit-config/`](../templates/pre-commit-config/)
already applies the selector shown here; this table exists so you can
build your own selection from scratch.

| Hook id | Runs | Matches | Requires |
| --- | --- | --- | --- |
| `checklist-basic` | check-added-large-files (max 1024kb), check-case-conflict, check-docstring-first, check-illegal-windows-names, check-merge-conflict, check-symlinks, destroyed-symlinks, end-of-file-fixer, mixed-line-ending, trailing-whitespace | all files (no selector needed) | none |
| `checklist-spell` | cspell, config from `.cspell.json` | all files cspell can read (no selector needed) | `.cspell.json` at repo root |
| `checklist-markdown` | markdownlint-cli2, markdown-link-check | `types: [markdown]` | Node; `.markdownlint.yaml` for markdownlint-cli2's own rules, `.markdown-link-check.json` optionally for link ignores (see [`docs/overrides.md`](overrides.md#ignoring-a-link-lychee--markdown-link-check)) |
| `checklist-json` | check-json, Prettier | `types_or: [json, json5]`; see [JSON5](#json5) | Node (Prettier runs via `language: node`) |
| `checklist-yaml` | check-yaml, yamllint, Prettier | `types: [yaml]` | `.yamllint.yml`; Node for Prettier |
| `checklist-toml` | check-toml | `types: [toml]` | none |
| `checklist-xml` | check-xml | `types: [xml]` | none |
| `checklist-security-credentials` | detect-private-key, detect-secrets | all files (no selector needed) | `.secrets.baseline` at repo root, `scripts/install.sh` generates one |
| `checklist-git-valid-branches` | `scripts/check-branch-name.sh` | not file-based: `pass_filenames: false`, `always_run: true` | none |
| `checklist-git-commit-msg` | `scripts/check-commit-msg.sh` | `stages: [commit-msg]`, `files: ^\.git/COMMIT_EDITMSG$` | `default_install_hook_types` must include `commit-msg` |
| `checklist-git-protected-branches` | no-commit-to-branch, pattern `(?i)(develop\|staging\|main\|master)` | not file-based: `pass_filenames: false`, `always_run: true` | none |
| `checklist-github-actions` | actionlint-docker, zizmor (`--no-online-audits`, pinned v1.29.0, offline audits only, see [Zizmor: offline by default](#zizmor-offline-by-default) below) | `files: ^\.github/workflows/` (both hooks) | Docker (actionlint-docker runs in a container); Python (zizmor installs via `additional_dependencies`) |
| `checklist-dev-dotenv` | [dotenv-linter/dotenv-linter](https://github.com/dotenv-linter/dotenv-linter) (Rust), run directly from its published image, not through its own `.pre-commit-hooks.yaml`; see [Which dotenv-linter](#which-dotenv-linter) below | `files: '(^\|/)\.env(\..+)?$'`, baked into the local hook itself | Docker or Podman on PATH |
| `checklist-dev-editorconfig` | editorconfig-checker | all files subject to `.editorconfig` (no selector needed) | `.editorconfig` at repo root |
| `checklist-dev-shell` | check-executables-have-shebangs, check-shebang-scripts-are-executable, shellcheck (`--severity=error`), shfmt (`--indent 2`) | `types: [shell]`, which covers extensionless files such as `.bashrc` and `.zshrc`; see [Why `checklist-dev-shell` has no baked selector](#why-checklist-dev-shell-has-no-baked-selector) | none |
| `checklist-dev-python` | check-ast, check-builtin-literals, debug-statements, name-tests-test (`--django`), requirements-txt-fixer, ruff-check (`--fix`, plus the flake8-bandit security floor, see [Python security rules](#python-security-rules)), ruff-format | `files: '(\.py$\|(^\|/)requirements\.txt$)'` | none; `templates/ruff.toml` is optional and `scripts/install.sh` copies it |
| `checklist-dev-terraform` | terraform-fmt, terraform-validate, tflint | `files: \.tf$` | Terraform CLI |
| `checklist-dev-javascript` | biome-check (`--indent-style=space --indent-width=2`) | `types: [javascript]` | Node (biome-check runs via `language: node`) |
| `checklist-dev-typescript` | biome-check (`--indent-style=space --indent-width=2`) | `files: \.ts$` | Node (biome-check runs via `language: node`) |
| `checklist-dev-docker` | hadolint-docker | `types: [dockerfile]` | Docker (hadolint-docker runs in a container) |
| `checklist-dev-make` | checkmake | `types: [makefile]`, baked into checkmake's own hook manifest: `Makefile`, `makefile`, `GNUmakefile`, `*.mk`, `*.make` | `checkmake.ini` at repo root, `scripts/install.sh` copies one in; see [Makefile linting](#makefile-linting) before adopting |

## JSON5

`checklist-json` covers `.json5` as well as `.json`, and the two file types
take different paths through it.

`check-json` is a strict JSON parser (Python's `json.load`). Handed a
`.json5` file it fails immediately on the first comment or unquoted key: a
real `renovate.json5` produces `Expecting property name enclosed in double
quotes: line 2 column 3`. It never sees one, because its own upstream hook
manifest carries `types: [json]` and `identify` tags `.json5` as `json5`,
not `json`. It self-filters, and the checklist reports it as
`(no files to check)Skipped` on a json5-only run.

Prettier reads json5 natively and formats it.

So a `.json5` file is formatted but never syntax-checked, and a `.json`
file gets both. That is the correct split, not a gap being papered over:
there is no point running a strict JSON parser against a format defined by
not being strict JSON. If you want json5 validated as well as formatted,
add a json5-aware checker as your own hook entry; see
[`docs/overrides.md`](overrides.md).

The selector must be `types_or: [json, json5]`. A plain `types: [json]`
matches neither the `json5` tag nor the file, so a repo whose only
JSON-family file is a `.json5` (a `renovate.json5`, commonly) silently gets
no coverage at all.

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

## Why `checklist-dev-shell` has no baked selector

This id used to bake `files: \.(sh|bash)$` into `.pre-commit-hooks.yaml`.
pre-commit ANDs a hook's manifest selector with the consumer's own, so a
consumer following the guidance above (`types: [shell]`, which is what both
shipped templates use) got the intersection: shell files that also end in
`.sh` or `.bash`.

Everything `identify` tags `shell` without one of those two extensions was
dropped silently: `.bashrc`, `.bash_aliases`, `.bash_profile`, `.zshrc`,
`.profile`, and any extensionless script carrying a shebang. A hook that
matches zero files exits 0, so this presented as a clean pass rather than
as missing coverage.

The selector is gone; `types: [shell]` alone now decides. If you select a
bare `- id: checklist-dev-shell` with no selector at all, every file
pre-commit hands the hook reaches it. `shellcheck` and `shfmt` self-filter
on their own `types: [shell]`, but `check-executables-have-shebangs` does
not, so give the id a selector rather than relying on that.

Note this was only ever reachable through the real consumer path
(`repo: <url>` plus `rev:`). This repository's own dogfood
`.pre-commit-config.yaml` restates each hook as `repo: local` and never
carried the regex, which is why nothing here caught it;
`tests/scripts/consumer_path.sh` now guards it specifically.

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

## Python security rules

`checklist-dev-python` passes `--extend-select S` to ruff, which turns on
[flake8-bandit](https://docs.astral.sh/ruff/rules/#flake8-bandit-s). This is a
floor the checklist enforces, not a default a consumer can drift away from
without noticing.

### Why it is enforced rather than offered

Ruff with no configuration selects `E4`, `E7`, `E9` and `F`: style, syntax and
undefined names. No security rules. So a repository that adopts
`checklist-dev-python` and never writes a `ruff.toml` gets no security analysis
of its own Python, while appearing to have adopted a Python checklist.

That is not hypothetical. Four repositories in this organization were in
exactly that state, including this one, whose `scripts/*.py` parse pull request
diffs and GitHub API responses. A fifth had found the gap by hand months
earlier and fixed it locally, leaving a comment in its own `ruff.toml` that
says so:

```toml
"S",   # flake8-bandit, the security rules this repo was missing
```

A lesson learned in one repository and not returned to the library is the
failure this library exists to prevent, so the rule moved here.

### It extends, it never replaces

Both flags are the `extend` form:

```yaml
args:
  - "--fix"
  - "--extend-select"
  - "S"
  - "--extend-per-file-ignores"
  - "**/test_*.py:S101,**/*_test.py:S101,**/tests/**:S101,**/conftest.py:S101"
```

`--extend-select` adds to whatever a consumer's own `select` names rather than
overriding it, and `--extend-per-file-ignores` does the same for their ignores.
Nothing a consumer has configured is lost by adopting this id.

Measured on ruff v0.16.6, because the precedence is not obvious and guessing it
wrong in either direction is expensive:

| Consumer `ruff.toml` | `S602` still reported |
| --- | --- |
| `ignore = ["S"]` | yes |
| `extend-ignore = ["S"]` | yes |
| `ignore = ["S602"]` | yes |
| `select = ["E", "F"]` | yes |
| `per-file-ignores = {"app.py" = ["S"]}` | **no** |

So the floor survives a consumer's `select` and `ignore` lists, and their own
`F401` per-file ignore still applies alongside it. One route does switch it
off: a `per-file-ignores` entry covering the path. That is a deliberate,
path-scoped act rather than something anyone does by accident, but it means
this is a floor by default and not a floor by force. If you need it
unremovable, that is a branch protection question rather than a ruff one.

### Why S101 is exempted in tests

`S101` is "use of assert detected". In application code an assert used as a
runtime check is a real finding, because `python -O` removes it. In a pytest
file it is the entire point, and the rule fires on every assertion in the
suite.

Shipping the security rules without that exemption would flood any repository
with tests on the first run, and a check that floods on adoption gets switched
off the same day. The four path patterns cover what pytest itself discovers: `test_*.py` and
`*_test.py` anywhere, anything under a `tests/` directory, and `conftest.py`.
`*_test.py` matters because a file like `parser_test.py` sitting beside the
module it tests is outside `tests/` and would otherwise be flooded.

These exemptions cannot be narrowed back. `--extend-per-file-ignores` unions
the hook's patterns with the consumer's, and a union has no subtraction, so
adding your own entry adds suppression rather than removing it. Confirmed on
ruff v0.16.6: with the flag present, `S101` is silent in `tests/` no matter
what the consumer's own `per-file-ignores` says, and reappears only when the
flag is absent. Turning `S101` back on for a path listed here therefore means
not using this hook id for that path.

### `templates/ruff.toml` is the fuller ruleset, not the floor

The floor travels with the hook id, so it applies whether or not a consumer
copies anything. [`templates/ruff.toml`](../templates/ruff.toml), which
`scripts/install.sh` copies in, selects the wider set this library recommends
(bugbear, comprehensions, pyupgrade, isort, ruff's own rules) and repeats the
per-file ignores in config form.

Deleting `"S"` from that file does **not** turn the security rules off, because
the checklist requests them separately, and neither does adding `S` to
`ignore`. The fuller ruleset is a preference and can be edited freely. The one
edit that does switch the floor off for a path is a `per-file-ignores` entry
naming it, per the table above.

### What this does not cover

Ruff reads one file at a time. It catches what is wrong on sight, such as
`shell=True` or a hardcoded password, and it runs in under a second on every
commit. It does not follow data across function or module boundaries, so it
cannot see a value that arrives untrusted in one file and reaches a dangerous
call in another.

That is CodeQL's job, and [`templates/workflows/codeql.yml`](../templates/workflows/codeql.yml)
is a starting point for it. The two are complementary, and the split is
deliberate: the fast per-file analysis blocks a pull request, while the slow
cross-file analysis runs on the default branch and reports to the security tab.
See that template's header for why it carries no `pull_request` trigger.

CodeQL supports no shell at all, so for a repository whose product is bash
scripts, `checklist-dev-shell`'s shellcheck remains the only analysis that
sees the code that matters most.

## Makefile linting

`checklist-dev-make` runs [checkmake](https://github.com/checkmake/checkmake).
It is the only id in this library that arrives with a convention attached, so
read this before turning it on.

### Why checkmake and not the alternatives

Three tools were evaluated. checkmake is a linter: it reports and does not
rewrite. [mbake](https://github.com/EbodShojaei/bake) is a formatter, and it
reformats against deliberate style, collapsing the aligned continuation
indentation of multi line `docker run` blocks and the aligned columns of
shorthand alias targets to a single tab. MegaLinter has no Make descriptor at
all, so matching MegaLinter and linting nothing are the same answer.

### Declare `.PHONY` one line at a time

checkmake reads only the **first physical line** of a `.PHONY` declaration and
silently drops every backslash continuation. So this

```makefile
.PHONY: all build \
        test clean
```

leaves `test` and `clean` invisible to it. `phonydeclared` then reports any of
them that has no body as undeclared, and `minphony` reports them as missing.
Both are false. Writing the same declaration as

```makefile
.PHONY: all build
.PHONY: test clean
```

is exactly equivalent to make and parses correctly. On a 550 line Makefile
with 25 targets across 5 continuation lines, the rewrite took 7 false findings
to zero without touching a single target.

This is [checkmake#280](https://github.com/checkmake/checkmake/issues/280),
with a fix open as
[checkmake#281](https://github.com/checkmake/checkmake/pull/281). Three things
have to happen before the constraint lifts, not one: that pull request merges,
checkmake cuts a release containing it, and
[`checklists/checklist-dev-make.yaml`](../checklists/checklist-dev-make.yaml)
moves its `rev:` to that release. Until the pin moves, a merged fix changes
nothing here. It is not specific to space indented
continuations; tab indented ones fail identically, which is what distinguishes
it from [checkmake#257](https://github.com/checkmake/checkmake/issues/257).

`tests/fixtures/checklist-dev-make/should-pass/Makefile` guards this: it
declares a bodyless target on the second `.PHONY` line, so rewriting those two
lines as a continuation makes the test suite fail.

### `checkmake.ini` is not optional in practice

checkmake reads `checkmake.ini` from the directory it runs in, which under
pre-commit is always the repo root. `scripts/install.sh` copies
[`templates/checkmake.ini`](../templates/checkmake.ini) in, and this
repository dogfoods the same file.

Without it you get checkmake's own defaults, and two of its five rules are
project conventions rather than correctness checks:

- `maxbodylength` caps target bodies at 5 lines. A single `docker run` with
  its flags on separate lines already exceeds that, so on a real Makefile this
  rule fires on nearly every target. Two separate knobs: `maxBodyLength` only
  raises the cap and cannot switch the rule off, while `disabled = true` can
  (see below). The shipped config raises the cap to 70 and leaves the rule
  enabled, so a genuinely runaway recipe still gets caught.
- `minphony` requires `all`, `clean` **and** `test` to be declared phony in
  every Makefile it is handed, sub-Makefiles included. The shipped config
  reduces that to `all`. Setting `required =` to the empty string disables the
  rule outright, which checkmake special cases rather than reading as an empty
  list.

The other three rules are left at full strength on purpose. `phonydeclared`
catches a bodyless target that a same named file in the working tree would
make `make` consider up to date and skip. `uniquetargets` catches a target
defined twice, where one recipe silently overrides the other.
`timestampexpanded` catches a recursively expanded timestamp that produces a
different value on every reference.

### Two false positive shapes that have no workaround

A colon inside a `define`/`endef` block, and a colon inside a top level
`$(error)`, `$(info)` or `$(warning)`, are both parsed as rule targets:

```makefile
define help_text
Usage:
  make all
endef

$(info Building with: $(CC))
```

reports `Usage` and `$(info Building with` as targets that should be declared
PHONY. These are
[checkmake#244](https://github.com/checkmake/checkmake/issues/244) (fix open
as [checkmake#254](https://github.com/checkmake/checkmake/pull/254)) and
[checkmake#284](https://github.com/checkmake/checkmake/issues/284).

No targeted escape hatch exists for either. What checkmake does and does not
let you switch off is worth stating precisely, because an earlier version of
this page got it wrong.

`phonydeclared` indexes `.PHONY` dependencies by name, so `.PHONY: Usage`
suppresses a phantom target whose text before the colon is a single word. But
`.PHONY` splits on whitespace, so a phantom named `You can also use` cannot be
written down at all. Half the findings in one `define` block can be silenced
and half cannot, which is more confusing than none of them being
suppressible at all.

There is no line level or block level ignore
([checkmake#31](https://github.com/checkmake/checkmake/issues/31),
[checkmake#285](https://github.com/checkmake/checkmake/issues/285)), so a
single false finding cannot be waived where it sits.

If a repository hits either shape, the options are to remove the colons from
the affected text, to switch the rule off for that repository with
`disabled` (below), or to leave the repository off this id until the upstream
fixes land. Do not reach for a repo wide `exclude:` on the Makefile: that
turns the whole checklist off while looking like it is on.

### Turning a rule off, and scoping it to some files

A whole rule can be disabled, and this page previously said otherwise. Any
rule section accepts `disabled`, which `validator.go` checks before running
the rule:

```ini
[phonydeclared]
disabled = true
```

It works on every rule and is documented nowhere upstream: `checkmake.1`'s
CONFIGURATION section lists only `default.format`,
`maxbodylength.maxBodyLength` and `minphony.required`. Three further keys are
real, `default.output`, `<rule>.disabled` and `uniquetargets.ignore` (a comma
separated list of target names for that rule to skip). See
[checkmake#82](https://github.com/checkmake/checkmake/issues/82) for the
full list.

Treat `disabled` as a last resort rather than a tuning knob. It is all or
nothing across the run, and the three rules worth keeping are exactly the
ones you would reach for it on.

checkmake itself cannot scope a rule to a subset of files
([checkmake#285](https://github.com/checkmake/checkmake/issues/285)), but
pre-commit can, by running the hook twice against different configs:

```yaml
- id: checkmake
  name: checkmake (strict)
  exclude: ^legacy/
- id: checkmake
  alias: checkmake-legacy
  files: ^legacy/
  args: ["--config", "checkmake.legacy.ini"]
```

Confirmed discriminating rather than a false pass: a `legacy/Makefile` with a
bodyless undeclared target reports one `phonydeclared` violation under the
strict config and none under the scoped one. This only helps consumers going
through pre-commit; anyone running `checkmake` from a Makefile target or CI
step directly gets nothing from it, and one logical configuration now lives
in two files that have to be kept in step.

## Zizmor: offline by default

`checklist-github-actions` runs [zizmor](https://docs.zizmor.sh/) alongside
actionlint. actionlint checks workflow syntax and semantics; zizmor checks
workflow *security*: credential persistence through `actions/checkout`
(`artipacked`), template injection through untrusted input reaching a
shell or script step (`template-injection`), overly broad permissions
(`excessive-permissions`), unpinned action references (`unpinned-uses`),
and several more, listed at
[docs.zizmor.sh/audits](https://docs.zizmor.sh/audits/). Confirmed
directly: actionlint's own "expression" rule already catches the
narrower case of a known untrusted GitHub context value
(`github.event.pull_request.title` and similar) interpolated straight
into a `run:` or `script:` block, so the two tools overlap there; they do
not overlap on credential persistence, permissions, or unpinned
references, none of which actionlint checks at all.

zizmor has no first party `.pre-commit-hooks.yaml` of its own (a plain
request for one against its GitHub repository returns 404), so this is a
`repo: local` hook, `language: python`, pinned via
`additional_dependencies: ["zizmor==1.29.0"]` rather than a `repo:` +
`rev:` entry. See [`docs/versioning.md`](versioning.md) for what that
means for how this pin moves.

**zizmor 1.29.0 needs Python 3.10 or newer; neither hook definition sets
`language_version`, on purpose.** PyPI reports `requires_python: >=3.10`
for this pin, but that floor is a fact about zizmor, not something a
`language: python` hook enforces on its own, so it is documented here,
in `README.md`, and in `tests/README.md` instead. Setting
`language_version: python3.10` looks like the obvious way to encode that
floor and was tried directly: confirmed on a machine whose only
interpreter is Python 3.14 and has no `python3.10` on `PATH` at all, that
setting makes pre-commit try to build the hook's virtualenv with
`python3.10` specifically, `-mvirtualenv` fails outright with
`RuntimeError: failed to find interpreter for Builtin discover of
python_spec='python3.10'`, and the hook never runs, pre-commit exits 3
before zizmor gets a chance to see a single file. `language_version`
selects one exact interpreter; it is not a minimum version check, so it
turns "works on 3.10 and any newer Python" into "works on exactly 3.10",
breaking every consumer already fine on 3.11 through 3.14 to guard
against the one who is not. `language_version: python3` was also tried,
confirmed to behave identically to leaving the key out entirely (both
resolve to whichever `python3` is already running `pre-commit` itself),
so it buys nothing beyond what omitting the key already does.
`minimum_pre_commit_version` does not help either: confirmed against
pre-commit's own source, that key gates the version of the `pre-commit`
tool itself, not the Python interpreter its hooks run under, so it
cannot express this requirement at all. Leaving `language_version`
unset is what actually keeps this hook working across 3.10 and up; a
consumer whose ambient `python3` predates 3.10 gets a clear failure
straight from pip's own resolver at install time (`Ignored the following
versions that require a different python version: ... 1.29.0
Requires-Python >=3.10`, confirmed directly against PyPI), not a
mysterious one, which is what documenting the floor here is for.

**The hook runs `zizmor --no-online-audits` rather than plain `zizmor`,
by design.** Without that flag, zizmor auto detects any
`GH_TOKEN`/`GITHUB_TOKEN`/`ZIZMOR_GITHUB_TOKEN` in the calling
environment and, if one is present, attempts online audits (chiefly
`impostor-commit`, which needs the GitHub API to confirm a pinned commit
SHA actually belongs to the repository it claims to) that need real,
working GitHub API access. Confirmed directly: with no token set at all,
zizmor limits itself to the offline audit set and exits normally; with a
token set that the GitHub API rejects (wrong scope, expired, or simply
not a real token, which an ordinary consumer CI job cannot always
guarantee about whatever token happens to already be in its
environment), the run instead aborts outright with `fatal: no audit was
performed` and an HTTP 401 from the GitHub API, exit status 1, zero
findings reported rather than a partial result. That failure mode has
nothing to do with the workflow content being checked, so this checklist
does not leave it to chance: `--no-online-audits` is baked into the
hook's own `entry:`, and the result depends only on the files it is
given, never on whether some ambient token happens to be valid on a
given run.

This means the audits that need connectivity, `impostor-commit` in
particular, do not run through this checklist id at all. A consumer who
wants them, and has a real token to spend on the extra GitHub API calls,
can override the hook in their own `.pre-commit-config.yaml` with
`entry: zizmor` (no flag) and a working `GH_TOKEN` exported in the
environment `pre-commit` runs in; see
[`docs/overrides.md`](overrides.md) for how a hook level override like
that works.

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
