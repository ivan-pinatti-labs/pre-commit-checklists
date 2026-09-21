CHECKLIST_FILES := $(shell find checklists -maxdepth 1 -type f \( -name 'checklist-*.yaml' -o -name 'checklist-*.yml' \))

.PHONY: all
all: uninstall install run

.PHONY: autoupdate_and_run
autoupdate_and_run: autoupdate_checklists autoupdate run

.PHONY: autoupdate
autoupdate:
	@echo "Running pre-commit autoupdate"
	@pre-commit autoupdate --config .pre-commit-config.yaml
	@echo "Pre-commit autoupdate successful"

.PHONY: autoupdate_checklists
autoupdate_checklists: $(CHECKLIST_FILES)
	@for file in $(CHECKLIST_FILES); do \
		echo "Running pre-commit autoupdate for $$file"; \
		pre-commit autoupdate --config $$file; \
	done
	@echo "Checklist autoupdate successful"

.PHONY: uninstall
uninstall:
	@echo "Running pre-commit uninstall"
	@pre-commit uninstall
	@echo "Pre-commit hooks uninstall successful"

.PHONY: install
install:
	@echo "Running pre-commit install"
	@pre-commit install
	@echo "Pre-commit hooks install successful"

.PHONY: run
run: run_pre_commit run_pre_push

.PHONY: run_pre_commit
run_pre_commit:
	@echo "Running pre-commit, pre-commit stage, against all files"
	@pre-commit run --all-files --config .pre-commit-config.yaml --hook-stage pre-commit --verbose
	@echo "Pre-commit run successful"

.PHONY: run_pre_push
run_pre_push:
	@echo "Running pre-commit, pre-push stage, against all files"
	@pre-commit run --all-files --config .pre-commit-config.yaml --hook-stage pre-push --verbose
	@echo "Pre-commit run successful"

.PHONY: test
test:
	@echo "Running the tests/ self-test suite"
	@tests/run_tests.sh
	@echo "Self-test suite successful"

# A shell inside the development container, without an editor in the loop.
#
# The flags mirror .devcontainer/devcontainer.json's runArgs, deliberately
# and by hand: a devcontainer.json is read by editors and by the devcontainer
# CLI, neither of which is involved here, so the two lists have to be kept in
# step. Anything added there that this target needs belongs here too.
#
# container_engine_t and /dev/fuse are what let the nested runtime work under
# SELinux, for the hooks that start containers of their own (hadolint-docker,
# actionlint-docker). See docs/IMAGES.md in
# ivan-pinatti-labs/devcontainer-images, under "Running containers inside it".
#
# This target matters more here than in the sibling repositories. The
# terraform, tofu and tflint hooks run binaries that live in this container
# and nowhere else, so `pre-commit run` on a host without them fails. On a
# host that still has asdf the failure is "No version is set for command
# tflint", because nothing pins it any more. Run the hooks in here, or in CI.
#
# The two agent directories are bind mounted from the host so Claude Code and
# Codex read and write the same sessions, transcripts and credentials whether
# they run in here or on the host, and so none of it is lost when the
# container exits.
#
# Lowercase z on those two, uppercase Z on the working tree. Z labels a mount
# private to a single container, which is right for a working tree this
# container alone uses. The agent directories are used by the host's own
# agents and by every other repository's development container, so labelling
# them private would take them away from all of those.
#
# SHELL_EXTRA_MOUNTS exists because a bind mount carries a symlink across as
# a symlink. Anything under ~/.claude or ~/.codex pointing outside those
# directories dangles in here until its target is mounted too:
#
#   make shell SHELL_EXTRA_MOUNTS='-v /path/on/host:/path/on/host:rw,z'
DEV_IMAGE ?= pre-commit-checklists-dev
SHELL_EXTRA_MOUNTS ?=

# GH_TOKEN by the mechanism devcontainer.json uses where that is available,
# and by the ordinary environment where it is not. `--secret` naming a secret
# that does not exist aborts the run rather than degrading, so hard coding it
# would break this target on every machine that has not run
# `podman secret create gh-devcontainer`. The environment fallback stays
# conditional on GH_TOKEN being non-empty, because `-e GH_TOKEN` with nothing
# set exports an empty one, which gh treats as a token and fails on.
_comma := ,
_shell_gh_secret := $(shell podman secret exists gh-devcontainer >/dev/null 2>&1 && echo present)
_shell_gh_token := $(if $(_shell_gh_secret),\
--secret=gh-devcontainer$(_comma)type=env$(_comma)target=GH_TOKEN,\
$(if $(GH_TOKEN),-e GH_TOKEN,))

# The ssh-agent socket the devcontainer expects, mounted only if the host has
# one. Without it the container simply has no agent, which is a working shell
# with no git-over-ssh rather than a container that refuses to start.
_shell_ssh_dir := $(XDG_RUNTIME_DIR)/devcontainer-ssh
_shell_ssh := $(if $(wildcard $(_shell_ssh_dir)),\
-v "$(_shell_ssh_dir):/run/devcontainer-ssh:rw,z" \
-e SSH_AUTH_SOCK=/run/devcontainer-ssh/agent.sock \
-e GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/run/devcontainer-ssh/known_hosts -o StrictHostKeyChecking=yes",)

.PHONY: shell
shell:
	@echo "Building the development container..."
	@podman build --file .devcontainer/Dockerfile --tag $(DEV_IMAGE) .
	@mkdir -p "$(HOME)/.claude" "$(HOME)/.codex"
	@echo "Entering $(DEV_IMAGE). Type exit to leave."
	@podman run --rm --interactive --tty \
		--userns=keep-id:uid=1000,gid=1000 \
		--security-opt label=type:container_engine_t \
		--security-opt label=level:s0:c555,c666 \
		--device /dev/fuse \
		-v "$(CURDIR):$(CURDIR):rw,Z" \
		-v "$(HOME)/.claude:/home/dev/.claude:rw,z" \
		-v "$(HOME)/.codex:/home/dev/.codex:rw,z" \
		$(_shell_ssh) \
		$(_shell_gh_token) \
		$(SHELL_EXTRA_MOUNTS) \
		--workdir "$(CURDIR)" \
		$(DEV_IMAGE) bash
