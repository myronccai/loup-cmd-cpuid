# Design: cpuid

## Overview

`main()` passes `runtime.args()` to `cli.app.run`, which parses the
arguments into `Options`, handles `--help` and `--version`, and calls
`commands.report.run_cpuid`. The program reads every CPUID leaf it needs
once, into a `Snapshot` (a list of `Leaf` records). Everything after that is
pure functions of the snapshot, which returns strings, so the tests can feed
recorded or hand-made register values to the decoder and check its output
without the instruction. Only `run_cpuid` prints.

All sources are `@mode(host.native)` `.lphc` files: the `asm` blocks in
`source/cpu/insn.lphc` are `E_ASM_NOT_COMPILED` in `host.dual`.

## Modules

| Module | Contents |
|---|---|
| `source/main.lphc` | entry point: `run(runtime.args())` |
| `source/appinfo.lphc` | name, version, summary, exit statuses |
| `source/cli/args.lphc` | `Options`, `parse_args`, `parse_count` |
| `source/cli/usage.lphc` | `usage()`, `version_line()` |
| `source/cli/app.lphc` | `run()`: parse, help/version, run, map exceptions to status 1 |
| `source/cpu/insn.lphc` | the only `asm`: `cpuid`, `rdtsc`, `rdtsc_ordered`, `keep`, `opaque` |
| `source/cpu/snapshot.lphc` | `Regs`, `Leaf`, `Snapshot`, `take_snapshot()`, `lookup()` |
| `source/cpu/decode.lphc` | vendor, brand, `Signature`, hypervisor, address sizes, the feature table, `CacheInfo` decoding |
| `source/cpu/bench.lphc` | the benchmark kernels, `measure_tsc_mhz`, `run_benchmarks` |
| `source/commands/text.lphc` | `hex`, padding, fixed-point and size formatting, word wrapping |
| `source/commands/report.lphc` | `render_summary`, `render_features`, `render_caches`, `render_raw`, `render_bench`, `run_cpuid` |

### The asm blocks

```loup
pub func cpuid(leaf: int, subleaf: int): Regs {
    var a = 0; var b = 0; var c = 0; var d = 0;
    @unsafe("asm: cpuid only reads processor identification registers")
    asm {
        "cpuid"
        out: a = "=a", b = "=b", c = "=c", d = "=d"
        in: "a" = leaf, "c" = subleaf
    }
    return Regs(eax = a, ebx = b, ecx = c, edx = d);
}
```

- `rdtsc` reads EDX:EAX; `rdtsc_ordered` puts `lfence` before it so that it
  does not run ahead of earlier instructions.
- `keep(x)` is an empty template with one input (`in: "r" = x`): the
  compiler must materialize `x` in a register on every iteration, so a
  benchmark loop cannot be folded into a closed form or deleted.
- `opaque(x)` is an empty template whose output is tied to its input's
  register (`out: r = "=a"`, `in: "a" = x`): the result equals `x`, but the
  optimizer cannot see that, so a divisor stays a real division.
- Each block carries `@unsafe("asm: ...")`, so `grep -rn 'unsafe(' source/`
  lists every unchecked claim.

### Snapshot

`take_snapshot` reads leaf 0 and 0x80000000 for the maxima, then each leaf in
the ranges of Requirement 4.2. Subleaf rules: leaf 4 and 0x8000001D stop at
cache type 0; leaf 7 reads subleaves up to EAX of subleaf 0 (at most 4); 0xB
and 0x1F stop at level type 0; 0xD reads subleaves 0 and 1. `lookup` returns
zero registers for a leaf that was not read, as the hardware does for most
out-of-range leaves.

### Decoding

- Vendor: EBX, EDX, ECX of leaf 0 as 12 ASCII bytes (little-endian per
  register). Brand: leaves 0x80000002–4, 48 bytes, NULs dropped, trimmed.
- Signature: leaf 1 EAX. `family = base + ext_family` if `base == 0xF`;
  `model = (ext_model << 4) + base_model` if `family >= 6`.
- Features: a table of `Feature(name, leaf, subleaf, reg, bit, desc)`;
  `features(snap)` returns `FeatureState` values in table order.
- Caches: Requirement 3.2. Leaf-4 format: type EAX[4:0], level EAX[7:5],
  fully associative EAX[9], threads EAX[25:14]+1, line EBX[11:0]+1,
  partitions EBX[21:12]+1, ways EBX[31:22]+1, sets ECX+1. Legacy AMD: L1 from
  0x80000005 ECX/EDX (KiB [31:24], ways [23:16], line [7:0]); L2 from
  0x80000006 ECX (KiB [31:16], way code [15:12]); L3 from EDX (512 KiB units
  [31:18], way code [15:12]).

### Benchmarks

Each kernel is a function `(n: int): int` that runs `n` iterations between
two `rdtsc_ordered` reads and returns the elapsed TSC cycles. `run_benchmarks`
runs each kernel 5 times and keeps the minimum. Results are kept as
hundredths of a cycle per iteration (integers) and printed with two decimals.
The pointer chase walks a single random cycle (Sattolo's algorithm with a
fixed-seed LCG) over 2^22 list entries (32 MiB), so each step is a cache miss.

## Differences from other CPUID tools

Not a port of one command: it combines what `cpuid`, `lscpu` and
`/proc/cpuinfo` show, with a much smaller decoder.

- Only the documented flags in the table are decoded; there is no
  per-model errata or microarchitecture name lookup.
- Flags are the raw CPUID bits. The Linux kernel can hide flags it disables
  (for example TSX), so `/proc/cpuinfo` may list fewer.
- Benchmark cycles are TSC reference cycles, not core clock cycles.
- x86-64 only; there is no ARM (`MIDR`) or other back end.

## Error handling

Usage errors give status 2. `--has` absent gives status 1, like `grep`.
An unexpected exception is reported as `cpuid: message` with status 1.

## Testing

All tests are `@mode(host.native)` and run through the native AOT pipeline
(`loup-bootstrap test --native`): the interpreter cannot execute `asm`.

- `tests/decode_test.lphc`: decoding of a recorded AMD Zen 4 snapshot and a
  hand-built Intel snapshot (vendor, brand trimming, signature, flags, leaf 4,
  0x8000001D and legacy caches).
- `tests/text_test.lphc`: hex, padding, fixed-point, sizes, wrapping.
- `tests/args_test.lphc`: options, values, conflicts, errors.
- `tests/live_test.lphc`: the real CPU: vendor length, SSE2 and LM present,
  at least one cache, a raw dump that starts with leaf 0, TSC monotonic.
- `tests/bench_test.lphc`: every kernel returns a positive cycle count.
- `tests/app_test.lphc`: exit statuses through `run()`.
- `tests/e2e.sh`: the built binary. Values differ between machines, so it
  checks structure (every field, sane ranges) and, where `/proc/cpuinfo`
  exists, that vendor, brand, family, model, stepping and a few stable flags
  agree with the kernel's view.
