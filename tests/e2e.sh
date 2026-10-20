#!/usr/bin/env bash
# End-to-end tests: run the built binary and check its output and exit
# status. CPUs differ between machines (and CI runners), so the reports are
# checked for structure and sane values, not for exact text; where Linux's
# /proc/cpuinfo exists, the values are cross-checked against the kernel's.
#
# usage: tests/e2e.sh BINARY

set -u
BIN=$1
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); }
bad() {
    fail=$((fail + 1))
    echo "FAIL: $1"
    sed 's/^/    stdout: /' "$TMP/out" | head -5
    sed 's/^/    stderr: /' "$TMP/err" | head -5
}

# run ARGS...: runs BINARY with standard input from /dev/null; sets $status.
run() {
    "$BIN" "$@" < /dev/null > "$TMP/out" 2> "$TMP/err"
    status=$?
}

# check NAME STATUS EXPECTED_STDOUT [ARGS...]: exact standard output.
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    if [ "$status" -eq "$want_status" ] && cmp -s "$TMP/want" "$TMP/out"; then ok; else bad "$name (exit $status)"; fi
}

# check_err NAME STATUS EXPECTED_STDERR [ARGS...]: exact standard error and
# empty standard output.
check_err() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    if [ "$status" -eq "$want_status" ] && cmp -s "$TMP/want" "$TMP/err" && [ ! -s "$TMP/out" ]; then ok; else bad "$name (exit $status)"; fi
}

# has_line NAME REGEX: the last run's standard output has a line matching
# the extended regular expression.
has_line() {
    if grep -Eq -- "$2" "$TMP/out"; then ok; else bad "$1: no line matches /$2/"; fi
}

# all_lines NAME REGEX: every line of the last run's output matches.
all_lines() {
    if ! grep -Evq -- "$2" "$TMP/out" && [ -s "$TMP/out" ]; then ok; else bad "$1: a line does not match /$2/"; fi
}

# value KEY: the text after "KEY:" and the padding, from the last run.
value() {
    grep -E "^$1: " "$TMP/out" | head -1 | sed -E "s/^$1: +//"
}

# --- summary ---------------------------------------------------------------
run
[ "$status" -eq 0 ] && ok || bad "summary exit status $status"
for key in vendor brand family model stepping 'max leaf' hypervisor 'address sizes' flags; do
    has_line "summary field $key" "^$key: +[^ ]"
done
has_line "vendor is 12 characters"   '^vendor: +[^ ]{12}$'
has_line "family decimal and hex"    '^family: +[0-9]+ \(0x[0-9a-f]{2,}\)$'
has_line "model decimal and hex"     '^model: +[0-9]+ \(0x[0-9a-f]{2,}\)$'
has_line "stepping 0-15"             '^stepping: +([0-9]|1[0-5])$'
has_line "max leaves in hex"         '^max leaf: +0x[0-9a-f]+, extended 0x8[0-9a-f]{7}$'
has_line "address sizes"             '^address sizes: +([0-9]+ bits physical, [0-9]+ bits virtual|not reported)$'
has_line "flags include sse2"        '^flags: .* sse2( |$)'
has_line "an L1 data cache"          '^L1d cache: +[0-9]+ (KiB|MiB)'
has_line "an L2 or L3 cache"         '^L[23] cache: +[0-9]+ (KiB|MiB)'
if awk 'length > 80 { exit 1 }' "$TMP/out"; then ok; else bad "summary fits 80 columns"; fi

# The same values as the kernel's view of the processor, where it exists.
if [ -r /proc/cpuinfo ]; then
    cpuinfo() { grep -m1 -E "^$1[[:space:]]*:" /proc/cpuinfo | sed -E 's/^[^:]*: ?//'; }
    [ "$(value vendor)" = "$(cpuinfo vendor_id)" ] && ok || bad "vendor matches /proc/cpuinfo"
    [ "$(value brand)" = "$(cpuinfo 'model name')" ] && ok || bad "brand matches /proc/cpuinfo"
    [ "$(value family | cut -d' ' -f1)" = "$(cpuinfo 'cpu family')" ] && ok || bad "family matches /proc/cpuinfo"
    [ "$(value model | cut -d' ' -f1)" = "$(cpuinfo model)" ] && ok || bad "model matches /proc/cpuinfo"
    [ "$(value stepping)" = "$(cpuinfo stepping)" ] && ok || bad "stepping matches /proc/cpuinfo"
    kernel_flags=" $(cpuinfo flags) "
    for flag in fpu tsc cmov sse sse2 pni ssse3 sse4_1 sse4_2 popcnt lm; do
        run --has "$flag"
        case "$kernel_flags" in
            *" $flag "*) want=0 ;;
            *) want=1 ;;
        esac
        [ "$status" -eq "$want" ] && ok || bad "--has $flag agrees with /proc/cpuinfo (exit $status)"
    done
