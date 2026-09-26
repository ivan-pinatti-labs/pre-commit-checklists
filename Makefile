CHECKLIST_FILES := $(shell find checklists -maxdepth 1 -type f \( -name 'checklist-*.yaml' -o -name 'checklist-*.yml' \))

# Inside a devcontainer-airlock workbench, the hooks and the self-test suite
# run in L2, with the working tree and nothing else; `l2 --net` adds network
# through the egress proxy for the steps that fetch. In CI and on a plain host
# there is no l2, and every target runs as it always has.
IN_WORKBENCH := $(shell command -v l2 2>/dev/null)
PRE_COMMIT := $(if $(IN_WORKBENCH),l2-pre-commit,pre-commit)
L2 := $(if $(IN_WORKBENCH),l2 --,)
L2_NET := $(if $(IN_WORKBENCH),l2 --net --,)

.PHONY: all
all: uninstall install run

.PHONY: autoupdate_and_run
autoupdate_and_run: autoupdate_checklists autoupdate run

.PHONY: autoupdate
autoupdate:
	@echo "Running pre-commit autoupdate"
	@$(L2_NET) pre-commit autoupdate --config .pre-commit-config.yaml
	@echo "Pre-commit autoupdate successful"

.PHONY: autoupdate_checklists
autoupdate_checklists: $(CHECKLIST_FILES)
	@for file in $(CHECKLIST_FILES); do \
		echo "Running pre-commit autoupdate for $$file"; \
		$(L2_NET) pre-commit autoupdate --config $$file; \
	done
	@echo "Checklist autoupdate successful"

.PHONY: uninstall
uninstall:
	@echo "Running pre-commit uninstall"
	@$(if $(IN_WORKBENCH),echo 'In a workbench the hooks are l2-hooks-install shims; make install rewrites them',pre-commit uninstall)
	@echo "Pre-commit hooks uninstall successful"

.PHONY: install
install:
	@echo "Running pre-commit install"
	@$(if $(IN_WORKBENCH),l2-hooks-install,pre-commit install)
	@echo "Pre-commit hooks install successful"

.PHONY: run
run: run_pre_commit run_pre_push

.PHONY: run_pre_commit
run_pre_commit:
	@echo "Running pre-commit, pre-commit stage, against all files"
	@$(PRE_COMMIT) run --all-files --config .pre-commit-config.yaml --hook-stage pre-commit --verbose
	@echo "Pre-commit run successful"

.PHONY: run_pre_push
run_pre_push:
	@echo "Running pre-commit, pre-push stage, against all files"
	@$(PRE_COMMIT) run --all-files --config .pre-commit-config.yaml --hook-stage pre-push --verbose
	@echo "Pre-commit run successful"

.PHONY: test
test:
	@echo "Running the tests/ self-test suite"
	@$(L2_NET) tests/run_tests.sh
	@echo "Self-test suite successful"

# The workbench targets (make claude, make codex, make unlock and the rest)
# come from a devcontainer-airlock clone, by default the one next to this
# repository's main clone, so every worktree finds the same one. See
# .devcontainer/README.md.
WORKBENCH_HOME ?= $(abspath $(dir $(shell git rev-parse --path-format=absolute --git-common-dir 2>/dev/null))../devcontainer-airlock)
-include $(WORKBENCH_HOME)/host/workbench.mk

.PHONY: workbench-help
ifeq ($(wildcard $(WORKBENCH_HOME)/host/workbench.mk),)
workbench-help:
	@printf '%s\n' \
		'Workbench: no devcontainer-airlock clone at $(WORKBENCH_HOME).' \
		'  Clone ivan-pinatti-labs/devcontainer-airlock there, or set WORKBENCH_HOME,' \
		'  for make claude, make codex, make unlock and the rest (.devcontainer/README.md).'
endif
