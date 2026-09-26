# Developing in containers

This repository is developed with
[devcontainer-airlock](https://github.com/ivan-pinatti-labs/devcontainer-airlock):
you and the coding agents work in a workbench that holds no GitHub token and
no ssh key, and every hook, the self-test suite and every package install
run in an L2 container that gets the working tree and nothing else. Its
[docs/LAYERS.md](https://github.com/ivan-pinatti-labs/devcontainer-airlock/blob/main/docs/LAYERS.md)
explains the layers and the one time setup on the host.

## Daily use

Clone devcontainer-airlock next to this repository's main clone (or point
`WORKBENCH_HOME` at a clone elsewhere), and the Makefile here gains its
targets:

```shell
make unlock          # the ssh key, for eight hours
make claude          # Claude Code in its workbench, started if needed
make codex           # Codex in its own workbench
make claude-shell    # a terminal in that workbench (or codex-shell)
```

Inside a workbench, `make install` routes the git hooks through L2
(`l2-hooks-install`), and `make run` and `make test` run the hooks and the
self-test suite there. In CI and on a plain host the same targets run them
directly, as before.

## What is in here

| File | What |
| --- | --- |
| `l2/Dockerfile` | This repository's L2 image, on the shared one pinned by digest: terraform, OpenTofu, tflint and detect-secrets, which the checklists and the self-test suite call by name. `l2` builds it in the L2 engine the first time and whenever it changes. |
| `keyrings/opentofu.asc` | OpenTofu's signing key, vendored and checked against its fingerprint before anything is verified with it. |
| `egress-sets` | The network services the egress proxy allows for this repository, one per line. |

Tools come from signed package repositories: `terraform` from HashiCorp's,
whose key the base image reviews against a fingerprint and installs without
enabling the repository, so the source entry in `l2/Dockerfile` is what opts
in.

`tofu` and `tflint` are the two exceptions, for different reasons. tflint is
packaged nowhere at all. OpenTofu does publish an apt repository, and it is
rejected on trust rather than availability: its index is signed by
packagecloud, the hosting provider, and not by OpenTofu, so the release
archive is the only path where the project itself vouches for the bytes.
Both install from a release archive verified against a signature the project
publishes: OpenTofu signs its `SHA256SUMS` with the GPG key vendored under
`keyrings/`, and tflint signs its checksums with cosign keyless, which binds
the signature to the GitHub Actions workflow that built it. Both
verifications fail the build rather than warning.

Package versions are deliberately unpinned, because Ubuntu and these vendors
ship security fixes by moving a version inside a release; the two release
downloads are pinned and Renovate moves them. The image digest pins what
this builds on, not what apt resolves on top.

**Run the hooks in L2, or in CI.** `terraform`, `tofu` and `tflint` live in
this repository's L2 image and nowhere else, so `pre-commit run` on the host
fails for those hooks.
