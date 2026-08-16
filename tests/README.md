# Tests

Self-tests for this library own checklists, hook wiring, and shell
scripts. Nothing here consumes the library the way `templates/` teaches a
real consumer to; instead it runs the checklists directly and, for the
consumer-path and real-commit phases, builds throwaway repos under `/tmp`
that consume a tagged local clone the way a real user eventually will.

## Run everything

```shell
tests/run_tests.sh
```

Exit 0 if every phase passed, exit 1 otherwise. This is the one command a
CI workflow should call; see "Wiring into CI" below.

Run a subset by naming phases:

```shell
tests/run_tests.sh hooks shell
```

## Phases

| Phase | Script | What it checks |
| --- | --- | --- |
| `selectors` | `tests/scripts/selector_lint.py` | Static: no hook definition in `.pre-commit-hooks.yaml`, `checklists/*.yaml`, or `templates/pre-commit-config/*.yaml` combines `types:`/`types_or:` with `files:` on the same entry. pre-commit ANDs those keys; combining them is exactly how defects 2 and 3 happened. |
| `hooks` | `tests/scripts/check_hooks.sh` | Per checklist: a `should-pass` fixture set exits 0, a `should-fail` fixture set exits nonzero, and, critically, the hook is not silently skipped for matching zero files ("(no files to check)"). Also re-runs each `should-pass` set through the real dogfood `.pre-commit-config.yaml` by hook id, asserting the file-based selector wiring there still selects the fixture. |
| `shell` | `tests/scripts/lint_shell.sh` | `shellcheck --severity=warning` over `scripts/*.sh`, plus behavioral tests of `check-branch-name.sh`, `check-commit-msg.sh` (including the opt-in `--ticket-prefixes` path for both), `run-checklist.sh`, and `install.sh` against their documented exit codes. |
| `consumer` | `tests/scripts/consumer_path.sh` | The `repo: <url>` + `rev: vX.Y.Z` consumer path, offline. See below. |
| `commit` | `tests/scripts/real_commit.sh` | A real `git commit` through installed hooks, covering the `commit-msg` stage. |

## Why "selected the file" matters as much as the exit code

Defects 2 and 3 both had the same shape: a hook wired with a selector
that matched zero files still reports success, because pre-commit exits 0
when a hook has nothing to check. A test that only asserts "the overall
`pre-commit run` exit code" would have passed against both bugs. Every
fixture-based assertion in `check_hooks.sh` additionally inspects the
verbose output and fails if the hook (or every sub-hook of a checklist)
reported `(no files to check)` when a fixture was actually handed to it.

This was verified directly: `checklists/checklist-dev-python.yaml`'s
selector in `.pre-commit-config.yaml` was hand-edited on a scratch copy of
that file to reintroduce defect 3 (`types_or: [python]` combined with
`files: ^requirements\.txt$`), the suite was pointed at the mutated copy,
and `tests/scripts/check_hooks.sh` went red with exactly this failure:

```text
FAIL: checklist-dev-python/dogfood-wiring: every hook reported (no files to check);
      the selector did not match the fixture, this is the defect-2/3 shape
```

The same was repeated for defect 2 (`checklist-dev-dotenv` wired to
`types: [json]`). Both reverted cleanly; the real `.pre-commit-config.yaml`
in this repo was never modified by that exercise (it lives outside
`tests/`, which is this sprint own scope).

## The consumer path: what it proves and what it does not

`tests/scripts/consumer_path.sh` and `tests/scripts/real_commit.sh` clone
this repo (a plain, read-only `git clone`, never writing back into the
original) into a throwaway directory under `/tmp`, tag *that clone* with a
throwaway tag, and point a second throwaway consumer repo own
`.pre-commit-config.yaml` at it with `repo: <clone path>` and
`rev: <that tag>`, the same shape `templates/pre-commit-config/*.yaml`
teach (`repo: https://github.com/ivan-pinatti/pre-commit-checklists`,
`rev: vX.Y.Z`), except the URL is a local path instead of GitHub. Neither
script writes a tag into this repo itself; tags do not travel backwards
through a clone.

**What this proves:**

- `.pre-commit-hooks.yaml` entry paths (`entry: ./scripts/run-checklist.sh`)
  resolve correctly when pre-commit clones the repo into its own hook
  cache at a pinned rev, rather than running from a checkout that already
  happens to be the working directory. This is exactly what `repo: local`
  (the dogfood config) and a same-directory `repo: ./` never exercise.
