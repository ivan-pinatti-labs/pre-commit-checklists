"""Trips flake8-bandit, which ruff only runs because the checklist asks for it.

Guards the security floor in checklist-dev-python.yaml. Under ruff's default
selection (E4, E7, E9, F) this file is clean: the import is used, nothing is
undefined, the formatting is fine. It fails only while --extend-select S is
present, so deleting that flag turns this fixture green and the suite red,
which is the point of it.
"""

import subprocess


def run_untrusted(command: str) -> int:
    """S602: subprocess call with shell=True."""
    return subprocess.call(command, shell=True)
