#!/usr/bin/env python3
"""Phase 4 (static): guard against the defect-2/3 AND-selector mistake.

Read-only. Scans .pre-commit-hooks.yaml, checklists/*.yaml, and
templates/pre-commit-config/*.yaml for any hook entry that combines a
types:/types_or: key with a files: key on the same hook. pre-commit ANDs
those two keys together rather than ORing them, which is exactly how
defects 2 and 3 happened: a hook meant to match "python files OR
requirements.txt" ends up matching "python files named requirements.txt"
(nothing), and a hook meant to match ".env files" ends up requiring them
to also be typed json (nothing).

This script never writes to the files it scans; it is a lint, not a
fixer, and the files it reads belong to other parts of this build.

Exit 0: no hook combines types/types_or with files.
Exit 1: at least one does; each is printed with its source file and hook id.
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]

TARGETS = [
    REPO_ROOT / ".pre-commit-hooks.yaml",
    *sorted((REPO_ROOT / "checklists").glob("*.yaml")),
    *sorted((REPO_ROOT / "templates" / "pre-commit-config").glob("*.yaml")),
]


def hooks_in(doc) -> list[dict]:
    """Return every hook mapping in a parsed pre-commit-style YAML doc.

    Handles both the top-level-list shape used by .pre-commit-hooks.yaml
    and the repos:/hooks: shape used by checklist and template files.
    """
    if isinstance(doc, list):
        return [h for h in doc if isinstance(h, dict)]
    if isinstance(doc, dict):
        out = []
        for repo in doc.get("repos", []) or []:
            for hook in repo.get("hooks", []) or []:
                if isinstance(hook, dict):
                    out.append(hook)
        return out
    return []


def main() -> int:
    violations = []
    for path in TARGETS:
        if not path.exists():
            continue
        text = path.read_text()
        try:
            doc = yaml.safe_load(text)
        except yaml.YAMLError as exc:
            print(f"selector-lint: could not parse {path}: {exc}", file=sys.stderr)
            return 1
        for hook in hooks_in(doc):
            has_types = "types" in hook or "types_or" in hook
            has_files = "files" in hook
            if has_types and has_files:
                violations.append(
                    (
                        path.relative_to(REPO_ROOT),
                        hook.get("id", "<no id>"),
                        {
                            k: hook[k]
                            for k in ("types", "types_or", "files")
                            if k in hook
                        },
                    )
                )

    if violations:
        print("selector-lint: found hook(s) combining types/types_or with files.")
        print("pre-commit ANDs these together; this is the defect-2/3 shape.")
        print()
        for path, hook_id, keys in violations:
            print(f"  {path}: id={hook_id} {keys}")
        return 1

    print(
        f"selector-lint: checked {len(TARGETS)} file(s), no types/types_or + files combinations found."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
