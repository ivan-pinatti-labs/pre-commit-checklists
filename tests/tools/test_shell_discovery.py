"""Hold the Makefile's shell script discovery in place.

`make coverage` measures the shell scripts SHELL_SCRIPTS finds, not a list
someone keeps by hand: every file git would commit that ends in .sh or .bash,
or whose first line is a shebang running sh, bash or dash, minus anything
under tests/ and minus SHELL_EXCLUDE, plus SHELL_EXTRA. A hand list only ever
falls behind, and a script it misses is a script nobody measures.

These tests run where `make coverage` runs them, in a container that gets the
committable files as a tar stream and has neither .git nor git. So they apply
the same rule in Python, to the tree, reading the two patterns straight out of
the Makefile's awk program so the two cannot disagree.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
MAKEFILE = REPO_ROOT / "Makefile"
PRE_COMMIT_CONFIG = REPO_ROOT / ".pre-commit-config.yaml"
SONAR_PROPERTIES = REPO_ROOT / "sonar-project.properties"

# The scripts this repository is known to have. Discovery has to find at
# least these; a new one is found without being added here.
KNOWN_SCRIPTS = {
    "scripts/check-branch-name.sh",
    "scripts/check-commit-msg.sh",
    "scripts/install.sh",
    "scripts/run-checklist.sh",
}

# The pieces of the SHELL_SCRIPTS line that make it discovery rather than a
# list: git's view of the files, the drop of paths deleted in the working
# tree, the awk rule, the tests/ exclusion and the two explicit lists.
DISCOVERY_PARTS = (
    "git ls-files -z --cached --others --exclude-standard",
    """if [ -f "$$f" ]""",
    "xargs -0 awk 'FNR == 1 {",
    "nextfile",
    "grep -v '^tests/'",
    "$(filter-out $(SHELL_EXCLUDE),",
    "$(SHELL_EXTRA)",
)

# Directories .gitignore keeps out of a commit, so a checkout with git
# matches what the coverage container sees.
SKIPPED_DIRECTORIES = {".git", ".venv", "venv", "node_modules", ".terraform"}
SKIPPED_PATHS = {".claude/worktrees", ".claude/agents/local", "coverage"}

AWK_REGEX = r"/((?:\\.|[^/\\])*)/"


def makefile_variable(name: str) -> str:
    """The value of a `NAME := value` line in the Makefile."""
    match = re.search(
        rf"^{name} :=(?P<value>.*)$", MAKEFILE.read_text(encoding="utf-8"), re.MULTILINE
    )
    assert match, f"no `{name} :=` line in {MAKEFILE.name}"
    return match.group("value").strip()


def awk_to_python(pattern: str) -> re.Pattern[str]:
    """An awk ERE from the Makefile, as a Python pattern."""
    pattern = pattern.replace("$$", "$").replace("\\/", "/")
    pattern = pattern.replace("[^[:space:]]", r"[^\s]").replace("[[:space:]]", r"\s")
    return re.compile(pattern)


def discovery_patterns() -> tuple[re.Pattern[str], re.Pattern[str]]:
    """The file name and first line patterns of the Makefile's awk rule."""
    line = makefile_variable("SHELL_SCRIPTS")
    name = re.search(r"FILENAME ~ " + AWK_REGEX + r" \|\| \$\$0", line)
    shebang = re.search(r"\$\$0 ~ " + AWK_REGEX, line)
    assert name, "SHELL_SCRIPTS no longer matches FILENAME against a pattern"
    assert shebang, "SHELL_SCRIPTS no longer matches the first line against a pattern"
    return awk_to_python(name.group(1)), awk_to_python(shebang.group(1))


def committable_files() -> list[str]:
    """Every file in the tree, minus .git and what .gitignore keeps out of it.

    Under `make coverage` the tree is exactly what git would commit, since
    that is all the tar stream carries. Elsewhere the skipped directories are
    the ones .gitignore names that could hold a shell script.
    """
    found = []
    for directory, subdirectories, files in os.walk(REPO_ROOT):
        here = Path(directory).relative_to(REPO_ROOT).as_posix()
        subdirectories[:] = [
            d
            for d in subdirectories
            if d not in SKIPPED_DIRECTORIES
            and f"{here}/{d}".removeprefix("./") not in SKIPPED_PATHS
        ]
        for file in files:
            found.append((Path(directory) / file).relative_to(REPO_ROOT).as_posix())
    return found


