"""Keep every copy of "which Python this repository runs" in step.

The same fact is written down in several places, and none is derived from
another:

- `python-version` in .github/workflows/pull-request.yml, the interpreter the
  Pre-commit and Tests jobs run;
- `sonar.python.version` in sonar-project.properties, which SonarQube Cloud's
  version dependent Python rules judge tools/ and tests/ against;
- every python image the Makefile pins, today PYTHON_IMAGE, the interpreter
  `make coverage` (and so sonarqube.yml) runs the tests in;
- the `target-version` of the root ruff.toml, the Python ruff judges this
  repository's own code against;
- the consumer templates, templates/workflows/pull-request.yml and the
  `target-version` of templates/ruff.toml, which consumers copy as they are.

Nothing watches any of them automatically. .github/renovate.json5 disables
Renovate's `uses-with` depType and lets the Makefile images move by digest
only, so every Python bump is a hand edit of several files, the kind of
pairing a person forgets. This test is the reminder. It runs under
`make coverage` with the tests of tools/.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = REPO_ROOT / ".github/workflows/pull-request.yml"
TEMPLATE_WORKFLOW = REPO_ROOT / "templates/workflows/pull-request.yml"
SONAR_PROPERTIES = REPO_ROOT / "sonar-project.properties"
MAKEFILE = REPO_ROOT / "Makefile"
RUFF = REPO_ROOT / "ruff.toml"
TEMPLATE_RUFF = REPO_ROOT / "templates/ruff.toml"

# `python-version: "3.14"`, as actions/setup-python is given it. Quoted on
# purpose: YAML reads a bare 3.10 as the float 3.1, so an unquoted value is a
# bug worth failing on rather than a spelling to accept.
WORKFLOW_PYTHON = re.compile(r"^\s*python-version:\s*(?P<value>.*?)\s*$", re.MULTILINE)
QUOTED_VERSION = re.compile(r'^"(?P<major>\d+)\.(?P<minor>\d+)"$')

# `sonar.python.version=3.14`.
SONAR_PYTHON = re.compile(
    r"^sonar\.python\.version=(?P<major>\d+)\.(?P<minor>\d+)\s*$", re.MULTILINE
)

# Any `python:3.X-<variant>` image reference in the Makefile, pinned or not.
MAKEFILE_IMAGE = re.compile(r"\bpython:(?P<major>\d+)\.(?P<minor>\d+)-(?P<rest>\S+)")

# `target-version = "py314"`, at the top level of a ruff.toml.
RUFF_TARGET = re.compile(
    r'^target-version\s*=\s*"py(?P<major>\d)(?P<minor>\d+)"\s*$', re.MULTILINE
)


def workflow_versions(path: Path) -> list[tuple[str, str]]:
    """Every python-version in a workflow, failing on an unquoted one."""
    versions = []
    for value in WORKFLOW_PYTHON.findall(path.read_text(encoding="utf-8")):
        quoted = QUOTED_VERSION.match(value)
        assert quoted, f"{path.name} passes python-version {value}, not a quoted X.Y"
        versions.append((quoted.group("major"), quoted.group("minor")))
    return versions


def ci_version() -> tuple[str, str]:
    """The one interpreter CI runs, every job agreeing on it."""
    versions = set(workflow_versions(WORKFLOW))
    assert len(versions) == 1, (
        f"expected every job in {WORKFLOW.name} to set one python-version, "
        f"found {versions}"
    )
    return versions.pop()


def mismatch(where: str, found: tuple[str, str], ci: tuple[str, str]) -> str:
    return (
        f"{where} says Python {found[0]}.{found[1]} but {WORKFLOW.name} runs "
        f"Python {ci[0]}.{ci[1]}. They have to move together; nothing derives "
        "one from the other."
    )


def test_every_ci_job_runs_the_same_python():
    assert ci_version()


def test_sonar_python_version_matches_ci():
    ci = ci_version()
    sonar = SONAR_PYTHON.search(SONAR_PROPERTIES.read_text(encoding="utf-8"))
    assert sonar, f"no sonar.python.version in {SONAR_PROPERTIES.name}"
    found = (sonar.group("major"), sonar.group("minor"))
    assert found == ci, mismatch(SONAR_PROPERTIES.name, found, ci)


def test_every_makefile_python_image_matches_ci():
    ci = ci_version()
    images = MAKEFILE_IMAGE.findall(MAKEFILE.read_text(encoding="utf-8"))
    assert images, f"no python image pinned in {MAKEFILE.name}"
    for major, minor, rest in images:
        assert "@sha256:" in rest, (
            f"python:{major}.{minor}-{rest} is not pinned by digest"
        )
        assert (major, minor) == ci, mismatch(
            f"{MAKEFILE.name}'s python image", (major, minor), ci
        )


def test_template_workflow_matches_ci():
    ci = ci_version()
    versions = workflow_versions(TEMPLATE_WORKFLOW)
    assert versions, (
        f"no python-version in templates/workflows/{TEMPLATE_WORKFLOW.name}"
    )
    for found in versions:
        assert found == ci, mismatch(
            f"templates/workflows/{TEMPLATE_WORKFLOW.name}", found, ci
        )


def ruff_target(path: Path, where: str) -> tuple[str, str]:
    ruff = RUFF_TARGET.search(path.read_text(encoding="utf-8"))
    assert ruff, f"no target-version in {where}"
    return (ruff.group("major"), ruff.group("minor"))


def test_ruff_target_matches_ci():
    ci = ci_version()
    found = ruff_target(RUFF, RUFF.name)
    assert found == ci, mismatch(RUFF.name, found, ci)


def test_template_ruff_target_matches_ci():
    ci = ci_version()
    where = f"templates/{TEMPLATE_RUFF.name}"
    found = ruff_target(TEMPLATE_RUFF, where)
    assert found == ci, mismatch(where, found, ci)
