# Requirements: cpuid

## Introduction

`cpuid` reports what an x86-64 processor says about itself through the
`CPUID` instruction: vendor, brand string, family/model/stepping, feature
flags and the cache hierarchy. It also times a few instructions and loops
with the time-stamp counter (`RDTSC`). It is the first host-compiled
(`host.native`) project in the loup-cmd series: the two instructions are
issued from inline `asm` blocks, which only `host.native` (and
`freestanding`) Loup allows. The program runs on x86-64 only.

## Requirements

### Requirement 1: Summary

**User Story:** As a developer, I want a one-screen summary of my processor
so that I know what I am running on.

#### Acceptance Criteria

1. WHEN cpuid is run with no options, THE program SHALL print the lines
   `vendor:`, `brand:`, `family:`, `model:`, `stepping:`, `max leaf:`,
   `hypervisor:`, `address sizes:`, `flags:` and one `<label> cache:` line
   per cache, and exit with status 0.
2. THE program SHALL compute the family and model the way the Linux kernel
   does: the extended family is added when the base family is 0xF, and the
   extended model is prepended when the family is 6 or more.
3. THE program SHALL print the brand string with leading and trailing
   blanks removed, or `(not reported)` when the extended leaves are absent.
4. WHEN leaf 1 reports a hypervisor, THE program SHALL print the hypervisor
   vendor from leaf 0x40000000; otherwise `none`.
5. THE `flags:` line SHALL list the names of the known flags that are
   present, in table order, wrapped to 80 columns.

### Requirement 2: Feature flags

**User Story:** As a developer, I want to see every feature flag the program
knows, with where it comes from, so that I can check for an instruction set.

#### Acceptance Criteria

1. WHEN `-f` / `--features` is given, THE program SHALL print one line per
   known flag: name, `yes`/`no`, its CPUID location in SDM notation
   (`01H.EDX[26]`), and a description.
2. THE known flags SHALL cover at least SSE to SSE4.2, AVX, AVX2, FMA, the
   AVX-512 subsets, AES, PCLMULQDQ, SHA, BMI1/2, ADX, RDRAND, RDSEED, and the
   extended-leaf flags (LM, NX, RDTSCP, LZCNT, SSE4A).
3. THE flag names SHALL be the Linux `/proc/cpuinfo` names (`pni` for SSE3,
   `sha_ni`, `abm`, `sse4_1`), so the output can be compared with
   `/proc/cpuinfo`.
4. WHEN `--has FLAG` is given, THE program SHALL print nothing and exit with
   status 0 if the flag is present and 1 if it is not; an unknown flag name
   SHALL be a usage error.

### Requirement 3: Caches

**User Story:** As a developer tuning code, I want the cache sizes and
geometry.

#### Acceptance Criteria

1. WHEN `-c` / `--caches` is given, THE program SHALL print one line per
   cache: label (`L1d`, `L1i`, `L2`, `L3`), size, associativity, line size,
   and the number of threads sharing it when reported.
2. THE program SHALL read the deterministic cache leaf 4 when it reports
   caches, else AMD's leaf 0x8000001D, else AMD's legacy leaves 0x80000005
   and 0x80000006.
3. THE size SHALL be ways × partitions × line size × sets, printed in KiB or
   MiB.

### Requirement 4: Raw leaves

**User Story:** As someone debugging the decoder, I want the raw registers.

#### Acceptance Criteria

1. WHEN `-r` / `--raw` is given, THE program SHALL print a header line and
   one line per leaf and subleaf read: leaf, subleaf, EAX, EBX, ECX, EDX as
   8-digit hexadecimal.
2. THE program SHALL read the basic leaves up to the reported maximum
   (capped at 0x20), the hypervisor leaves when present (capped at
   0x40000010), and the extended leaves (capped at 0x80000028), with the
   subleaves of leaves 4, 7, 0xB, 0xD, 0x1F and 0x8000001D.

### Requirement 5: Micro-benchmarks

**User Story:** As a developer, I want to see what a few instructions cost in
cycles.

#### Acceptance Criteria

1. WHEN `-b` / `--bench` is given, THE program SHALL time each kernel (RDTSC,
   LFENCE+RDTSC, CPUID, dependent integer add, multiply and divide chains, a
   dependent float add chain, a sequential list sum and a random pointer
   chase) and print the best of 5 runs as TSC cycles and nanoseconds per
   iteration.
2. WHEN `-n N` / `--iterations N` is given, THE program SHALL run N
   iterations per run (default 1000000; CPUID runs N/100, at least 1).
3. THE program SHALL measure the TSC frequency against the monotonic clock
   and say whether the TSC is invariant.
4. THE kernels SHALL keep their results alive with an empty `asm` barrier so
   that the optimizer cannot delete or fold the loops.

### Requirement 6: Command line

**User Story:** As a shell user, I want the usual conventions.

#### Acceptance Criteria

1. WHEN `-h` / `--help` is given, THE program SHALL print the help text and
   exit with status 0; `-V` / `--version` SHALL print
   `cpuid (loup-cmd-cpuid) 0.1.0`.
2. WHEN an option is unknown, a value is missing or not a positive integer
   (at most 1000000000), an operand is given, or more than one of `-f`,
   `-c`, `-r`, `-b` and `--has` is given, THE program SHALL print
   `cpuid: MESSAGE` and `Try 'cpuid --help' for more information.` on
   standard error and exit with status 2.
3. THE program SHALL accept `--iterations=N` and `--has=FLAG` as well as
   the value in the next argument.
