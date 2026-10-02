# Security Vulnerabilities

Please report through the GitHub Report Security Issues page:
<https://github.com/ivan-pinatti-labs/pre-commit-checklists/security/advisories/new>

## What scans what

| Code | Scanned by | Where |
| --- | --- | --- |
| `scripts/*.sh`, `tests/**/*.sh` | shellcheck, shfmt, shebang checks | `checklist-dev-shell`, every commit |
| Python under `tools/` and `tests/` | ruff (with the flake8-bandit security rules), check-ast, debug-statements | `checklist-dev-python`, every commit |
| `.devcontainer/l2/Dockerfile` | hadolint | `checklist-dev-docker`, every commit |
| `.github/workflows/*` | actionlint, zizmor | `checklist-github-actions`, every commit |
| Everything | detect-secrets | `checklist-security-credentials`, every commit |
| Everything SonarQube Cloud has an analyzer for: shell, Python, the `Dockerfile`, YAML, `.github/workflows/*`, secrets | SonarQube Cloud, Sonar way quality gate, plus 100% coverage of `scripts/*.sh` and `tools/` | `sonarqube.yml`, every pull request targeting `main` from a branch of this repository and every push to `main` |

Two layers, deliberately. The pre-commit hooks fail before anything is
pushed; SonarQube Cloud reads the whole repository at once on every pull
request targeting `main` from a branch of this repository (a fork's pull request cannot
receive its token, so a maintainer pushes the branch here first). Neither
replaces the other: SonarQube's shell rules are few and different from
shellcheck's, not a superset of them. The test fixtures under
`tests/fixtures/` are left out of the analysis, because the should-fail ones
are defective on purpose.

SonarQube Cloud replaced CodeQL here, both `codeql.yml` and the
GitHub-managed Code Quality setup. CodeQL only ever analyzed the Python, and
it cannot read shell or a `Dockerfile` at all. Its old alerts in the Security
tab stop updating; they are history, not current findings.

The quality gate is the Free plan's built-in "Sonar way", which cannot be
edited. It judges new code only, and fails the pull request when that new
code:

- is rated below A for reliability or security, which any new bug or any new
  vulnerability does;
- is rated below A for maintainability, which code smells do only once their
  estimated fix effort passes the A threshold (a technical debt ratio of 5%),
  not one by one;
- adds a security hotspot nobody has reviewed in SonarQube Cloud;
- duplicates more than 3% of its lines; or
- has less than 80% of its lines covered.

This repository holds its own code above that floor: `make coverage`, run by
the same job, requires 100% of every `scripts/*.sh` and 100% of the lines and
branches under `tools/`, and fails the job otherwise. Fix what a rule asks
for, or mark the single finding false positive or accepted in SonarQube Cloud
with the reason; no `# NOSONAR` comments.

The library also ships a copy of this setup for its consumers,
[`templates/workflows/sonarqube.yml`](../templates/workflows/sonarqube.yml),
next to the CodeQL alternative; see
[`docs/hook-catalogue.md`](hook-catalogue.md#what-this-does-not-cover).
