# AGENTS.md

This repository is `cpuid`, a processor-identification and micro-benchmark
tool written in the Loup programming language, as part of the loup-cmd series
of example applications. It is a `host.native` project: every source file is
`.lphc`, and the `CPUID` and `RDTSC` instructions are issued from inline
`asm` blocks, which only `host.native` allows. It runs on x86-64 only.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership, execution
modes and projects, errors and diagnostics, the standard library, and common
mistakes (`freestanding.md` has the `asm` syntax). Load those only as needed.

## Code layout

```text
.
├── package.lppkg                # Loup manifest: name, version, toolchain, [build] entry, [test] pattern
├── Makefile                     # run, check, test, build, e2e, ci, clean
├── source/                      # all Loup code; modules import each other by path from here
│   ├── main.lphc                # entry point: func main() calls run(runtime.args())
│   ├── appinfo.lphc             # APP_NAME, APP_VERSION, APP_SUMMARY, exit statuses
│   ├── text.lphc                # hex(), pad_*(), fixed2(), size_text(), wrap_words()
│   ├── cli/
│   │   ├── args.lphc            # struct Options, parse_args(), parse_count()
│   │   ├── usage.lphc           # usage(), version_line()
│   │   └── app.lphc             # run(): parse, --help/--version, run_cpuid, exit status
│   ├── cpu/
│   │   ├── insn.lphc            # every asm block: cpuid(), rdtsc(), rdtsc_ordered(), keep(), opaque()
│   │   ├── snapshot.lphc        # Leaf, Snapshot, take_snapshot(), lookup()
│   │   ├── decode.lphc          # vendor(), brand(), signature(), feature_table(), caches()
│   │   └── bench.lphc           # benchmark kernels, measure_tsc_mhz(), run_benchmarks()
│   └── commands/
│       └── report.lphc          # render_summary/features/caches/raw/bench(), run_cpuid()
├── tests/
│   ├── *_test.lphc              # native unit tests: func test_*(): void
│   ├── samples.lphc             # recorded AMD and hand-built Intel snapshots, expect_text()
│   └── e2e.sh                   # end-to-end tests of the native binary
├── specs/cpuid/                 # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
├── .github/workflows/ci.yml     # installs Loup and runs `make ci`
└── build/                       # build output (git-ignored)
```

## Build, run and test

Prerequisites: Linux x86-64, Loup 1.26.0 (`loup` and `loup-bootstrap` on
`PATH`), `make`, and `clang` 17 or later.

| Task | Command | Notes |
|------|---------|-------|
| Run | `make run ARGS="--features"` | builds `build/cpuid`, then runs it: `loup run` cannot execute `asm` |
| Type-check | `make check` | checks `source/main.lphc` and every module it imports; tests are not checked |
| Run all tests | `make test` | every `tests/*_test.lphc`, each test built as a native binary (about 1 s each) |
| Run matching tests | `make test TEST_ARGS="--filter amd"` | tests whose name contains `amd` |
| Run one test file | `make test TEST_ARGS="--file tests/decode_test.lphc"` | |
| Build | `make build` | native binary at `build/cpuid` |
| End-to-end tests | `make e2e` | runs `tests/e2e.sh build/cpuid`: structure, sane values, `/proc/cpuinfo` cross-checks |
| Everything CI runs | `make ci` | check, test, build, e2e, then `build/cpuid --version` |
| Clean | `make clean` | removes `build/`, `.temp/` and `.loup-cache/` |

Run `make ci` before reporting a change as done.

The Makefile uses `loup-bootstrap` (Stage0) for every step:

- `check`: on Linux x86-64 the self-hosted `loup` refuses `check`.
- `build`: the self-hosted `loup build` refuses an `asm` block with more than
  one output (`loup-llbe: ... aggregate read from undefined`), and CPUID has
  four.
- `test`: Stage0 runs `host.native` test files through the native AOT
  pipeline, generating one temporary package per test file outside the
  repository. That is why `LOUPPATH` is absolute
  (`$(CURDIR)/source:$(CURDIR)/tests`); a relative path is ignored there.

## Making a change

1. Update the spec in `specs/cpuid/` (see [specs/README.md](specs/README.md)).
2. Change the code under `source/`.
3. Add or update unit tests in `tests/` and checks in `tests/e2e.sh`.
4. Run `make ci`.
5. Tick the finished tasks in `specs/cpuid/tasks.md`.

Keep machine code in `source/cpu/insn.lphc` and decoding pure: everything
after `take_snapshot()` is a function of a `Snapshot`, so tests can use the
samples in `tests/samples.lphc`. Only `run_cpuid` prints. The e2e tests must
not expect exact CPU values: CI runners have different processors.

## Conventions

- Every source file is `@mode(host.native)` with the `.lphc` extension. Only
  `source/main.lphc` has a `main()`.
- Every `asm` block carries `@unsafe("asm: <why it is safe>")`. Templates are
  Intel syntax; bind registers with constraints (`out: a = "=a"`,
  `in: "c" = x`). Operand references such as `$0` do not work.
- Modules import each other by path from `source/`:
  `from cpu.decode import (vendor);`. Tests import them the same way. Do not
  use relative imports.
- Struct fields read from another module must be `pub`.
- Loup 1.26.0 native-lane pitfalls this code works around:
  - `match` on a `string` always takes the `_` arm in Stage0 native code: use
    `if (s == "x") ... else if` chains.
  - A hex literal `match` pattern (`0xA =>`) never matches: write arms in
    decimal.
  - `expectEq` on two equal strings fails in native tests: use
    `expect_text(actual, expected, context)` from `tests/samples.lphc`.
  - A test file that does not compile (a reserved word such as `where` as a
    binding is enough) is skipped silently. A full `make test` therefore
    fails unless it ran every `test_` function; find the broken file with
    `LOUPPATH=source:tests loup-bootstrap run tests/FILE`.
- Keep `APP_VERSION` in `source/appinfo.lphc` equal to `version` in
  `package.lppkg`.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
