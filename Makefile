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

# `make test` is the Python tests and then the rest of the self-test suite.
#
# test_python runs every Python test here (tests/tools/ under pytest, and the
# selectors phase of tests/run_tests.sh) in PYTHON_IMAGE, the image `make
# coverage` uses, so they run on one Python everywhere and never on the
# host's. The container is locked down the way the coverage one is (see
# below): the source arrives on standard input as a tar stream, nothing from
# the host is mounted, every capability is dropped, and it has the network
# only because pip installs the hash locked tests/requirements.txt in it.
#
# test_suite runs every other phase of tests/run_tests.sh. Those run the
# checklists themselves, so they need what tests/README.md lists (pre-commit,
# shellcheck, Node, terraform, tofu, tflint and a container engine for the
# image based linters), which this repository's L2 image carries and the
# Python image does not. In CI the Tests job runs the whole suite on the
# runner. The phase list comes from tests/run_tests.sh itself, so a new phase
# runs here without an edit.
#
# In a devcontainer-airlock workbench run this as `l2 --engine --net -- make
# test`: test_python needs the engine, and test_suite then runs in L2.
SUITE_PHASES := $(filter-out selectors,$(shell sed -n 's/^ALL_PHASES="\(.*\)"$$/\1/p' tests/run_tests.sh))

.PHONY: test
test: test_python test_suite

.PHONY: test_python
test_python:
	@echo "Running the Python tests in $(PYTHON_IMAGE)"
	@set -u; out="$$(mktemp -d)"; trap 'rm -rf "$$out"' EXIT; \
	$(_sources); \
	$(PODMAN) run <"$$out/src.tar" --rm --interactive $(_locked) \
		"$(PYTHON_IMAGE)" sh -c '$(_unpack); $(_pip_lock); rc=0; \
			python -m pytest tests/tools -q -p no:cacheprovider || rc=1; \
			python tests/scripts/test_selector_lint.py || rc=1; \
			exit $$rc'
	@echo "Python tests successful"

.PHONY: test_suite
test_suite:
	@echo "Running the tests/ self-test suite: $(SUITE_PHASES)"
	@$(L2_NET) tests/run_tests.sh $(SUITE_PHASES)
	@echo "Self-test suite successful"

# Coverage of everything this repository writes as code, held at 100%: the
# shell scripts (lines; kcov reports no branches for bash) and the
# Python under tools/ (lines and branches, .coveragerc). Writes the two
# reports SonarQube Cloud reads, $(COVERAGE_DIR)/shell.xml and
# $(COVERAGE_DIR)/coverage.xml, and fails if either is under 100%.
# .github/workflows/sonarqube.yml runs this, and so does the `coverage`
# pre-push hook.
#
# The shell is measured by tests/scripts/script_units.sh (the `units` phase
# of tests/run_tests.sh), which stubs every command the scripts call out to,
# not by the rest of the self-test suite: that needs Docker, the network and
# every checklist's tools, none of which this locked down container has.
# Every shell script SHELL_SCRIPTS discovers (below) is held to it, so a new
# script fails here until a case there runs each of its lines.
#
# Both tools run in containers that cannot see this checkout. The files git
# would commit (tracked, plus new ones not ignored) go in on standard input
# as a tar stream, and the only host path either container gets is an empty
# scratch directory for its report. Nothing else is mounted: no home
# directory, no SSH agent, no token, and podman passes no environment
# variable that is not named. Both drop every capability; kcov also gets no
# network and a read only root filesystem. The Python container needs the
# network for its pip install. The images are pinned by digest, and Renovate
# moves the digests.
#
# The scratch directory comes from mktemp, so it lands in TMPDIR. In a
# devcontainer-airlock workbench run this as `l2 --engine --net -- make
# coverage`: the engine can only mount paths under the TMPDIR it sets.
#
# Both reports are written before either verdict is given, so CI can still
# hand SonarQube the report of a run that falls short.
COVERAGE_DIR ?= coverage
PODMAN ?= $(if $(CONTAINER_HOST),podman-remote,podman)
# renovate: datasource=docker depName=docker.io/library/python
PYTHON_IMAGE ?= docker.io/library/python:3.14-slim@sha256:c3e521df8b2b498a7a682e7e18676771cb80c6b75b8699af886b2d554ce40151
# renovate: datasource=docker depName=docker.io/kcov/kcov
KCOV_IMAGE ?= docker.io/kcov/kcov:latest@sha256:481289ae32e55e5b733019515acd10948a4f76dfed381765577db909664fc603
# The shell scripts measured, found rather than listed: every file git would
# commit (tracked, plus new ones not ignored) that ends in .sh or .bash, or
# whose first line is a shebang running sh, bash or dash (any interpreter
# path, env with or without options). Anything under tests/ is the tests, not
# the code under test, and stays out. Only regular files reach awk: mawk
# (Debian's and Ubuntu's awk) exits at the first file it cannot open and
# drops every file after it, so a path deleted in the working tree is
# filtered out first, not left to awk. Nothing else trims or extends the set:
# SHELL_EXCLUDE names vendored or third party shell, each with its reason,
# and SHELL_EXTRA names shell files neither the extension nor a shebang
# identifies. Both are empty today. `make print-shell-scripts` prints the set.
# tests/tools/test_shell_discovery.py holds this rule in place.
SHELL_EXCLUDE :=
SHELL_EXTRA :=
# A script name outside [A-Za-z0-9._/+-] would reach the recipes as shell text
# (a committed `x;id;#.sh` would run `id`), so discovery marks it UNSAFE: and
# make stops here instead.
_shell_safe = $(if $(filter UNSAFE:,$(1)),$(error a shell script name holds a character outside A-Za-z0-9._/+-; rename it),$(1))
SHELL_SCRIPTS := $(call _shell_safe,$(sort $(filter-out $(SHELL_EXCLUDE),$(shell git ls-files -z --cached --others --exclude-standard | xargs -0 sh -c 'for f do if [ -f "$$f" ]; then printf "%s\0" "$$f"; fi; done' sh | xargs -0 awk 'FNR == 1 { if (FILENAME ~ /\.(sh|bash)$$/ || $$0 ~ /^#![[:space:]]*([^[:space:]]*\/)?(env[[:space:]]+(-[^[:space:]]+[[:space:]]+)*)?(ba|da)?sh([[:space:]]|$$)/) print (FILENAME ~ /^[A-Za-z0-9._\/+-]+$$/ ? FILENAME : "UNSAFE:"); nextfile }' 2>/dev/null | grep -v '^tests/')) $(SHELL_EXTRA)))

