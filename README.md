# loup-cmd-cpuid

Ask an x86-64 processor what it is, in [Loup](https://code-craft.ai/references/loup):
vendor, brand string, family/model/stepping, feature flags (SSE to AVX-512,
AES, SHA, ...) and cache hierarchy straight from the `CPUID` instruction, plus
a micro-benchmark mode that times instructions and loops with `RDTSC`.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.native` (host-compiled) project.

**x86-64 only.** The instructions are x86-64 machine code; the program builds
and runs on Linux x86-64.

## What this example shows

- **Inline `asm` with register constraints.** `source/cpu/insn.lphc` holds
  every instruction the program issues. CPUID takes EAX and ECX and returns
  four registers, all bound to Loup variables in one block:

  ```loup
  @unsafe("asm: cpuid only reads processor identification registers")
  asm {
      "cpuid"
      out: a = "=a", b = "=b", c = "=c", d = "=d"
      in: "a" = leaf, "c" = subleaf
  }
  ```

  `asm` is the reason this is `host.native`: in a `host.dual` file the same
  block is `E_ASM_NOT_COMPILED`, and the interpreter (`loup run`) cannot
  execute it at all. Each block carries an `@unsafe("asm: ...")` reason, so
  `grep -rn 'unsafe(' source/` lists every unchecked claim.
- **Asm as an optimizer barrier.** The benchmark loops would be deleted or
  folded into a formula by LLVM. `keep(x)` (an empty template with
  `in: "r" = x`) forces each result into a register, and `opaque(x)` (an
  empty template whose output is tied to its input register) hides a
  divisor so that a division stays a division.
- **Pure decoding behind one snapshot.** All CPUID leaves are read once into a
  `Snapshot`; everything else is a pure function of it. The unit tests feed
  the decoder a recorded AMD Zen 4 snapshot and a hand-built Intel one, so the
  Intel and legacy-AMD cache paths are tested on any machine.
- **Native tests.** The tests are `host.native` too, so `loup-bootstrap test
  --native` compiles each `test_*` function into its own binary and runs it.
- **Why compile:** the benchmark counts single cycles of machine code; an
  interpreter's dispatch loop would bury them.

## Requirements

- Linux x86-64.
- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later; see [Installing Loup Lite](#installing-loup-lite).
- `make`, and `clang` 17 or later for the native build.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. The full release is at
<https://code-craft.ai/loup/download>, and commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make build                    # native binary: build/cpuid
make ci                       # check, native unit tests, build, end-to-end tests
make run ARGS="--features"    # build, then run with ARGS
```

The summary (on an AMD Ryzen 9 7940HS):

```text
$ build/cpuid
vendor:        AuthenticAMD
brand:         AMD Ryzen 9 7940HS w/ Radeon 780M Graphics
family:        25 (0x19)
model:         116 (0x74)
stepping:      1
max leaf:      0x10, extended 0x80000028
hypervisor:    none
address sizes: 48 bits physical, 48 bits virtual
flags:         fpu tsc cx8 cmov clflush mmx fxsr sse sse2 ht pni pclmulqdq
               monitor ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave
               osxsave avx f16c rdrand fsgsbase bmi1 avx2 smep bmi2 erms invpcid
               avx512f avx512dq rdseed adx smap avx512ifma clflushopt clwb
               avx512cd sha_ni avx512bw avx512vl avx512vbmi umip pku
               avx512_vbmi2 gfni vaes vpclmulqdq avx512_vnni avx512_bitalg
               avx512_vpopcntdq rdpid fsrm avx512_bf16 lahf_lm svm abm sse4a
               3dnowprefetch topoext syscall nx mmxext pdpe1gb rdtscp lm
               nonstop_tsc
L1d cache:     32 KiB, 8-way, 64-byte lines, shared by 2 threads
L1i cache:     32 KiB, 8-way, 64-byte lines, shared by 2 threads
L2 cache:      1 MiB, 8-way, 64-byte lines, shared by 2 threads
L3 cache:      16 MiB, 16-way, 64-byte lines, shared by 16 threads
```

Every known flag, with where it lives (Intel SDM notation) and what it is:

```text
$ build/cpuid --features
flag                 has  cpuid             description
fpu                  yes  01H.EDX[0]        x87 floating-point unit
tsc                  yes  01H.EDX[4]        time-stamp counter (RDTSC)
cx8                  yes  01H.EDX[8]        CMPXCHG8B
...
fsgsbase             yes  07H.0.EBX[0]      RDFSBASE, WRFSBASE and friends
bmi1                 yes  07H.0.EBX[3]      bit manipulation set 1
hle                  no   07H.0.EBX[4]      TSX hardware lock elision
avx2                 yes  07H.0.EBX[5]      AVX2
...
```

The raw registers, and a scripting check:

```text
$ build/cpuid --raw | head -4
leaf      sub  eax       ebx       ecx       edx
00000000  0    00000010  68747541  444d4163  69746e65
00000001  0    00a70f41  06100800  7ef8320b  178bfbff
00000002  0    00000000  00000000  00000000  00000000
$ build/cpuid --has avx512f && echo yes
yes
$ build/cpuid --has amx_tile || echo no
no
```

The micro-benchmarks (each kernel's fastest of five runs; cycles are TSC
reference cycles, not core clock cycles):

```text
$ build/cpuid --bench
TSC: 3992 MHz, invariant
best of 5 runs, in TSC reference cycles

kernel          iterations  cycles/iter    ns/iter
rdtsc              1000000        32.91       8.24
lfence+rdtsc       1000000        63.71      15.95
cpuid                10000       207.05      51.86
int add            1000000         0.98       0.24
int mul            1000000         2.96       0.74
int div            1000000        12.91       3.23
float add          1000000         2.98       0.74
list sum           1000000         2.96       0.74
pointer chase      1000000       445.06     111.48
```

`int add`, `int mul`, `int div` and `float add` are dependent chains, so they
show latency; `pointer chase` follows a random cycle through 32 MiB, so each
step is a cache miss. In a virtual machine `cpuid` traps to the hypervisor and
costs thousands of cycles.

## Options

| Option | Meaning |
|---|---|
| (none) | the summary above |
| `-f`, `--features` | every known flag: name, `yes`/`no`, CPUID location, description |
| `-c`, `--caches` | the cache lines of the summary only |
| `-r`, `--raw` | the raw leaves and subleaves in hexadecimal |
| `-b`, `--bench` | the micro-benchmarks |
| `-n N`, `--iterations=N` | iterations per benchmark run (default 1000000; `cpuid` runs N/100) |
| `--has=FLAG` | print nothing; exit 0 if the flag is present, 1 if not |
| `-h`, `--help`, `-V`, `--version` | help, version |

Only one of `-f`, `-c`, `-r`, `-b` and `--has` may be given. Flag names are
the Linux `/proc/cpuinfo` names (`pni` for SSE3, `sha_ni`, `abm` for LZCNT,
`sse4_1`), so the output can be compared with the kernel's.

Exit status: `0` success, `1` `--has` found the flag absent (or an error),
`2` usage error.

## Limits

- x86-64 only; there is no back end for other architectures.
- Flags are the raw CPUID bits. Linux can hide flags it disables (TSX's `hle`
  and `rtm`, for example), so `/proc/cpuinfo` may list fewer; `osxsave` is
  never listed there.
- Only the flags in the table are decoded: no microarchitecture names, no
  topology (leaves 0xB and 0x1F are dumped by `--raw` but not decoded).
- Cache sharing comes from leaf 4 or 0x8000001D; the legacy AMD leaves do
  not report it.
- Benchmark cycles are TSC reference cycles: with turbo the core clock runs
  faster than the TSC, so a one-cycle add can show below 1.00.

## Layout

```text
source/main.lphc              # entry point
source/appinfo.lphc           # name, version, exit statuses
source/text.lphc              # hex, padding, fixed-point and size formatting
source/cli/args.lphc          # options
source/cli/usage.lphc         # --help and --version text
source/cli/app.lphc           # run(): parse, dispatch, exit status
source/cpu/insn.lphc          # every asm block: cpuid, rdtsc, keep, opaque
source/cpu/snapshot.lphc      # read all leaves once
source/cpu/decode.lphc        # vendor, brand, signature, flags, caches
source/cpu/bench.lphc         # benchmark kernels and TSC frequency
source/commands/report.lphc   # the views; run_cpuid
tests/*_test.lphc             # native unit tests (make test)
tests/samples.lphc            # recorded and hand-built snapshots for the tests
tests/e2e.sh                  # end-to-end tests of build/cpuid (make e2e)
specs/cpuid/                  # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.
