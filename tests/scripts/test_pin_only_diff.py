#!/usr/bin/env python3
"""Phase (static): guard the Pin Only gate's grammar against silent drift.

Read-only. Feeds hand written diffs to scripts/assert-pin-only-diff.py and
asserts the verdict for each shape, so the check that stands between a
dependency bot's pull request and an unattended merge cannot change what it
accepts without a test here saying so.

Why this exists at all. A sibling repository's copy of that script
normalized a `uses:` pin's SHA but left the trailing release comment as
ordinary text, so an ordinary bump that also moved `# v4.37.9` to
`# v4.38.0` compared unequal, read as a structural change, and was refused.
No action SHA bump could reach an unattended merge there for as long as the
copy existed. It went unnoticed because the only fixtures anywhere pinned
the same comment on both sides of the bump, which is not a shape Renovate
produces: it rewrites the comment whenever the tag the SHA resolves from
changes. The first case below is that shape.

The gate is imported rather than run through a subprocess. `main()` reads a
diff from stdin and returns an exit code, so a redirected stdin is all it
needs, and this file stays free of subprocess use.

Exit 0: every shape got the verdict recorded here.
Exit 1: at least one did not; each mismatch is printed with its diff.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
GATE = REPO_ROOT / "scripts" / "assert-pin-only-diff.py"

# A 40 character hex string, the shape of a GitHub Actions commit pin.
SHA = "a" * 40
OTHER_SHA = "b" * 40

WORKFLOW = ".github/workflows/pull-request.yml"
CHECKLIST = "checklists/checklist-github-actions.yaml"
DOCS = "docs/hook-catalogue.md"
DEVCONTAINER = ".devcontainer/Dockerfile"

BASE_IMAGE = "ghcr.io/ivan-pinatti-labs/devcontainer-base"
DIGEST = "4" * 64
OTHER_DIGEST = "7" * 64

ACCEPT = 0
REFUSE = 1


def load_gate():
    """Import the gate, whose filename is not importable as a module name."""
    spec = importlib.util.spec_from_file_location("pin_only_gate", GATE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {GATE}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def diff(path: str, body: str) -> str:
    """Wrap changed lines in the headers a real `gh pr diff` would carry."""
    return (
        f"diff --git a/{path} b/{path}\n"
        f"--- a/{path}\n"
        f"+++ b/{path}\n"
        "@@ -1,3 +1,3 @@\n"
        f"{body}"
    )


def verdict(gate, text: str) -> int:
    """Return the gate's exit code for `text`, keeping its output quiet."""
    saved = sys.stdin
    sys.stdin = io.StringIO(text)
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            return int(gate.main())
    finally:
        sys.stdin = saved


# Each case is (description, expected exit code, diff). The expectations are
# what this repository's gate does today, measured before they were written
# down, not what a sibling copy happens to do.
CASES = [
    (
        "a SHA bump whose trailing release comment moves with it",
        ACCEPT,
        diff(
            WORKFLOW,
            "       - name: Checkout\n"
            f"-        uses: actions/checkout@{SHA} # v4.37.9\n"
            f"+        uses: actions/checkout@{OTHER_SHA} # v4.38.0\n",
        ),
    ),
    (
        "a first time pin, its comment appearing with the SHA",
        ACCEPT,
        diff(
            WORKFLOW,
            "       - name: Checkout\n"
            "-        uses: actions/checkout@v7\n"
            f"+        uses: actions/checkout@{SHA} # v7\n",
        ),
    ),
    (
        "a first time pin written as a bare YAML list item",
        ACCEPT,
        diff(
            WORKFLOW,
            "     steps:\n"
            "-      - uses: actions/checkout@v7\n"
            f"+      - uses: actions/checkout@{SHA} # v7\n",
        ),
    ),
    (
        "a first time pin whose SHA is uppercase",
        ACCEPT,
        diff(
            WORKFLOW,
            "       - name: Checkout\n"
            "-        uses: actions/checkout@v7\n"
            f"+        uses: actions/checkout@{SHA.upper()} # v7\n",
        ),
    ),
    (
        "a first time pin arriving with no release comment",
        REFUSE,
        diff(
            WORKFLOW,
            "       - name: Checkout\n"
            "-        uses: actions/checkout@v7\n"
            f"+        uses: actions/checkout@{SHA}\n",
        ),
    ),
    (
        "trailing text changing beside an otherwise real SHA bump",
        REFUSE,
        diff(
            WORKFLOW,
            "       - name: Checkout\n"
            f"-        uses: actions/checkout@{SHA} # v7 keep\n"
            f"+        uses: actions/checkout@{OTHER_SHA} # v8 changed\n",
        ),
    ),
    (
        "a pin the diff shows no shallower line to judge against",
        REFUSE,
        diff(
            WORKFLOW,
            f"-        uses: actions/checkout@{SHA} # v7\n"
            f"+        uses: actions/checkout@{OTHER_SHA} # v7\n",
        ),
    ),
    (
        "the zizmor pin, which has no safe anchor and waits for a person",
        REFUSE,
        diff(
            CHECKLIST,
            "        language: python\n"
            '-        additional_dependencies: ["zizmor==1.29.0"]\n'
            '+        additional_dependencies: ["zizmor==1.30.1"]\n',
        ),
    ),
    (
        "a file that is not a pin surface at all",
        REFUSE,
        diff(
            DOCS,
            " prose\n-pinned v1.29.0\n+pinned v1.30.1\n",
        ),
    ),
    (
        "the development container base image digest moving",
        ACCEPT,
        diff(
            DEVCONTAINER,
            " # comment\n"
            f"-ARG BASE_IMAGE={BASE_IMAGE}@sha256:{DIGEST}\n"
            f"+ARG BASE_IMAGE={BASE_IMAGE}@sha256:{OTHER_DIGEST}\n",
        ),
    ),
    (
        "that digest moving while the image itself is swapped",
        REFUSE,
        diff(
            DEVCONTAINER,
            " # comment\n"
            f"-ARG BASE_IMAGE={BASE_IMAGE}@sha256:{DIGEST}\n"
            f"+ARG BASE_IMAGE=ghcr.io/attacker/devcontainer-base"
            f"@sha256:{OTHER_DIGEST}\n",
        ),
    ),
    (
        "an unrelated line in the development container Dockerfile",
        REFUSE,
        diff(
            DEVCONTAINER,
            " # comment\n"
            "-RUN apt-get install -y curl\n"
            "+RUN apt-get install -y curl ca-certificates\n",
        ),
    ),
]


def main() -> int:
    gate = load_gate()
    failures = []

    for description, expected, text in CASES:
        actual = verdict(gate, text)
        if actual != expected:
            failures.append((description, expected, actual, text))

    if failures:
        print("pin-only-lint: the gate's verdict changed for some shapes.")
        print("Each case below records what this gate did when the test was")
        print("written. A mismatch means the grammar moved; decide whether")
        print("that was intended before changing the expectation.")
        print()
        for description, expected, actual, text in failures:
            print(f"  {description}")
            print(f"    expected exit {expected}, got {actual}")
            for line in text.splitlines():
                print(f"    | {line}")
            print()
        return 1

    print(f"pin-only-lint: {len(CASES)} diff shape(s) checked, all as recorded.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
