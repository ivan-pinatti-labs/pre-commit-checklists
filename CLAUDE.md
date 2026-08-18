# Repository instructions

## Writing style

- Do not use the hyphen character, or an em dash or en dash, as punctuation,
  anywhere: not in doc prose, code comments, commit messages, PR/issue text,
  or any other written output in this repo. Use commas, parentheses, or
  separate sentences instead. Hyphens are fine inside compound words (e.g.
  `pre-commit`, `self-signed`) and in code, paths, flags, and identifiers.

## Pull requests

1. Open as a draft (`gh pr create --draft`). Let the pre-commit checks run
   before asking anyone to look at it.
2. Mark ready (`gh pr ready <n>`) once the checks are green.
3. Never add AI attribution anywhere: no `Co-Authored-By`, no "Generated with
   Claude Code", not in commits, PR bodies, comments, issues, or docs.

## Commits

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
