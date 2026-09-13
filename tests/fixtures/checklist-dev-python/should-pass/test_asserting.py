"""Guards the S101 exemption in checklist-dev-python.yaml.

A should-pass fixture whose whole job is to contain a bare `assert`. Without
`--extend-per-file-ignores`, ruff reports S101 here, this fixture stops
passing, and the suite goes red. That is what keeps the exemption honest, and
what the security floor test asserts by name.

Named `test_*.py` rather than `*_test.py` deliberately. The same checklist runs
`name-tests-test --django`, which requires `test*.py` for anything under
`tests/`, so a `*_test.py` fixture cannot live here at all. The `*_test.py`
entry in the exemption list is for a file sitting beside the module it tests,
outside any `tests/` directory, which is a path `name-tests-test` never sees.
"""


def test_addition_holds() -> None:
    """S101 territory: a bare assert, which is the entire point of a test."""
    assert 1 + 1 == 2
