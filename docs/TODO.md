# TODO

<!-- cspell:words hostnames repoint repoints unsets -->

Known defects and follow-ups in this library, with the evidence for each.
Nothing here is urgent enough to block a release; all of it is worth fixing.

## 1. `templates/.markdown-link-check.json` teaches the wrong default

**Status:** DONE in v2.2.1. The stargazers entry was removed before
[#12](https://github.com/ivan-pinatti/pre-commit-checklists/pull/12) merged,
and the file's header now states what the file is for and that a stars badge
does not qualify. Kept here for the reasoning, which is the rule to apply to
any future ignore entry.

That template ships an `ignorePatterns` entry for GitHub's `/stargazers`
route, so a consumer adopting it silences their own star badge link without
being asked.

**Why it is wrong:** the point of a link checker is to check links. A config
entry that quietly skips one is a worse outcome than a badge pointing
somewhere that actually resolves, and shipping it as a default teaches every
consumer that habit on day one.

**What to do instead:** drop that one entry, and replace it with a comment
saying the honest fix is to repoint the badge at the repository itself. Keep
the other two entries: the GitHub API rate-limit pattern and the in-cluster
Kubernetes hostnames are whole classes of URL that genuinely cannot be
resolved from CI, which is a different thing from one fixable link.

**Evidence, so nobody re-derives it:** GitHub answers 404 on `/stargazers`
and `/watchers` for every client without a logged-in browser session. Plain
`curl`, a browser user agent, a full set of `Sec-Fetch-*` navigation headers,
and an authenticated `Authorization: Bearer` token all get the same
plain-text `Not Found` rather than GitHub's HTML 404 page. `/forks`,
`/issues`, `/pulse` and `/network/members` all return 200, so this is those
two routes specifically.

It is **not** about star count. That was an early wrong reading: a repository
with thousands of stars 404s identically, and starring a zero-star repository
changes nothing.

Worked example of the fix: `ivan-pinatti/rsync-crypt` repoints its stars
badge at the repository root. The count is unaffected, because it comes from
the `img.shields.io` image URL, not the link target.

## 2. `checklist-yaml`'s two hooks contradict each other

**Status:** open. Affects every consumer of `checklist-yaml`.

`templates/.yamllint.yml` extends yamllint's `default` rule set, whose
`comments` rule requires two spaces before an inline `#`. The same checklist
also runs Prettier over every YAML file, and Prettier normalizes that to
exactly one space.

So Prettier's own output permanently warns under yamllint, and correcting the
spacing makes Prettier undo it on the next run. The consumer cannot win.

**Reproduced directly:**

```console
$ cat a.yml
key: value  # two spaces, which yamllint's default rule wants
$ yamllint -c .yamllint.yml a.yml          # clean

$ prettier a.yml > b.yml
$ cat b.yml
key: value # Prettier rewrote it to one space
$ yamllint -c .yamllint.yml b.yml
  1:12  warning  too few spaces before comment: expected 2  (comments)
```

It is only a warning today, because the upstream yamllint hook does not pass
`--strict`, so it does not fail a run. What it does produce is permanent,
unfixable noise in every consumer's hook output, which trains people to
ignore yamllint findings.

**Where the fix already exists:** `ivan-pinatti/github-template` hit this and
relaxed the `comments` rule in its own copy, with a comment explaining
exactly this interaction. That fix should come back into
`templates/.yamllint.yml` rather than living only downstream.

Confirmed live in `ivan-pinatti/rsync-crypt` too: several of the 14 yamllint
warnings on its first adopted run were this rule.

## 3. `templates/.cspell.json` still ignores a MegaLinter directory

**Status:** open, trivial.

`ignorePaths` still lists `megalinter-reports/**`. MegaLinter was removed
from this library in `v2.0.0`, so that directory can no longer be produced by
anything here, and the entry is dead config shipped to every consumer.

Noticed by diffing the template against `github-template`'s snapshot, which
had already dropped it.

## 4. Decide what `templates/.lycheeignore` is for

**Status:** partially addressed in #12, decision still open.

No checklist in this library runs lychee, but `scripts/install.sh` copies
`.lycheeignore` into every consumer and `docs/getting-started.md` lists it
among the files to keep. `checklist-markdown` runs `markdown-link-check`
instead, which reads a different file entirely.

PR #12 adds the `.markdown-link-check.json` that was actually missing. The
remaining question is whether `.lycheeignore` should still ship at all, or be
documented purely as an optional extra for consumers who separately run
lychee.

## 5. Snapshot drift in `github-template`

**Status:** open, tracked in both repositories.

`docs/getting-started.md` already records that `ivan-pinatti/github-template`
holds a materialized snapshot of `templates/` which needs a manual refresh
when a template changes. It has drifted, and the drift runs in both
directions:

| File | State |
| --- | --- |
| `.markdownlint.yaml` | identical |
| `.yamllint.yml` | github-template is **ahead**, see item 2 |
| `.cspell.json` | github-template is **ahead** on item 3, and adds its own words |
| `.editorconfig` | diverged; github-template unsets `indent_size` deliberately |
| `.lycheeignore` | absent downstream, arguably correct, see item 4 |
| `.markdown-link-check.json` | absent downstream, add once #12 ships |

Reconciling this is not a one-way copy: some of what is downstream is a fix
this library should absorb.

## 6. `templates/.markdownlint.yaml` promises auto-fixing it does not do

**Status:** open. Affects every consumer of that template.

The file opens with:

```yaml
# Automatically fix problems markdownlint-cli2 knows how to fix.
fix: true
```

`fix` does nothing there. `.markdownlint.yaml` is markdownlint's **rule**
configuration; `fix` is a markdownlint-**cli2** runner option, and cli2 only
reads it from its own config file. Verified with an auto-fixable MD009
trailing-whitespace probe:

| Where `fix: true` is declared | Result |
| --- | --- |
| `.markdownlint.yaml` | file untouched |
| `.markdownlint-cli2.yaml` | file rewritten |

So the comment is false, and every consumer believes they have auto-fixing
and does not. Either drop the option and the claim, or ship a
`.markdownlint-cli2.yaml` where it actually works and decide whether
auto-fixing is wanted at all given "CI never autofixes" is the house rule in
at least one consumer.

Found by CodeRabbit on `rsync-crypt#12`, which had copied the template
verbatim.

## 7. `templates/.markdownlint.yaml`'s MD013 comment named the wrong source

**Status:** fixed in this pull request.

The comment said MD013's 100-character limit was set "to match
`.editorconfig`". Nothing should match `.editorconfig` here: MD013 is the
only thing that can enforce Markdown line length correctly, because
editorconfig-checker cannot tell that a wrapped pipe table or a fenced code
block is not a violation. A consumer that reads the old comment and then sets
`max_line_length` for `*.md` to agree with it gets unfixable findings, which
is what rsync-crypt hit and worked around with `unset` (see item 11).

The comment now says MD013 is the sole enforcement, and why.

## 8. `templates/.editorconfig` used `max_line_length = 0`

**Status:** fixed in this pull request.

Under `[COMMIT_EDITMSG]`. `max_line_length` is not in the EditorConfig
specification at all: the spec lists `indent_style`, `indent_size`,
`tab_width`, `end_of_line`, `charset`, `trim_trailing_whitespace`,
`insert_final_newline`, `root`, and the universal value `unset`.
`max_line_length` is a widely implemented extension whose values are only
documented per implementation. `0` is not documented anywhere, and
editorconfig-checker 3.11.1 reads it as a literal limit of zero, so it failed
every line of the file it was meant to exempt. Confirmed 2026-08-20 by running
the hook's own `ec` binary against a 300-character `COMMIT_EDITMSG`:

```text
max_line_length = 0        exit=1   Line too long (300 instead of 0)
max_line_length = off      exit=0
max_line_length = unset    exit=0
max_line_length = 50       exit=1   Line too long (300 instead of 50)
```

Now `unset`, which is the specification's universal "no value here" and so
holds in any implementation. `off` also passes, but only because this checker
discards values it cannot parse as a number, which is a tool behaviour rather
than a guarantee. Same spelling as item 11 recommends for `*.md`.

## 9. `--ticket-prefixes` has the separator gap the default path just lost

**Status:** open. Deliberately scoped out of
[#13](https://github.com/ivan-pinatti/pre-commit-checklists/pull/13), which
shipped as v2.2.2.

`check-branch-name.sh` now accepts `_` and `.` as separators on its default
path, so both dependency bots' branch names pass. The opt-in
`--ticket-prefixes` path was left alone, and its suffix class is still
`[-a-zA-Z0-9]*`, so it rejects exactly the characters the default path now
accepts:

| Branch, with `--ticket-prefixes PROJ` | Result |
| --- | --- |
| `PROJ-123-fix_something` | rejected, the underscore |
| `PROJ-123-bump-node.18` | rejected, the dot |

Scoping it out was reasonable: neither bot takes that path, and a smaller
diff was easier to verify. What it leaves is an undocumented inconsistency,
where one script applies two different rules to the same characters depending
on a flag. Either widen it to match, or say in the usage text that ticket mode
is deliberately stricter, and why.

The locale half is already fixed for both paths: v2.2.2 pinned `LC_ALL=C` for
the whole script rather than only the one regex, which also covers the
protected-branch comparison.

## 10. This file was untracked and got deleted once

**Status:** fixed by committing it.

Every item above was written into an untracked `docs/TODO.md`, on the basis
that a note does not need a commit. An agent then worked in this repository,
switched branches, and the file was gone: untracked files are not protected by
anything. It was recoverable only because a copy happened to exist elsewhere.

The lesson is the boring one. A note worth writing down is worth committing,
because the whole point of it is to outlive the session that produced it.

## 11. `templates/.editorconfig` fights markdownlint over `*.md`

**Status:** open. Not fixed here because it changes the template for every
consumer, which deserves its own pull request.

The `[*.md]` block sets `indent_size = 2` and `max_line_length = 100`. Both
produce findings that cannot be fixed while markdownlint is also enforcing
Markdown: editorconfig-checker reads a wrapped pipe table, a fenced code
block, and a nested list's continuation lines as violations, and there is no
way to tell it otherwise. rsync-crypt set both to `unset` for exactly this
reason and recorded why in its own `.editorconfig`.

`unset` rather than `off` is the right spelling: `unset` is in the
specification and applies to any property, and it is what removes the
property rather than giving it a sentinel value (see item 8).

The template should either `unset` both for `*.md`, or drop the `[*.md]`
block entirely and let markdownlint own the file type.

## CodeRabbit: automatic reviews stop silently on a busy branch

`.coderabbit.yaml` now sets `reviews.auto_review.auto_pause_after_reviewed_commits: 0`.
That is a change from the default of `5`, which pauses automatic reviews once
five commits on a branch have been reviewed.

**Why it matters:** the pause is silent. The CodeRabbit check still reports
green, so a pull request looks reviewed when nothing has read its current
head. Observed directly on
[pre-commit-checklists#12](https://github.com/ivan-pinatti/pre-commit-checklists/pull/12),
a branch with seven commits: reviews stopped after the fifth, and twelve
hours passed with no review of the head and no indication anything was
waiting. Recovery needs a manual `@coderabbitai review`.

**Still open, and not fixable by config:** CodeRabbit declines a review when
its usage limit is reached rather than queueing it, and never retries that
push. What is documented, rather than inferred: CodeRabbit's Fair Usage
Limits Policy applies per developer identity, across every repository that
identity touches, over a rolling seven-day window. The policy page does not
publish the numeric limit, and no numeric limit was observed directly, so no
rate is claimed here. The published configuration schema (`schema.v2.json`,
read 2026-08-20) has no retry, backoff, queue or poll setting anywhere in it,
so there is nothing to configure. Recovery is a manual `@coderabbitai
review`.

Worth knowing when judging whether a pull request is really reviewed:

- A green CodeRabbit **check** does not mean a review happened. It is green on
  a skipped draft and on a rate-limited decline.
- A **resolved** thread does not mean a fix was verified. CodeRabbit
  auto-resolves threads whose lines a later commit changed, which means the
  code moved, not that it was re-read.
- The reliable signal is comparing CodeRabbit's latest review timestamp
  against the head commit's timestamp.

`drafts: false` is deliberate and stays. CodeRabbit is a GitHub App posting a
check, not a workflow job, so it cannot be ordered after the pre-commit job
with a `needs:` dependency. Skipping drafts is the lever instead: open as a
draft, let pre-commit and the tests find the mechanical defects, then mark it
ready so a review slot is spent on a diff they have already cleaned.
