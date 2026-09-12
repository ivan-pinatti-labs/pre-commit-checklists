# `shortcut` has no body and is not declared PHONY, so a file named
# `shortcut` appearing in the working tree would make make consider the
# target up to date and silently skip it. That is what phonydeclared is
# for, and it is the rule this checklist is worth adopting for.
.PHONY: all build

all: build
	@echo done

build:
	@echo build

shortcut: build