- A consumer config written the way the shipped templates instruct
  (`repo:` + `rev:`, hook ids selected by name, selectors applied by hand
  per `docs/hook-catalogue.md`) finds those hook ids in the cloned
  `.pre-commit-hooks.yaml` and runs them successfully.
- `real_commit.sh` additionally proves a real `git commit` through that
  same `repo:`+`rev:` config is blocked at the `commit-msg` stage by a
  non-conventional message, and that the blocked commit does not land.

**What this does NOT prove:**

- That `https://github.com/ivan-pinatti/pre-commit-checklists` is
  reachable, authenticates correctly, or serves the same content pre-commit
  would clone. The repository is not published yet (see the plan, Sprint
  6); nothing here touches the network for this repo specifically.
- Anything about GitHub release mechanics, tag signing, or the
  `gh repo create` / push flow.
- Real-network behavior (interrupted clones, auth prompts, rate limits).
  The clone target is a local path; pre-commit treats it like any other
  git remote, but no packets for it leave this machine.

This gate should be re-run once the repo is public, against the real URL,
before treating the consumer path as fully proven.

## Known gaps this sprint found but did not fix

Out of scope for `tests/` to fix directly (the owning files sit outside
this sprint scope); reported here for a follow-up.

1. **`shfmt` in `checklist-dev-shell.yaml` is a no-op formatter check.**
   The checklist overrides shfmt args to `["--indent", "2"]`. Consumer
   `args:` fully replace a hook manifest own default args rather than
   merging with them, and the upstream `pre-commit-shfmt` hook default is
   `[--write]`. With neither `--write`/`-w` nor `--diff`/`-d` present,
   `shfmt` prints reformatted output to stdout and always exits 0;
   `tests/fixtures/checklist-dev-shell/should-fail/greet.sh` intentionally
   uses a shellcheck-severity-error bug (`local` outside a function)
   rather than a formatting bug, precisely because a formatting-only bug
   would not fail this hook at all. Confirmed live: shfmt reported
   `Passed` against a should-fail fixture with clearly wrong indentation.
   A fix would add `-d` (or restore `--write`) to `checklists/checklist-dev-shell.yaml`,
   which is outside `tests/`.
2. **No root `.editorconfig` in this repo.** `checklist-dev-editorconfig`
   is wired into the dogfood `.pre-commit-config.yaml`, but with no
   `.editorconfig` anywhere above a checked file, `editorconfig-checker`
   has no rules to apply and passes trivially. `docs/hook-catalogue.md`
   says this hook "Requires: `.editorconfig` at repo root", which is not
   currently true of how this repo dogfoods itself.
   `tests/fixtures/checklist-dev-editorconfig/.editorconfig` works around
   this for the fixture tests only, by relying on EditorConfig own
   directory-walk-up behavior (confirmed empirically); it does not fix
   the gap in the real repo.
3. **`checklist-github-actions` dogfood-wiring is untestable right now.**
   `actionlint-docker` own hook manifest anchors `files:` to
   `^\.github/workflows/` at the repo root (not overridable from a
   fixture path under `tests/`), and this repo has no
   `.github/workflows/` yet (owned by a different, not-yet-run part of
   the build). `check_hooks.sh` tests this hook own behavior via
   `tests/config/checklist-github-actions.override.yaml` (a test-only
   config that points the same pinned `actionlint-docker` hook at any
   YAML file) but skips the dogfood-wiring assertion for it. Re-check
   this hook specific wiring once `.github/workflows/*.yml` exists.
4. **The dogfood `.pre-commit-config.yaml` has no `exclude:` for
   `tests/fixtures/`, so `pre-commit run --all-files` at the repo root
   now also fails against the `should-fail` fixtures themselves.**
   Every dogfood hook that matches by file type (or matches everything,
   like `checklist-basic` and `checklist-security-credentials`) has no
   path-based exclusion, so a full repo sweep correctly, if noisily,
   reports the intentionally bad content in
   `tests/fixtures/*/should-fail/*` as real failures: invalid TOML/JSON/
   XML/YAML, a merge-conflict marker, a fake private key, a leftover
   `pdb` import, and so on. This was confirmed by running
   `pre-commit run --config .pre-commit-config.yaml --all-files
   --hook-stage pre-commit` after adding the fixtures: roughly a dozen
   checklists newly report a `Failed` line, on top of the two
   pre-existing, already-documented exceptions (`markdown-link-check`
   and the protected-branches hook on `main`). There is no way to avoid
   this from inside `tests/`: pre-commit only supports excluding paths
   via a hook-level or top-level `exclude:` key in `.pre-commit-config.yaml`
   itself, and that file sits outside this sprint own scope. The fix is
   a single line at the top of that file, `exclude: ^tests/fixtures/`
   (or narrower, `^tests/fixtures/.*/should-fail/`), which is a one-line,
   low-risk change for whoever owns that file next. Until that lands,
   expect `pre-commit run --all-files` at the repo root to be red for
   this reason in addition to the two already-known ones; `tests/run_tests.sh`
   itself is unaffected, since every phase targets specific checklist
   files or fixture paths directly rather than sweeping the whole repo.

