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
config-file equivalent of `SKIP` — pre-commit only reads the hooks you
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
`.markdown-link-check.json` if present — see its
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
