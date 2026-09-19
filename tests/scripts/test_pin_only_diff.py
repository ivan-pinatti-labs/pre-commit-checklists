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
import difflib
import importlib.util
import io
import sys
import tempfile
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


# Whole-file block scalar judgment. The gate reads the workflow's base side
# from its own checkout, so each case points the gate's REPO_ROOT at a scratch
# directory holding `base`, and builds a real `index` line from it.
STEP_WITH_COMMENT = (
    "jobs:\n"
    "  scan:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - name: Upload the scan\n"
    "        # A comment between the step's name and its uses: line, long\n"
    "        # enough that three lines of diff context above the pin never\n"
    "        # reach anything shallower than it.\n"
    "        uses: github/codeql-action/upload-sarif@{sha} # v4\n"
    "        with:\n"
    "          sarif_file: scan.sarif\n"
)
NESTED_IN_RUN = (
    "jobs:\n"
    "  build:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - name: Build\n"
    "        run: |\n"
    "          if true; then\n"
    "            uses: fake/action@{sha} # v4\n"
    "          fi\n"
)

ANCHORED_RUN = (
    "jobs:\n"
    "  build:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - name: Build\n"
    "        run: {props} |2-\n"
    "            uses: fake/action@{sha} # v4\n"
)
DASH_NAME_SIBLING = (
    "jobs:\n"
    "  scan:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - name: |\n"
    "          Upload the scan\n"
    "        uses: github/codeql-action/upload-sarif@{sha} # v4\n"
)

PROPERTIES_ON_STEP = (
    "jobs:\n"
    "  scan:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - {props} name: |\n"
    "          Upload the scan\n"
    "        uses: github/codeql-action/upload-sarif@{sha} # v4\n"
)

SPLIT_INDICATOR_RUN = (
    "jobs:\n"
    "  build:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - name: Build\n"
    "        run: {props}\n"
    "          |\n"
    "          uses: fake/action@{sha} # v4\n"
)

SEQUENCE_ITEM_SPLIT = (
    "jobs:\n"
    "  build:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - name: Build\n"
    "        run:\n"
    "          {item}\n"
    "            |\n"
    "            uses: fake/action@{sha} # v4\n"
)
COMMENT_BEFORE_OPENER = (
    "jobs:\n"
    "  build:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - name: Build\n"
    "        # note: |\n"
    "        run: &body |-\n"
    "          uses: fake/action@{sha} # v4\n"
)


def whole_file_diff(gate, before: str, after: str) -> str:
    """A `git diff` shaped diff of `before` to `after`, index line included."""
    old = gate._git_blob_id(before.encode())[:12]
    new = gate._git_blob_id(after.encode())[:12]
    body = "".join(
        difflib.unified_diff(
            [line + "\n" for line in before.splitlines()],
            [line + "\n" for line in after.splitlines()],
            f"a/{WORKFLOW}",
            f"b/{WORKFLOW}",
        )
    )
    return f"diff --git a/{WORKFLOW} b/{WORKFLOW}\nindex {old}..{new} 100644\n{body}"


def whole_file_verdict(gate, base: str, text: str) -> int:
    """The gate's exit code for `text` with `base` as the checked out file."""
    saved = gate.REPO_ROOT
    with tempfile.TemporaryDirectory() as root:
        workflow = Path(root) / WORKFLOW
        workflow.parent.mkdir(parents=True)
        workflow.write_text(base)
        gate.REPO_ROOT = Path(root)
        try:
            return verdict(gate, text)
        finally:
            gate.REPO_ROOT = saved