None of these are things `tests/` is scoped to fix; `checklists/`,
`docs/`, and `.github/` belong to other parts of this build.

## Fixture design notes

- **Fixtures must be git-tracked before a "fixer" hook run is meaningful.**
  pre-commit detects "files were modified by this hook" (prettier,
  `ruff-format`, `end-of-file-fixer`, `requirements-txt-fixer`, ...) by
  diffing against the git index, not just by running the tool. Every
  fixture here is committed, which satisfies this; an uncommitted file
  passed straight to `pre-commit run --files` would not trigger the
  "modified" detection correctly, understating should-fail cases.
- **`check_hooks.sh` restores fixtures after every run.** Fixer hooks
  rewrite should-fail fixtures in place on their first (correctly-failing)
  run; without a restore step, a second run of the suite against the same
  working tree would find the file already fixed and silently start
  passing. `restore_fixtures()` in `tests/lib/harness.sh` runs
  `git checkout --` on every fixture file after each hook invocation, pass
  or fail, so the suite is idempotent across repeated runs. Verified by
  running `tests/scripts/check_hooks.sh` twice in a row with an identical
  result both times.
- **`.env` fixtures need `git add -f`.** The repo `.gitignore` ignores
  `.env`/`.env.local`, which is correct hygiene for a real consumer but
  means `tests/fixtures/checklist-dev-dotenv/**/.env` needed a forced add
  to get committed at all.
- **Fixtures must live inside this git repository.** `check-shebang-scripts-are-executable`
  and a few other `pre-commit-hooks` checks call `git ls-files` on the
  paths they are given; a fixture living outside the repo tree (e.g. a
  bare `/tmp` path) makes that `git ls-files` call fail outright rather
  than report a clean result. Every fixture here lives under
  `tests/fixtures/`, inside the repo.
- **Prettier fixtures must already be in Prettier own canonical form.**
  A `should-pass` JSON/YAML/JS/TS fixture that is valid but not already
  formatted exactly the way Prettier would write it counts as a failure
  ("files were modified by this hook"), not a pass. Every `should-pass`
  fixture that Prettier touches was verified to come back `(unchanged)`.
- **`name-tests-test --django` matches on path, not just filename.**
  Its hook manifest selector is `files: (^|/)tests/.+\.py$`, since this
  whole suite lives under a top-level `tests/` directory, any `.py`
  fixture here is automatically in scope for that hook, regardless of
  what `checklist-dev-python.yaml` itself does. The Python fixtures are
  named `test_sample.py` to satisfy it, matching how a real consumer
  `tests/` directory would look.
- **`checklist-github-actions` needs `tests/config/checklist-github-actions.override.yaml`.**
  See "Known gaps" above; this override file exists solely so the hook
  own real behavior (does it actually lint the workflow file content) can
  be tested from a fixture path outside `.github/workflows/`.

## What each phase needs installed

- `selectors`: Python 3 with PyYAML.
- `hooks`: `pre-commit`, network access (hook environments are built and
  cached on first use), Docker (for `actionlint-docker`), Node/npm (for
  the Prettier-based checklists), and a Terraform + `tflint` toolchain
  (for `checklist-dev-terraform`).
- `shell`: `shellcheck`, `git`, `pre-commit`, `detect-secrets`.
- `consumer` / `commit`: `git`, `pre-commit`, and everything `hooks` needs
  (the throwaway consumer repos exercise the same checklists).

All of the above were available in the environment this suite was
developed and verified against; `tests/run_tests.sh` does not attempt to
detect or skip missing tools; a missing tool surfaces as a failed
assertion with the tool own error in the failure detail.

## Wiring into CI

This sprint does not touch `.github/workflows/` (owned by a different,
not-yet-run part of the build). The command a workflow should call is:

```shell
tests/run_tests.sh
```

Exit 0 means every phase passed; nonzero means at least one did. The
script needs the tool versions in `.tool-versions` available (or
`pre-commit` resolvable some other way), Docker for the GitHub Actions
checklist test, and network access for pre-commit to build hook
environments and for the actionlint Docker image pull.
