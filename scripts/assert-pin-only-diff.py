#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Ivan Pinatti
"""Refuse a unified diff that changes anything but a dependency pin.

Read a diff on stdin (`gh pr diff <n> | scripts/assert-pin-only-diff.py`) and
exit non-zero unless every changed file is one of the pin surfaces below and
every changed line differs from its counterpart in nothing but a version.

Ported from rsync-crypt's script of the same name (which itself carried the
reasoning forward from docker-torrent-box-with-vpn), the check that stands
between "renovate[bot] or dependabot[bot] opened a pull request" and an
unattended merge here. It exists for the same reason: approving a bot's pull
request on the strength of its author means the bot identity holds write
access to main, and a diff that is not actually pin-only is exactly the shape
a compromised or misconfigured bot would take. A path allowlist alone would
not be much of a fence, since `.github/workflows/` and the checklist files
under `checklists/` are executable and behavioral surfaces on their own; the
line comparison below is what makes it one.

The comparison normalizes both sides and requires them to match line for line
per file, duplicates counted. A line whose structure changed has no
counterpart and the diff is refused, which covers
`uses: actions/checkout@<sha> # v7` becoming `uses: evil/checkout@<sha> # v7`
as much as it covers an added `curl | sh`. Anything this refuses is not
broken, it just waits for a person: the approval is skipped and the pull
request sits there, which is the direction to fail in.

What it deliberately does not catch: a bump to a version that exists but is
malicious. `actionlint`'s `rev: v1.7.12` becoming `rev: v1.7.13` is exactly
the change this file exists to permit, and no amount of diff reading can tell
a good release from a backdoored one.

Four pin surfaces, and nothing else, chosen to match where a version pin
actually lives in this repository:

- `.tool-versions`: asdf tool versions (`pre-commit 4.5.1`), owned by
  Renovate's asdf manager.
- `.pre-commit-config.yaml`: this repo's own dogfood config, at the root.
  Every hook here is `repo: local` today (see that file's own header
  comment for why), so it has no `rev:` pins yet, but Dependabot's
  pre-commit ecosystem is already pointed at it and this surface is ready
  the day that changes.
- `checklists/`: every `checklists/checklist-*.yaml` file's own `rev:`
  pins on the upstream hooks it wraps (`actionlint`, `pre-commit-hooks`,
  and so on). These are watched by Renovate's own `pre-commit` manager,
  scoped to this directory in .github/renovate.json5, precisely because
  Dependabot's pre-commit ecosystem only ever reads a file literally named
  .pre-commit-config.yaml and never looks inside checklists/.
- `.github/workflows/`: `uses: ...@<sha> # vX` action pins, owned by
  Dependabot's github-actions ecosystem.

Deliberately not a pin surface here: the three version strings inside
checklists/*.yaml that a Renovate *custom.regex* manager watches instead of
the built-in `pre-commit` manager (the dotenv-linter Docker tag in
checklist-dev-dotenv.yaml, zizmor's PyPI pin in checklist-github-actions.yaml,
markdown-link-check's npm pin in checklist-markdown.yaml; see
docs/versioning.md). Each lives inside an `entry:` or
`additional_dependencies:` line with no shared shape to anchor a safe regex
on the way `rev:` or a `uses:` SHA does, so a bump to any of them fails this
assertion and waits for a person, same as a major bump does. That is the
conservative direction to be wrong in: those pull requests get no automatic
approval rather than a false one.
"""

import re
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

ALLOWED_PATHS = (
    ".tool-versions",
    ".pre-commit-config.yaml",
    "checklists/",
    ".github/workflows/",
)

# A released version, always starting with a digit (an optional single
# leading `v` aside): `2.2.2`, `v2.2.2`, `4.5.1`. Anchors both `rev:` in
# .pre-commit-config.yaml/checklists/*.yaml and every value in
# .tool-versions, and is deliberately narrower than "any tag-shaped token": a
# floating ref like `main` or `latest` is made entirely of characters this
# would otherwise accept, and normalizing it the same as a real release would
# let a compromised bot trade an immutable pin for something that can move
# under it after the diff is already merged, with nothing left in the diff to
# catch it.
RELEASE = r"v?[0-9][0-9A-Za-z.+_-]*"

# .tool-versions writes `<tool> <version>`, one per line, with nothing to
# anchor on but the space. That cannot go in the prefix set below, because a
# lookbehind of variable width is not allowed and "the word after a space"
# would match most of a workflow file. It is matched whole-line instead, and
# only for that file, which is why normalize() takes the path. The value
# after the space has to be a real release, not merely non-blank: `pre-commit
# main` would otherwise normalize identically to `pre-commit 4.5.1`.
TOOL_VERSION_LINE = re.compile(
    r"^(?P<prefix>[A-Za-z0-9_.-]+[ \t]+)" + RELEASE + r"[ \t]*$"
)

# A pre-commit hook `rev:`, wherever it appears: the root
# .pre-commit-config.yaml or any checklists/checklist-*.yaml. The prefix is
# captured and put back, so that a pin changing shape rather than value still
# reads as a difference.
#
# GitHub Actions pins are handled separately below rather than through this
# same released-version grammar: this repository, like the one it was ported
# from, pins every action to a full commit SHA rather than a tag (see any
# `uses:` line in .github/workflows/), so the immutable shape to require
# there is a SHA, not a release number.
REV_PIN = re.compile(r"(?P<prefix>\brev:[ \t]+)" + RELEASE)