def whole_file_cases(gate) -> list[tuple[str, int, str, str]]:
    """(description, expected exit code, checked out base, diff)."""
    before = STEP_WITH_COMMENT.format(sha=SHA)
    after = STEP_WITH_COMMENT.format(sha=OTHER_SHA)
    step = whole_file_diff(gate, before, after)
    nested_before = NESTED_IN_RUN.format(sha=SHA)
    nested = whole_file_diff(gate, nested_before, NESTED_IN_RUN.format(sha=OTHER_SHA))
    sibling_before = DASH_NAME_SIBLING.format(sha=SHA)
    sibling = whole_file_diff(
        gate, sibling_before, DASH_NAME_SIBLING.format(sha=OTHER_SHA)
    )
    properties = []
    for props in ("&body", "!!str"):
        props_before = ANCHORED_RUN.format(props=props, sha=SHA)
        props_after = ANCHORED_RUN.format(props=props, sha=OTHER_SHA)
        props_diff = whole_file_diff(gate, props_before, props_after)
        properties += [
            (
                f"a uses: line inside a `run: {props} |2-` block, whole file",
                REFUSE,
                props_before,
                props_diff,
            ),
            (
                f"a uses: line inside a `run: {props} |2-` block, from context",
                REFUSE,
                props_before,
                "".join(
                    line + "\n"
                    for line in props_diff.splitlines()
                    if not line.startswith("index ")
                ),
            ),
        ]
    for props in ("&step", "!!map"):
        step_before = PROPERTIES_ON_STEP.format(props=props, sha=SHA)
        properties.append(
            (
                f"a step's uses: beside `- {props} name: |` is its sibling",
                ACCEPT,
                step_before,
                whole_file_diff(
                    gate,
                    step_before,
                    PROPERTIES_ON_STEP.format(props=props, sha=OTHER_SHA),
                ),
            )
        )
    for props in ("&body", "!!str", ""):
        split_before = SPLIT_INDICATOR_RUN.format(props=props, sha=SHA)
        split = whole_file_diff(
            gate, split_before, SPLIT_INDICATOR_RUN.format(props=props, sha=OTHER_SHA)
        )
        properties += [
            (
                f"a uses: line under `run: {props}` then a lone `|`, whole file",
                REFUSE,
                split_before,
                split,
            ),
            (
                f"a uses: line under `run: {props}` then a lone `|`, from context",
                REFUSE,
                split_before,
                "".join(
                    line + "\n"
                    for line in split.splitlines()
                    if not line.startswith("index ")
                ),
            ),
        ]
    shapes = [
        (f"`{item}` then a lone `|`", SEQUENCE_ITEM_SPLIT, {"item": item})
        for item in ("- &body", "- !!str", "- run:")
    ] + [("a comment ending in `: |` above `run: &body |-`", COMMENT_BEFORE_OPENER, {})]
    for label, shape, fields in shapes:
        shape_before = shape.format(sha=SHA, **fields)
        properties.append(
            (
                f"a uses: line under {label}, whole file",
                REFUSE,
                shape_before,
                whole_file_diff(
                    gate, shape_before, shape.format(sha=OTHER_SHA, **fields)
                ),
            )
        )
    return properties + [
        (
            "a step's uses: beside a `- name: |` block is its sibling, not content",
            ACCEPT,
            sibling_before,
            sibling,
        ),
        (
            "a pin whose step name sits above a comment, judged from the whole file",
            ACCEPT,
            before,
            step,
        ),
        (
            "a uses: line nested deep inside a run: block, judged from the whole file",
            REFUSE,
            nested_before,
            nested,
        ),
        (
            "the #105 shape when main has moved the file, falling back to context",
            REFUSE,
            before + "# moved on main\n",
            step,
        ),
        (
            "a hunk whose context disagrees with the base, falling back to context",
            REFUSE,
            before,
            step.replace("shallower than it.", "else at all."),
        ),
        (
            "a hunk shorter than its header declares, falling back to context",
            REFUSE,
            before,
            "\n".join(step.splitlines()[:-1]) + "\n",
        ),
    ]


def main() -> int:
    gate = load_gate()
    failures = []

    for description, expected, text in CASES:
        actual = verdict(gate, text)
        if actual != expected:
            failures.append((description, expected, actual, text))

    for description, expected, base, text in whole_file_cases(gate):
        actual = whole_file_verdict(gate, base, text)
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

    print(
        f"pin-only-lint: {len(CASES) + len(whole_file_cases(gate))} diff shape(s) "
        "checked, all as recorded."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
