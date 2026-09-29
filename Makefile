TOIT ?= $(if $(shell command -v toit),toit,jag toit)
TESTS := $(wildcard tests/*-test.toit)

all: test analyze

install-pkgs:
	$(TOIT) pkg install --project-root=tests
	$(TOIT) pkg install --project-root=examples

test: install-pkgs
	@for test in $(TESTS); do \
	  echo "--- $$test"; \
	  $(TOIT) $$test || exit 1; \
	done

# Each directory is its own package root, so they analyze separately.
analyze: install-pkgs
	@for file in src/*.toit examples/*.toit $(TESTS); do \
	  $(TOIT) analyze $$file || exit 1; \
	done

.PHONY: all install-pkgs test analyze