fi

# --- features --------------------------------------------------------------
run --features
[ "$status" -eq 0 ] && ok || bad "--features exit status $status"
[ "$(head -1 "$TMP/out")" = "flag                 has  cpuid             description" ] && ok || bad "--features header"
[ "$(wc -l < "$TMP/out")" -ge 90 ] && ok || bad "--features lists at least 90 flags"
has_line "sse2 row"   '^sse2 +yes +01H\.EDX\[26\] +SSE2$'
has_line "lm row"     '^lm +yes +80000001H\.EDX\[29\] '
sed 1d "$TMP/out" > "$TMP/rows" && mv "$TMP/rows" "$TMP/out"
all_lines "every flag row" '^[0-9a-z_]+ +(yes|no) +[0-9A-F]+H(\.[0-9])?\.E[ABCD]X\[[0-9]+\] +[^ ]'

# --- caches ----------------------------------------------------------------
run --caches
[ "$status" -eq 0 ] && ok || bad "--caches exit status $status"
all_lines "cache lines" '^L[1-4][di]? cache: +[0-9]+ (B|KiB|MiB)(, (fully associative|[0-9]+-way))?, [0-9]+-byte lines(, (1 thread|shared by [0-9]+ threads))?$'

# --- raw -------------------------------------------------------------------
run --raw
[ "$status" -eq 0 ] && ok || bad "--raw exit status $status"
[ "$(head -1 "$TMP/out")" = "leaf      sub  eax       ebx       ecx       edx" ] && ok || bad "--raw header"
[ "$(sed -n 2p "$TMP/out" | cut -c1-15)" = "00000000  0    " ] && ok || bad "--raw starts at leaf 0"
has_line "--raw extended leaves" '^80000000  0 '
sed 1d "$TMP/out" > "$TMP/rows" && mv "$TMP/rows" "$TMP/out"
all_lines "raw rows" '^[0-9a-f]{8}  [0-9] {1,3} ( [0-9a-f]{8} ){3} [0-9a-f]{8}$'

# --- bench -----------------------------------------------------------------
run --bench -n 2000
[ "$status" -eq 0 ] && ok || bad "--bench exit status $status"
has_line "TSC frequency" '^TSC: [0-9]+ MHz, (invariant|not invariant)'
has_line "bench header"  '^kernel +iterations +cycles/iter +ns/iter$'
for kernel in 'rdtsc' 'lfence\+rdtsc' 'cpuid' 'int add' 'int mul' 'int div' 'float add' 'list sum' 'pointer chase'; do
    has_line "bench $kernel" "^$kernel +[0-9]+ +[0-9]+\.[0-9]{2} +([0-9]+\.[0-9]{2}|-)$"
done
has_line "cpuid runs n/100" '^cpuid +20 '

# --- --has -----------------------------------------------------------------
check "--has sse2 (every x86-64 CPU)"   0 ''  --has sse2
check "--has=lm"                        0 ''  --has=lm
run --has amx_int8
{ [ "$status" -eq 0 ] || [ "$status" -eq 1 ]; } && [ ! -s "$TMP/out" ] && ok || bad "--has present or absent, silent"

# --- command line ----------------------------------------------------------
check "version" 0 $'cpuid (loup-cmd-cpuid) 0.1.0\n' --version
run --help
[ "$status" -eq 0 ] && [ "$(head -1 "$TMP/out")" = "usage: cpuid [OPTION]..." ] && ok || bad "--help"

try=$'Try \'cpuid --help\' for more information.\n'
check_err "unknown option"   2 "cpuid: unrecognized option '--bogus'"$'\n'"$try"  --bogus
check_err "two views"        2 $'cpuid: only one of --features, --caches, --raw, --bench and --has may be given\n'"$try"  -f -c
check_err "operand"          2 "cpuid: extra operand 'x'"$'\n'"$try"  x
check_err "unknown flag"     2 "cpuid: unknown flag 'AVX2' (see 'cpuid --features')"$'\n'"$try"  --has AVX2
check_err "-n without -b"    2 $'cpuid: option \'--iterations\' needs --bench\n'"$try"  -n 5
check_err "zero iterations"  2 "cpuid: iteration count must be from 1 to 1000000000: '0'"$'\n'"$try"  -b -n 0
check_err "missing value"    2 "cpuid: option '--has' requires an argument"$'\n'"$try"  --has

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
