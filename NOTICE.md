# Notice

pre-commit-checklists
Copyright 2026 Ivan Pinatti
<https://github.com/ivan-pinatti-labs/pre-commit-checklists>

This product is licensed under the Apache License, Version 2.0. See
[LICENSE.md](LICENSE.md) for the full terms.

## Scope

The checklists under [checklists/](checklists/) are curated selections of
public upstream pre-commit hooks: each file lists a `repo:` and `rev:` pin
for a project such as `pre-commit/pre-commit-hooks`, `astral-sh/ruff-pre-commit`,
or `Yelp/detect-secrets`. Nothing from those upstream projects is vendored or
copied into this repository; pre-commit clones each pinned hook repository
itself at run time, under that project's own license. This NOTICE does not
relicense, and is not needed to cover, code this repository never contains.
