# Overrides

Use these sparingly, and prefer fixing the underlying finding. An
override hides one specific case; a habit of overriding hides a pattern.

## Skip a hook entirely, for one commit

```shell
SKIP=checklist-spell git commit -m "fix: typo in a string cspell won't parse"
```

Comma-separate multiple ids: `SKIP=checklist-spell,checklist-markdown`.

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
another.

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

MegaLinter wraps its own set of linters and has its own inline-ignore
conventions per linter, plus repo-wide `DISABLE`/`DISABLE_LINTERS` keys
in `.mega-linter.yml`. See [`docs/megalinter.md`](megalinter.md).