def first_line(path: Path) -> str | None:
    """The first line as awk reads it, or None for an empty file."""
    with path.open("rb") as handle:
        line = handle.readline()
    if not line:
        return None
    return line.decode("utf-8", errors="replace").rstrip("\n")


def discovered() -> set[str]:
    """SHELL_SCRIPTS, worked out the way the Makefile works it out."""
    name, shebang = discovery_patterns()
    exclude = set(makefile_variable("SHELL_EXCLUDE").split())
    extra = set(makefile_variable("SHELL_EXTRA").split())
    found = set()
    for relative in committable_files():
        path = REPO_ROOT / relative
        if not path.is_file():
            continue
        line = first_line(path)
        if line is None:
            continue
        if name.search(relative) or shebang.search(line):
            found.add(relative)
    found = {path for path in found if not path.startswith("tests/")}
    return (found - exclude) | extra


def test_makefile_discovers_rather_than_lists():
    line = makefile_variable("SHELL_SCRIPTS")
    for part in DISCOVERY_PARTS:
        assert part in line, (
            f"SHELL_SCRIPTS in {MAKEFILE.name} lost `{part}`; the scripts "
            "coverage measures are discovered, not listed by hand"
        )
    assert "wildcard" not in line, "SHELL_SCRIPTS is back to a hand list"


@pytest.mark.parametrize(
    ("path", "line", "expected"),
    [
        ("a.sh", "echo", True),
        ("a.bash", "", True),
        ("bin/tool", "#!/bin/sh", True),
        ("bin/tool", "#!/bin/bash -e", True),
        ("bin/tool", "#! /usr/bin/dash", True),
        ("bin/tool", "#!/usr/bin/env bash", True),
        ("bin/tool", "#!/usr/bin/env -S bash -e", True),
        ("bin/tool", "#!/usr/bin/env python3", False),
        ("bin/tool", "#!/bin/zsh", False),
        ("bin/tool", "#!/usr/bin/bashful", False),
        ("a.shx", "echo", False),
        ("README.md", "# bash", False),
    ],
)
def test_rule_classifies_by_extension_or_shebang(path, line, expected):
    name, shebang = discovery_patterns()
    assert bool(name.search(path) or shebang.search(line)) is expected


def test_discovers_the_known_scripts():
    missing = KNOWN_SCRIPTS - discovered()
    assert not missing, f"discovery no longer finds {sorted(missing)}"


def test_discovers_nothing_under_tests():
    assert not {path for path in discovered() if path.startswith("tests/")}


def test_coverage_hook_runs_for_every_discovered_script():
    config = yaml.safe_load(PRE_COMMIT_CONFIG.read_text(encoding="utf-8"))
    hooks = [
        hook
        for repo in config["repos"]
        for hook in repo["hooks"]
        if hook["id"] == "coverage"
    ]
    assert len(hooks) == 1, "expected one `coverage` hook"
    files = re.compile(hooks[0]["files"])
    unmatched = sorted(path for path in discovered() if not files.search(path))
    assert not unmatched, (
        f"the coverage hook's files: does not match {unmatched}, so a change "
        "to them would not run make coverage before a push"
    )


def test_sonar_knows_every_script_without_an_extension():
    """SonarQube Cloud picks a file's language by its extension alone.

    A script found by its shebang but named without .sh or .bash is not
    analyzed as shell, and its coverage goes nowhere, unless
    sonar.lang.patterns.shell names it.
    """
    bare = sorted(path for path in discovered() if "." not in Path(path).name)
    if not bare:
        return
    match = re.search(
        r"^sonar\.lang\.patterns\.shell=(?P<value>.*)$",
        SONAR_PROPERTIES.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    listed = set(match.group("value").split(",")) if match else set()
    missing = [path for path in bare if path not in listed]
    assert not missing, (
        f"{missing} have no extension, so {SONAR_PROPERTIES.name} has to list "
        "them in sonar.lang.patterns.shell"
    )


def test_discovery_refuses_unsafe_script_names():
    """A script name reaches make's recipes as shell text, so discovery has to
    refuse any name outside [A-Za-z0-9._/+-] (a committed `x;id;#.sh` would
    otherwise run `id`)."""
    here = Path(__file__).resolve().parent
    while not (here / "Makefile").is_file():
        here = here.parent
    text = (here / "Makefile").read_text()
    assert "_shell_safe = $(if $(filter UNSAFE:," in text
    assert "$(call _shell_safe," in text
    assert '? FILENAME : "UNSAFE:")' in text