# A GitHub Actions pin, always a full 40 character commit SHA in this
# repository (Dependabot updates it that way), optionally followed by the
# trailing `# vX.Y.Z` comment Dependabot writes and rewrites alongside it.
# The negative lookahead stops a 40 character prefix of a longer hex run from
# matching and silently swallowing the character that would have made the
# shapes differ.
#
# The trailing comment has to be normalized too, not left as ordinary text:
# this repository pins with a full semver comment (`# v7.0.1`), not a
# major-version-only one (`# v7`), so Dependabot rewrites that comment on
# every bump, patch releases included. Leaving it untouched would refuse
# every ordinary action bump as "not pin-only", which defeats the entire
# point of this script. The comment is optional in the regex so a `uses:`
# line with no trailing comment, or one that is not version-shaped (and
# therefore not matched, left as literal text for both sides to compare
# against), is still handled correctly: only a comment that already looks
# like a release is treated as part of the pin.
ACTION_SHA = re.compile(
    r"(?P<prefix>@)[0-9a-f]{40}(?![0-9a-fA-F])"
    r"(?P<comment>[ \t]*#[ \t]*" + RELEASE + r")?"
)

FILE_HEADER = re.compile(r"^diff --git a/(?P<old>.+) b/(?P<new>.+)$")


def _normalize_action_sha(match: re.Match[str]) -> str:
    if match.group("comment"):
        return f"{match.group('prefix')}<version> # <version>"
    return f"{match.group('prefix')}<version>"


def normalize(line: str, path: str = "") -> str:
    """Reduce a line to everything about it that a version bump may not change."""
    if path.endswith(".tool-versions"):
        return TOOL_VERSION_LINE.sub(r"\g<prefix><version>", line)
    line = ACTION_SHA.sub(_normalize_action_sha, line)
    line = REV_PIN.sub(r"\g<prefix><version>", line)
    return line


def parse(diff: str) -> tuple[dict[str, tuple[Counter, Counter]], list[str]]:
    """Group removed and added lines by file, and collect structural changes."""
    changes: dict[str, tuple[Counter, Counter]] = {}
    structural: list[str] = []
    path = None
    in_hunk = False

    for line in diff.splitlines():
        header = FILE_HEADER.match(line)
        if header:
            old, new = header.group("old"), header.group("new")
            path = new
            in_hunk = False
            changes.setdefault(path, (Counter(), Counter()))
            if old != new:
                structural.append(f"{old} renamed to {new}")
            continue

        if line.startswith("@@"):
            in_hunk = True
            continue

        # Everything between a file header and its first hunk is preamble: the
        # index line, the ---/+++ pair, and any mode line. Recognizing those
        # only here is what stops a content line impersonating one. Inside a
        # hunk, `+++foo` is an added line reading `++foo`, and skipping it as
        # a file header would drop it from the comparison, which fails open.
        if not in_hunk:
            if line.startswith(
                ("new file ", "deleted file ", "old mode ", "new mode ")
            ):
                structural.append(f"{path}: {line.strip()}")
            continue

        if path is None:
            continue

        if line.startswith("-"):
            changes[path][0][normalize(line[1:], path)] += 1
        elif line.startswith("+"):
            changes[path][1][normalize(line[1:], path)] += 1

    return changes, structural


def main() -> int:
    diff = sys.stdin.read()
    if not diff.strip():
        print("REFUSED: the diff is empty, so there is nothing to approve.")
        return 1

    changes, problems = parse(diff)

    # Output that parsed into nothing is not a clean bill of health. Truncated
    # output, a binary diff, or anything that arrives without a `diff --git`
    # header would otherwise leave the change set empty and read as "no
    # problems found", approving a diff nobody managed to read.
    if not changes:
        print("REFUSED: no file headers in the diff, so nothing could be checked.")
        return 1

    for path in changes:
        if not path.startswith(ALLOWED_PATHS):
            problems.append(f"{path}: not a dependency pin file")

    for path, (removed, added) in changes.items():
        if not removed and not added:
            problems.append(
                f"{path}: no readable changed lines, so nothing was checked"
            )

    for path, (removed, added) in changes.items():
        # Counter subtraction drops non-positive counts, so each direction has
        # to be asked separately to see both halves of a mismatch.
        for line in removed - added:
            problems.append(f"{path}: removed a line that was not re-added: -{line}")
        for line in added - removed:
            problems.append(
                f"{path}: added a line that was not a version bump: +{line}"
            )

    if problems:
        print("REFUSED: this diff changes more than dependency pins.")
        for problem in problems:
            print(f"  {problem}")
        print(
            "\nNothing is broken. The automated approval is skipped and the pull "
            "request waits for a person, which is what should happen when a "
            "dependency bot reaches outside its lane."
        )
        return 1

    files = ", ".join(sorted(changes)) or "nothing"
    print(f"Pin-only diff confirmed: {files}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
