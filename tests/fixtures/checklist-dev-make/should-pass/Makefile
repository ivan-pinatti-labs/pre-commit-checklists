# Guards the constraint checklist-dev-make documents: checkmake reads only
# the first physical line of a .PHONY declaration. `t` below is bodyless and
# declared on the second .PHONY line, so it passes only while the one
# declaration per line convention holds. Rewrite the two .PHONY lines as a
# single backslash continuation and this fixture starts failing, which is
# exactly the regression the convention exists to prevent.
.PHONY: all build
.PHONY: test t

all: build test
	@echo done

build:
	@echo build

test:
	@echo test

t: test
