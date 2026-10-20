# Build, check and test commands for this host.native Loup application.
#
# On Linux x86-64 `loup` is the self-hosted driver and `loup-bootstrap` is
# Stage0. This project uses Stage0 for everything: `check`, the native build
# (the self-hosted builder refuses an `asm` block with several outputs, such
# as CPUID's four registers) and the tests, which Stage0 builds and runs as
# native binaries because they are host.native files.

APP            ?= cpuid
LOUP           ?= loup
LOUP_BOOTSTRAP ?= loup-bootstrap
BUILD_DIR      ?= build
BIN            := $(BUILD_DIR)/$(APP)
SOURCES        := package.lppkg $(shell find source -name '*.lphc')
ARGS           ?=
TEST_ARGS      ?=

.PHONY: all run check test build e2e ci clean

all: build

# `loup run` cannot execute inline asm, so `run` builds the binary and runs
# it, e.g. `make run ARGS="--features"`.
run: $(BIN)
	$(BIN) $(ARGS)

# Type-check source/main.lphc and every module it imports.
check:
	$(LOUP_BOOTSTRAP) check --no-color

# Each test_* function becomes its own native binary (about a second each).
# The generated test package lives in a temporary directory, so LOUPPATH
# must be absolute: source/ for the program's modules, tests/ for the
# shared sample snapshots. Narrow the run with TEST_ARGS, e.g.
# `make test TEST_ARGS="--filter amd"`.
test:
	LOUPPATH=$(CURDIR)/source:$(CURDIR)/tests$${LOUPPATH:+:$$LOUPPATH} $(LOUP_BOOTSTRAP) test --native --no-color $(TEST_ARGS)

# Native executable (needs clang).
build: $(BIN)

$(BIN): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(LOUP_BOOTSTRAP) build --target native -o $@

# End-to-end tests: run the built binary and check its output and exit
# status.
e2e: $(BIN)
	bash tests/e2e.sh $(BIN)

# Everything CI runs, ending with a smoke test of the built binary.
ci: check test build e2e
	$(BIN) --version

clean:
	rm -rf $(BUILD_DIR) .temp