.PHONY: print-shell-scripts
print-shell-scripts:
	@printf '%s\n' $(SHELL_SCRIPTS)

_comma := ,
_empty :=
_space := $(_empty) $(_empty)
# Builds $$out/src.tar: the files git would commit (tracked, plus new ones
# not ignored), minus any deleted in the working tree, each step checked,
# so the containers never measure a partial tree.
_sources := git ls-files -z --cached --others --exclude-standard --deduplicate \
		>"$$out/all" || exit 1; \
	xargs -0 sh -c 'for f do if [ -e "$$f" ] || [ -L "$$f" ]; then printf "%s\0" "$$f"; fi; done' sh \
		<"$$out/all" >"$$out/list" || exit 1; \
	tar --create --owner=0 --group=0 --numeric-owner --null --files-from="$$out/list" --file="$$out/src.tar" || exit 1
_unpack := set -e; mkdir /tmp/w; tar -x --no-same-owner -C /tmp/w; cd /tmp/w
_locked := --cap-drop=ALL --security-opt no-new-privileges
_pip_lock := pip install --quiet --disable-pip-version-check --root-user-action=ignore \
	--require-hashes --only-binary=:all: -r tests/requirements.txt

.PHONY: coverage
coverage:
	@set -u; out="$$(mktemp -d)"; trap 'rm -rf "$$out"' EXIT; \
	$(_sources); \
	mkdir "$$out/python" "$$out/shell"; py=0; sh=0; \
	$(PODMAN) run <"$$out/src.tar" --rm --interactive $(_locked) \
		--network=none --read-only --tmpfs /tmp \
		-v "$$out/shell:/out:rw,Z" "$(KCOV_IMAGE)" sh -c '$(_unpack); \
			kcov --include-path=$(subst $(_space),$(_comma),$(addprefix /tmp/w/,$(SHELL_SCRIPTS))) \
				/out/kcov tests/scripts/script_units.sh; \
			python3 tools/kcov_to_sonar.py /tmp/w /out/kcov/script_units.sh.*/cobertura.xml \
				/out/shell.xml $(SHELL_SCRIPTS)' || sh=$$?; \
	$(PODMAN) run <"$$out/src.tar" --rm --interactive $(_locked) \
		-v "$$out/python:/out:rw,Z" "$(PYTHON_IMAGE)" sh -c '$(_unpack); \
			$(_pip_lock); \
			coverage run -m pytest tests/tools -q -p no:cacheprovider; \
			coverage xml -q --fail-under=0 -o /out/coverage.xml; \
			coverage report' || py=$$?; \
	mkdir -p "$(COVERAGE_DIR)" && rm -f "$(COVERAGE_DIR)/coverage.xml" "$(COVERAGE_DIR)/shell.xml" || exit 1; \
	for report in "$$out/python/coverage.xml" "$$out/shell/shell.xml"; do \
		if [ -f "$$report" ]; then cp "$$report" "$(COVERAGE_DIR)"/ || exit 1; fi; \
	done; \
	test "$$py" -eq 0 && test "$$sh" -eq 0 && \
		test -s "$(COVERAGE_DIR)/coverage.xml" && test -s "$(COVERAGE_DIR)/shell.xml"

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
