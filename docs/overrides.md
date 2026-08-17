# Overrides

Use these sparingly, and prefer fixing the underlying finding. An
override hides one specific case; a habit of overriding hides a pattern.

## Skip a hook entirely, for one commit

```shell
SKIP=checklist-spell git commit -m "fix: typo in a string cspell won't parse"
```

Comma-separate multiple ids: `SKIP=checklist-spell,checklist-markdown`.

## Keeping the validator, dropping the formatter or network check

`checklist-json` and `checklist-yaml` bundle a formatter (Prettier)
alongside a plain syntax check; `checklist-markdown` bundles a link
checker (`markdown-link-check`) that needs network access alongside a
lint-only tool (`markdownlint-cli2`). Neither is a knob you set in your
own `.pre-commit-config.yaml`, but `SKIP` reaches inside a checklist the
same way it reaches a checklist id: `scripts/run-checklist.sh` starts
its nested `pre-commit run` as a subprocess, and `SKIP` is an
environment variable that subprocess inherits like any other, so naming
the *inner* hook id skips just that tool, not the whole checklist:

```shell
# Keep check-json, skip the Prettier reformat
SKIP=prettier-json git commit -m "chore: commit a generated JSON export as-is"

# Keep check-yaml (and, optionally, yamllint), skip the Prettier reformat
SKIP=prettier-yaml git commit -m "chore: commit a generated YAML export as-is"

# Keep markdownlint-cli2, skip the network-dependent link check
SKIP=markdown-link-check git commit -m "docs: edit without a network connection"
```

Verified directly, through the full outer-hook-then-nested-run path
(not just the inner config file in isolation): with
`SKIP=prettier-json` set, `pre-commit run checklist-json` on a validly
formatted-but-not-Prettier-canonical JSON file still runs `check-json`
(passes) and reports `prettier-json` as `Skipped` rather than
reformatting the file, where the same run with no `SKIP` set reformats
it and reports the hook `Failed` (files were modified). The same holds
for `SKIP=markdown-link-check` against a Markdown file with an
unreachable link: `markdownlint-cli2` still runs, `markdown-link-check`
is skipped rather than attempted.

