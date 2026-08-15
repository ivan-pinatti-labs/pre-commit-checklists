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
