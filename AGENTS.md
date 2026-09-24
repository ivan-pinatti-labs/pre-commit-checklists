# pre-commit-checklists agent instructions

Instructions for AI coding agents working in this repository. Claude Code
reads them through `CLAUDE.md`; Codex and CodeRabbit read this file
directly.

## Organization conventions

Shared by every `ivan-pinatti-labs` repository and kept identical across
them, so change it everywhere at once. Where this repository's own sections
are more specific, follow them.

### Everything here is public

- Nothing sensitive, controversial or borderline goes into a commit, pull
  request, issue, comment or committed agent file. That includes secrets,
  tokens, personal paths, email addresses other than a GitHub noreply one,
  host names, LAN addresses and details of anyone's own deployment.
- Personal or machine specific material stays in gitignored files:
  `CLAUDE.local.md` for notes, `.claude/settings.local.json` for settings,
  `.claude/agents/local/` for agents.
- Sensitive content found already committed is reported to a maintainer.
  Never rewrite history or force push to remove it.

### Run binaries in containers, not on the host

A binary that did not come from the operating system's package manager (a
release download, an installer script, a new version under evaluation, a
scanner, a debugging tool) runs inside a rootless Podman container, never
directly on the host. That holds when validating,
testing, checking a new version and debugging.

```bash
podman run --rm --network=none \
  -v "<only what it needs>:/work:ro,Z" -w /work \
  <image> <binary> [args]
```

- The container gets what the process needs and nothing else. Mount only the
  specific files and folders required, read only. Add network access or
  `:rw` only when the task requires it, and say so.
- Prefer the tool's official image, pinned to a version. For a bare release
  binary use `debian:13-slim` rather than Alpine: glibc builds fail on musl
  with a misleading "No such file or directory".
- On SELinux hosts a bind mount needs a label (`Z`). Do not relabel a large
  tree that other containers also use; copy what is needed into a scratch
  directory and mount that.
- Podman is the default container runtime: rootless, with no daemon.
- Exceptions: the hook environments pre-commit builds, and the containers
  this repository's own `Makefile` or hooks start.

### Parallel work uses worktrees

More than one agent may work in a repository at the same time. Give each task
its own worktree under `.claude/worktrees/<branch>` (gitignored), and never
switch branches in a checkout someone else may be using.

### Unattended work runs on a bounded tick

Work left running while nobody is watching is driven by a bounded pass, never
by a wait for the outcome you want.

A background wait whose only exit is success does not fail, it disappears. A
pull request sitting in a merge queue is the worked example: a flaky check
ejects it, which is neither merged nor closed, so a loop waiting for "merged"
runs forever, nothing notifies, and the session stops. That cost roughly
sixteen unattended hours here on 2026-09-22, and the giveaway is that silence
and progress look identical from outside.

So:

- **Cap every pass**, around fifty minutes, and report on exit whether or not
  anything moved. Time always advances, so no condition can trap it. Say
  plainly when a pass did nothing, because a quiet pass and a dead session
  have to look different.
- **Re-derive state from the API every pass.** Draft status, review verdict,
  unresolved threads, approval, queue membership. Never carry a belief from
  the previous pass.
- **Handle every terminal state, not only the good one.** Released from
  draft, review declined, approval job timed out, ejected from the queue,
  merged, closed. A pass that only knows how to recognize success cannot
  recover anything.
- **Before arming a wait, ask what would wake you if this failed right now.**
  If the answer is nothing, widen the condition.
- **A pass that ends with nothing moved and no reason is a signal to
  inspect**, not to re-arm the same watch.
- **Never finish a turn** without either a bounded wait armed or an explicit
  statement that work has stopped.

### Writing style

Do not use a hyphen, em dash or en dash as punctuation in prose, code
comments, commit messages or pull request text. Use commas, parentheses or
separate sentences. Hyphens inside compound words and in code, paths, flags
and identifiers are fine.

### Commits and pull requests

- Conventional Commits with an imperative subject. Branch names are lowercase
  slugs such as `fix/flaky-test`. Never commit directly to `main`.
- Open a pull request as a draft and mark it ready once the checks are green;
  marking it ready is what starts CodeRabbit. `docs/MERGE_PIPELINE.md` is the
  authority on required checks and how a pull request merges.
- Answer every CodeRabbit comment on its thread, and say plainly when
  declining one and why.
- Never force push.
- Never add AI attribution: no AI `Co-Authored-By` trailer and no "Generated
  with" line, in commits, pull requests, comments, issues or docs.

## Commits in this repository

Conventional Commits, imperative subject line, no ticket prefix baked in.
Ticket prefixes are an opt-in override for *consumers* of this library (see
docs/overrides.md), not a convention this repository's own history follows.

## Checklists and scripts

- Checklists live under `checklists/`, one YAML file per checklist, each a
  standalone `pre-commit` config consumed through `scripts/run-checklist.sh`.
- Shell scripts use `#!/usr/bin/env bash`, the explicit `set -o errexit`,
  `set -o pipefail`, `set -o nounset` trio, and a leading `: '...'` doc
  comment naming every exit status code.
- A hook id's `types:`/`types_or:` and `files:` selectors are ANDed by
  pre-commit, not ORed. Read docs/hook-catalogue.md's "Why the selector
  matters" section before adding either to a new hook id; two defects in an
  earlier version of this checklist set came from exactly that mistake.
- The `rev:` pins inside `checklists/*.yaml` and the `rev:` a consumer puts
  in their own `.pre-commit-config.yaml` are two different things that move
  independently. See docs/versioning.md before changing either.
