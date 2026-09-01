# The Merge Pipeline

<!-- cspell:words coderabbit coderabbitai renovate zizmor -->

What happens between opening a pull request against this repository and it
landing on `main`. Ported from `rsync-crypt`'s document of the same name,
which this pipeline was ported from, adapted to what this repository
actually contains: a hook checklist library with a real self-test suite
(`tests/run_tests.sh`) but no build, no Docker image, and no app code of its
own. Where the reasoning is identical to rsync-crypt's it is only
summarized here, not restated; see that repository's `docs/MERGE_PIPELINE.md`
for the fuller version this one was trimmed from, and its `CLAUDE.md` for the
operational gotchas (recognizing a genuine CodeRabbit review, recovering a
rebased branch, and so on) that apply here unchanged.

## What actually gates a merge

Four required status checks on `main`'s branch protection:

| Context | What it actually proves | Who publishes it |
| --- | --- | --- |
| `Pre-commit` | The full pre-commit hook set (this repo's own dogfood config) passed over every file | `pull-request.yml`, as a job |
| `Tests` | `tests/run_tests.sh`'s five phases passed | `pull-request.yml`, as a job |
| `Pin Only` | A dependency bot's diff changes nothing but a version in a pin position; `success` with a "not a dependency bot pull request" description on everything else | `coderabbit-gate.yml`, published directly onto the head SHA |
| `Review Verified` | CodeRabbit's actual review outcome, not merely that it reported something | `coderabbit-gate.yml`, published directly onto the head SHA |

`Pre-commit` and `Tests` are ordinary workflow jobs: GitHub reports a job's
own pass or fail as the check. The other two are commit statuses, written
directly by a workflow step rather than read off a job's outcome, for the
same reason as in rsync-crypt: a status a workflow chooses whether to write,
and what to write, does not read as passed merely because it was skipped.

There is no `Docker Build` context here, deliberately: this library ships no
image, so nothing in this pipeline builds or pushes one.

## A human pull request

Open it as a **draft** first. `Pre-commit` runs the full hook set over every
file, and CodeRabbit does not review a draft at all: `.coderabbit.yaml` sets
`drafts: false` on purpose, so a review is not spent on a diff the mechanical
linters have not finished cleaning up yet.

**Mark it ready for review** once `Pre-commit` and `Tests` are green. That is
what starts CodeRabbit. Address what it raises, pushing fixes as needed; each
push re-runs both jobs and gets a fresh review.

Once every required check reads green and a maintainer has approved it, the
pull request is eligible for the merge queue, but entering it still needs
someone to select **Merge when ready** (or enable auto-merge); nothing here
enqueues it on its own. Once it is enqueued, it merges when the queue's own
run of the same check set passes on the commit the queue actually builds; see
"The merge queue" below.

## The repository owner's own pull request

Ivan is the only account with write access here, and GitHub refuses to let an
account approve its own pull request. `bot-auto-merge.yml`'s `approve-owner`
job is the fix, ported unchanged in reasoning from rsync-crypt: once
`Pre-commit`, `Tests`, `Pin Only` and `Review Verified` are all green, it
supplies the approval that makes the pull request queue eligible, without
arming auto-merge, so the owner still decides when to enqueue. This approval
is not evidence a human read the diff; it is issued the moment the four
contexts settle, which is exactly why it waits for `Review Verified` rather
than `Pin Only` alone. A contributor or a fork gets no approval from this job
and still needs a genuine human review, same as always.

## A dependency bot pull request

Dependabot (`.github/dependabot.yml`: github-actions, Wednesday 06:30
America/Toronto; pre-commit, Wednesday 06:00) and Renovate
(`.github/renovate.json5`: the asdf `.tool-versions` surface and the
checklist-scoped upstream hook pins, daily before 7am, not scoped to a
single day the way Dependabot is: a pin-only bump spends no CodeRabbit
review quota, and BOT_SCHEDULE.md's day-spreading exists only to protect
that quota) open pull requests unattended. For the ones that are pin only:

1. **`Pin Only` is graded.** `scripts/assert-pin-only-diff.py` checks that
   every changed line differs from its counterpart in nothing but a version,
   across four pin surfaces real to this repository: `.tool-versions`,
   `.pre-commit-config.yaml`, `checklists/*.yaml` `rev:` pins, and
   `.github/workflows/*.yml` action SHA pins. See that script's own
   docstring for exactly what is and is not covered, including the three
   checklist-embedded version strings (dotenv-linter's image tag, zizmor's
   PyPI pin, markdown-link-check's npm pin) that are deliberately **not** a
   pin surface: a bump to any of them fails this assertion and waits for a
   person, the conservative direction to be wrong in.
2. **The approval is supplied, conditionally.** `bot-auto-merge.yml` waits
   for `Pin Only` to read `success` and then supplies the approving review
   branch protection requires. A diff that is not pin-only gets no approval
   and waits for a person, same as a major bump does.
3. **GitHub enqueues and merges it** once every required check, including
   `Review Verified`, is green and the approval is in place, the same as any
   other pull request.

**A gap that was raised in review and then disproved.** Renovate arms its
own automerge through `platformAutomerge`, using Renovate's own GitHub App
installation token. Dependabot cannot arm auto-merge itself, so
`bot-auto-merge.yml`'s last step does it with `gh pr merge --auto`,
authenticated as `secrets.GITHUB_TOKEN`. CodeRabbit's review of the pull
request that added this pipeline reported that GitHub's documentation says
this token cannot add a pull request to a merge queue, naming that exact
command, and proposed provisioning a separate merge-capable credential.

It was tested instead of accepted, and it does not hold.
`ivan-pinatti-labs/github-template` runs the same workflow with an active
merge queue ruleset, and its Dependabot pull request #11 exercised this
step: `bot-auto-merge.yml` run `33433281810` reported `Enable auto-merge`
as `success`, and the pull request then reported `enabledBy:
app/github-actions` with `mergeMethod: SQUASH`. Auto-merge was armed by
`GITHUB_TOKEN` against a repository with a merge queue.

Arming is not the same as a queue accepting the entry, which review pointed
out and which that evidence on its own does not cover. The traversal is
proven separately, on rsync-crypt: pull request #43 merged through its
queue, leaving `merge_group` runs `33516020124` and `33516020136` against
the ref `gh-readonly-queue/main/pr-43-<sha>`, both `success`. That ref
exists only because the queue built the entry, so the two observations
together cover arming and entry rather than arming alone.

Recorded here rather than deleted, because the claim is plausible, cites
real documentation, and will be raised again by the next reviewer. No extra
credential is needed for this path.

## What actually gets reviewed, and what does not

Same shape as rsync-crypt, summarized: a dependency bot pull request whose
diff is pin only merges with no CodeRabbit review at all.
`scripts/coderabbit-review-verdict.py`'s bot lane resolves `Review Verified`
straight to `success` the moment `Pin Only` reads `success`, and
`coderabbit-review-queue.yml`'s hourly nudge skips it for the same reason.
CodeRabbit only enters the bot lane when `Pin Only` **fails**, and even then
gets no automatic approval; a person is already looking. See rsync-crypt's
`docs/MERGE_PIPELINE.md`, "What actually gets reviewed, and what does not,"
for the fuller argument, including why Renovate's `minimumReleaseAge` cooling
window (kept here at 7 days, see `.github/renovate.json5`) is the actual
defence against a release that is well formed and malicious, not the `Pin
Only` assertion itself.

## `Review Verified`, and the bug it exists to fix

Ported unchanged in reasoning from rsync-crypt (which itself ported it from
docker-torrent-box-with-vpn ahead of that repository's own #114): a green
`CodeRabbit` check does not mean a review happened, because CodeRabbit posts
through the legacy commit status API, which has no state for "green, but not
for the reason you think." `scripts/coderabbit-review-verdict.py`, published
as `Review Verified` by `coderabbit-gate.yml`, reads the actual description
behind the `CodeRabbit` status rather than its color, and grades in three
lanes: a draft is `pending`; a dependency bot pull request is graded on
`Pin Only` first (a clean verdict is `success` with no review at all, a diff
that fails it falls through to lane three); everything else is `success`
only for the literal description `Review completed`, with an in-flight
review (`Review queued`/`Review in progress`) read as `pending` rather than
`failure`. See that script's own docstring for the full reasoning, and
rsync-crypt's `CLAUDE.md`, "Knowing whether CodeRabbit has actually reviewed
a branch," for how to tell a genuine review from a status that merely looks
like one.

## Recovering a stuck `Review Verified`

`coderabbit-gate.yml`'s hourly schedule (`41 * * * *`, offset from
rsync-crypt's `47 * * * *` and this repository's own
`coderabbit-review-queue.yml` at `17 * * * *`, so this organization's hourly
CodeRabbit jobs do not pile onto the same Actions minute) is a real
mitigation, not a guarantee: GitHub deprioritises scheduled workflows on
public repositories under load and can skip a slot outright. See
rsync-crypt's `docs/MERGE_PIPELINE.md`, "Recovering a stuck `Review
Verified`, honestly," for the specific evidence of that happening there.
`workflow_dispatch` on `coderabbit-gate.yml` is the manual recovery path,
run by anyone with write access, against a single `pr_number` or every open
pull request at once.

For a stuck review specifically (not a stuck grading run), the actual fix is
a genuine human `@coderabbitai review` comment: `coderabbit-review-queue.yml`
posts that hourly through a bot account, and per rsync-crypt's `CLAUDE.md`,
"CodeRabbit silently ignores `@coderabbitai review` from a bot account,"
that comment does not reliably make CodeRabbit start a review. Check the
pull request's comments for a `coderabbitai[bot]` reply before assuming the
request is in flight; if there is none, only a human posting the same
comment will move it.

## The merge queue

This repository transferred from a personal account to the
`ivan-pinatti-labs` organization specifically so a `merge_queue` ruleset rule
could exist at all: GitHub refuses that rule under personal ownership and
accepts it under an organization. `merge_group:` triggers on `pull-request.yml`
and `coderabbit-gate.yml` are what let every required context run a second
time against the queue's own temporary commit before anything actually
merges.

Branch protection on `main` requires `Pre-commit`, `Tests`, `Pin Only` and
`Review Verified`, one approval, dismissal of stale reviews, approval of the
last push, conversation resolution and a linear history. `enforce_admins` is
`false`, which lets the owner merge without being blocked by rules an admin
can bypass, but does not exempt the owner's own pull request from the
approval the queue itself requires to accept it, which is what makes "The
repository owner's own pull request" above necessary. `allow_auto_merge` has
to be enabled, or the queue cannot accept anything at all.

## The bootstrap this document's own pull request went through

`coderabbit-gate.yml` and `bot-auto-merge.yml` trigger on
`pull_request_target`, which runs the workflow file **from the base branch**.
On the pull request that first added them they did not exist on `main` yet,
so they did not run, and `Pin Only`/`Review Verified` could not be published
on that pull request. Branch protection and the merge queue ruleset were
therefore applied only **after** that pull request merged, the same bootstrap
rsync-crypt went through ("ported ahead of need... every job below was
inert"). That pull request still needed `Pre-commit` and `Tests` green and a
genuine CodeRabbit review before merging; it just could not be gated on
`Pin Only` or `Review Verified`, since neither context could exist yet.

## What was ported, and what was deliberately left out

Ported: `.github/workflows/coderabbit-gate.yml`,
`.github/workflows/coderabbit-review-queue.yml`,
`.github/workflows/bot-auto-merge.yml`, `scripts/assert-pin-only-diff.py`,
`scripts/coderabbit-review-verdict.py`, the `Pin Only`/`Review Verified`
settings in `.coderabbit.yaml`, and the `merge_group:` trigger plus the
`Pre-commit`/`Tests` context renames in `pull-request.yml` (this repository's
existing `pull-request-validation.yml` equivalent; reworked in place rather
than duplicated, so there are not two workflows both firing on every pull
request).

Left out, and why:

- **`merge.yml`** (rsync-crypt's tag-and-release workflow). This repository
  already has `.github/workflows/new-tag-and-release.yml` doing that job;
  adding rsync-crypt's copy on top would be a second, competing tag-and-release
  path against the same `main`.
- **A `Docker Build` job.** No image is built here; see "What actually gates
  a merge" above.
- **Renovate's `.env.example` custom regex manager.** There is no
  `.env.example` in this repository.
- **`.github/zizmor.yml`.** rsync-crypt's copy exists only to scope one
  ignore to a line in `merge.yml`, which this repository does not have.
  zizmor runs clean over every workflow ported here (verified directly,
  `--no-online-audits`, the same flags `checklist-github-actions` uses), so
  no ignore file was added; one can be added later if a real finding needs
  scoping.

---

See also: [README.md](../README.md), [CLAUDE.md](../CLAUDE.md),
[docs/versioning.md](versioning.md)