This is a per-commit (or, exported in a shell profile or a CI job's
environment, a standing) override, not a config-file setting: there is
no persistent, no-argument way to make `checklist-yaml` mean "just
check-yaml and yamllint" from your own `.pre-commit-config.yaml` today.
See [`docs/hook-catalogue.md`](hook-catalogue.md#adopting-part-of-a-bundled-checklist)
for the other options considered for that gap and why this is the one
implemented so far.

## Skip a hook entirely, for a repo

Delete its entry from your `.pre-commit-config.yaml`. There is no
config-file equivalent of `SKIP`: pre-commit only reads the hooks you
listed, so removing one is the permanent version of skipping it.

## Exclude specific files or paths from a hook

Add `exclude:` to the hook entry in your own `.pre-commit-config.yaml`
(this is a pre-commit feature, available on every hook id regardless of
what the hook itself does):

```yaml
- id: checklist-spell
  exclude: ^(CHANGELOG\.md|vendor/)
```

## Ticket prefixes in branch names and commit messages

`checklist-git-valid-branches` and `checklist-git-commit-msg` accept
plain names by default (`add-login-page`,
`feat: add login page`). To require a ticket id instead, pass
`--ticket-prefixes` as an `args:` override in your own config:

```yaml
- id: checklist-git-valid-branches
  args: ["--ticket-prefixes", "PROJ ACME"]
  pass_filenames: false
  always_run: true

- id: checklist-git-commit-msg
  args: ["--ticket-prefixes", "PROJ ACME"]
  stages: [commit-msg]
  files: ^\.git/COMMIT_EDITMSG$
```

With that, branches must look like `proj-123-add-login-page` and commits
like `feat(PROJ-123): add login page`. Run either script with `--help`
for the exact grammar
([`scripts/check-branch-name.sh`](../scripts/check-branch-name.sh),
[`scripts/check-commit-msg.sh`](../scripts/check-commit-msg.sh)).

The two ids above are the only ones this works on, because their
`entry:` in [`.pre-commit-hooks.yaml`](../.pre-commit-hooks.yaml) calls
one of those scripts directly, and pre-commit hands your `args:`
straight to that `entry:`. Read on before reaching for `args:` on any
other checklist id by analogy with this example.

## Do not put args: on a checklist-* id that routes through run-checklist.sh

Every checklist id except `checklist-git-valid-branches` and
`checklist-git-commit-msg` has `entry: ./scripts/run-checklist.sh` and a
baked-in `args:` of exactly one string: the checklist name, e.g.
`args: [checklist-json]` for `checklist-json`. pre-commit does not merge
a hook's own `args:` from your `.pre-commit-config.yaml` with the ones
already baked into `.pre-commit-hooks.yaml`; yours replace them
entirely. Add your own `args:` to one of these ids and
`run-checklist.sh` receives that instead of the checklist name it needs
to find its config file, and fails:

```yaml
# Don't do this. checklist-json's baked-in args: [checklist-json] is
# gone the moment you set your own args: here.
- id: checklist-json
  args: ["--some-flag"]
```

`run-checklist.sh` fails loudly when this happens (checklist not found,
with a pointer back to this section), rather than silently mis-behaving,
but the fix is still to not do it. If you need to pass a flag to the
tool a checklist id wraps, that checklist id cannot take it from your
config at all, baked-in `args:` or not: add the upstream hook directly
in your own `.pre-commit-config.yaml` instead of going through the
checklist id, the same way the [ticket prefix example](#ticket-prefixes-in-branch-names-and-commit-messages)
above works, because those two ids are the exception that call a script
directly rather than dispatching through `run-checklist.sh`. See
[Changing the protected branches pattern](#changing-the-protected-branches-pattern)
below for a worked example of adding an upstream hook directly, and
[`docs/hook-catalogue.md`](hook-catalogue.md#which-dotenv-linter) for
another. [Passing a flag to the tool a checklist wraps](#passing-a-flag-to-the-tool-a-checklist-wraps)
below has the investigation behind why no config-only override for this
exists, rather than only asserting it does not.

## Changing the protected branches pattern

`checklist-git-protected-branches` runs `no-commit-to-branch` with
`args: ["--pattern", "(?i)(develop|staging|main|master)"]` baked into
[`checklists/checklist-git-protected-branches.yaml`](../checklists/checklist-git-protected-branches.yaml).
Like every other checklist id except the two named above, it routes
through `run-checklist.sh`, so the `args:` override shown in the
previous section is not available here either: forking the checklist
file is one way to change the pattern (and the one
`templates/pre-commit-config/recommended.yaml` mentions first), but it
is not the only one. The config-only alternative is to drop
`checklist-git-protected-branches` from your hook list and add
`no-commit-to-branch` yourself, pointed at its own upstream repo, with
whatever `--branch` and `--pattern` you want:

```yaml
- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: v6.0.0 # match, or move independently of, this library's own pin
  hooks:
    - id: no-commit-to-branch
      args: ["--branch", "trunk", "--pattern", "(?i)release/.*"]
      pass_filenames: false
      always_run: true
```

One behavior of the upstream tool itself is easy to miss here:
`--branch` and `--pattern` are not alternatives, and `--pattern` alone
does not replace anything. `no-commit-to-branch` protects `master` and
`main` by default *only when `--branch` is absent*; passing `--pattern`
without `--branch` adds your pattern on top of that default rather than
replacing it. `checklist-git-protected-branches` relies on exactly this:
it passes `--pattern` only, so `develop`/`staging`/`main`/`master`
(case-insensitively) are all protected, `main`/`master` twice over, once
by the upstream default and once by the pattern. If your repo's
long-lived branch is not named `main` or `master` at all, pass
`--branch` explicitly (as above) or the hardcoded default keeps
protecting a branch name your repo does not use, alongside whatever you
intended. Verified directly: with `--branch trunk --pattern
(?i)release/.*` and no other configuration, a commit to `trunk` is
blocked, a commit to `main` is not, and a commit to `release/1.0` is
blocked.

## Passing a flag to the tool a checklist wraps

Every `checklist-*` id's baked-in `args:` is one string, the checklist
name `run-checklist.sh` needs (see above). There is no way to add a
flag on top of that from a consumer's own `.pre-commit-config.yaml`,
for any `checklist-*` id, on any release of this library so far. That
gap was investigated before writing this section, not assumed, and
three separate facts about pre-commit itself close it off:

- A nested `pre-commit run --config <checklist>.yaml` invocation, the
  shape every `checklist-*` id runs, cannot have one hook's `args:`
  influenced at runtime through its own command line. `pre-commit run`
  takes exactly one optional positional argument, a hook id that
  restricts which hook in the config runs, not arguments to hand that
  hook; there is no `--` passthrough and no flag anywhere in it that
  injects extra args into a specific hook's tool invocation. Confirmed
  by reading pre-commit 4.5.1's own argument parser
  (`pre_commit/main.py`, `_add_run_options`): the full, closed list of
  flags `run` accepts is `--verbose`, `--all-files`/`--files`,
  `--show-diff-on-failure`, `--fail-fast`, `--hook-stage`, and a set of
  git ref/branch flags for stages other than `pre-commit` itself
  (`commit-msg`, `pre-push`, and so on). None of them touch a hook's
  own `args:`.
- pre-commit does not interpolate environment variables, or anything
  else, into a `.pre-commit-config.yaml` (or a checklist file here,
  which is the same format) when it loads one. A config file is parsed
  with a plain YAML safe loader and nothing else; a `${SOME_VAR}` sitting
  in a checklist's `args:` list would reach the tool as that literal
  text, unexpanded, not a substituted value. Confirmed by reading
  pre-commit 4.5.1's own config loader (`pre_commit/yaml.py`,
  `pre_commit/clientlib.py`): neither references `os.environ`, or any
  templating step, at all.
- Even on a hook id that does not route through `run-checklist.sh`, a
  consumer's own `args:` on that hook entry fully replaces the
  manifest's baked-in `args:` rather than merging with it (this is the
  entire reason the [earlier warning](#do-not-put-args-on-a-checklist--id-that-routes-through-run-checklistsh)
  on this page exists). Confirmed by reading pre-commit 4.5.1's own
  hook-merge code (`pre_commit/repository.py`, the `_hook()` function):
  it is a plain dict update, one key at a time, last value wins, no
  list ever gets concatenated with another. A `--` separator convention,
  for example `args: [checklist-dev-shell, --, --severity=warning]`,
  would not get any help from pre-commit here either; something would
  still have to read the tail after `--` and act on it, and the only
  place free to do that is `run-checklist.sh` itself, generating a
  different checklist file than the one reviewed and tagged in this
  repository, on every commit, for every consumer who sets the
  convention.

That last option, generating an overridden checklist file on the fly,
was considered and rejected, not overlooked. Doing it safely needs a
YAML-aware rewrite step, a dependency `run-checklist.sh` does not
otherwise carry, because a text level substitution against arbitrary
YAML (the only kind of rewrite a plain shell script can do without that
new dependency) is exactly how a malformed override turns into invalid
YAML that breaks every hook in the checklist, not just the one flag it
targeted. And even done correctly, the config that actually ran that
commit is a transient file nobody reviewed or committed, which fights
[`docs/versioning.md`](versioning.md)'s entire contract that a
checklist's `args:` only change when this repository itself cuts a
release. `SKIP` already covers the "drop this tool entirely" half of
this need (see above) with none of that cost, because it is
pre-commit's own environment variable, read by its own nested run, not
a mechanism this repository invented. The "change a flag on this tool"
half has no equivalent, and does not get one here: the supported path
is the one the [ticket prefix](#ticket-prefixes-in-branch-names-and-commit-messages)
and [protected branches](#changing-the-protected-branches-pattern)
examples above already use, add the upstream hook (or, like
`checklist-dev-dotenv`, a `repo: local` entry that shells out directly)
yourself, pointed at whatever the checklist wraps, with the flag you
need. See [`docs/hook-catalogue.md`](hook-catalogue.md#which-dotenv-linter)
for a concrete, verified worked example doing exactly that.

## Allowlisting one secret finding (detect-secrets)

Inline, on the offending line:

```yaml
secret = "hunter2"  # pragma: allowlist secret
```

```js
// pragma: allowlist nextline secret
const secret = "hunter2";
```

Or regenerate the baseline after confirming the finding is a false
positive, so it's recorded as reviewed rather than silenced inline:

```shell
detect-secrets scan --baseline .secrets.baseline
detect-secrets audit .secrets.baseline
```

More at the
[detect-secrets README](https://github.com/Yelp/detect-secrets#inline-allowlisting).

## Ignoring a link (lychee / markdown-link-check)

`checklist-markdown` runs `markdown-link-check`, which reads
`.markdown-link-check.json` if present. See its
[own docs](https://github.com/tcort/markdown-link-check#config-file-format)
for the ignore-pattern format.

If you separately run [lychee](https://lychee.cli.rs/) (not part of any
checklist here, but `templates/.lycheeignore` ships a starter for it),
add a regex per line to `.lycheeignore`:

```shell
^https?://internal-only-host(:[0-9]+)?(/.*)?$
```

See the [lychee recipe](https://lychee.cli.rs/recipes/excluding-links/)
for the full pattern syntax.

## Ignoring a word (cspell)

Add it to `.cspell.json`, in `words` if it's a real word your project
uses often, or `ignoreWords` if it's a one-off identifier that
shouldn't be suggested as a fix either:

```json
{
  "words": ["myproject"],
  "ignoreWords": ["xkcd"]
}
```

## Ignoring one line (yamllint / markdownlint)

```yaml
# yamllint disable-line rule:line-length
a_very_long_key: "a value that would otherwise trip the line-length rule"
```

```markdown
<!-- markdownlint-disable-next-line MD013 -->
A very long line that would otherwise trip the line-length rule.
```

## MegaLinter-specific overrides

MegaLinter does not have one inline-ignore syntax of its own: it runs
dozens of underlying linters, and each keeps its own convention for
ignoring one finding. For a linter this library also wraps directly
(yamllint, markdownlint, cspell, detect-secrets), the sections above
apply unchanged, MegaLinter is invoking the same binary. For any other
linter MegaLinter enables, check that linter's own documentation, linked
from [MegaLinter's descriptor list](https://megalinter.io/latest/config-file/).

What is repo-wide, not per-linter or per-line, is `DISABLE`/`DISABLE_LINTERS`
in `.mega-linter.yml`, which turns a whole descriptor or linter off
entirely rather than ignoring one finding. See
[`docs/megalinter.md`](megalinter.md) for that file and how MegaLinter
itself is run.
