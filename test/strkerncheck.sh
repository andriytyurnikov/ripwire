#!/usr/bin/env bash
# strkerncheck.sh — SIMD-vs-scalar parity gate for src/infra/strkern.h, and the tokenizer equivalence
# gate for the mask-driven walkers in src/lexindex.h.
#
# It drives the CMake target `ripwire_test_strkern` (test/verify_strkern.cpp), the repo's doctest form —
# DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN, one TEST_CASE per kernel, one CHECK/REQUIRE per assertion, built
# beside ripwire_test_csr / ripwire_test_pagerank / ripwire_test_radix. Until 2026-09-10 the same arms
# lived in a standalone test/strkern_harness.cpp (14 `checkf` arms) and test/emitescape_harness.cpp (4);
# the doctest target carries all 18 plus one — a compiled-path assertion — and this gate prints both
# counts so a lost arm is arithmetic, not a feeling.
#
# THE TARGET IS BUILT THREE TIMES, and each build is a different question:
#
#   1  CMAKE, FULL G1 SANITIZERS.  `cmake -DRIPWIRE_TESTS=ON -DRIPWIRE_ASAN=ON` in a scratch dir, then
#      `--target ripwire_test_strkern`. This is the arm that proves the SHIPPED target builds and runs —
#      the same target `ctest` runs — under -fsanitize=address,undefined,integer,float-* with
#      -fno-sanitize-recover=all, so a nibble-table read one lane past the end ABORTS rather than
#      reporting and exiting 0. It runs EVERY test case in the TU (kernels and escapers both): this is
#      the G1 arm for the whole file, which is why test/emitescapecheck.sh does not build a second
#      sanitized copy of the same source to re-prove it.
#   2  DIRECT $CXX, -DSTRKERN_MUTATE=1.  CAN GO RED. The mutation flips one bit of the SIMD-only nibble
#      table, narrows the fold's range by one, drops findByteset's high half, and drops the high half of
#      the set from Byteset256::words. That build MUST fail. If it passes, every parity assertion above
#      is unbinding and this gate is decoration. A compile flag, not a build type — a second CMake
#      configure to pass one -D would cost a configure to say nothing extra.
#   3  DIRECT $CXX, `-arch x86_64 -march=x86-64-v3`, run under Rosetta 2.  BEST EFFORT. CMake cannot
#      express a second architecture for one target inside this tree, so this arm compiles the same
#      source the way the pre-doctest gate did. It is a SKIP, never a failure, when the SDK or Rosetta is
#      unavailable — the authoritative AVX2 proof is the ubuntu-24.04 CI leg.
#
# NON-VACUITY sits between 1 and 2: on arm64 the banner must say NEON, on x86-64 AVX2. A scalar-only
# build on those arches would compare the oracle to itself and pass while proving nothing.
#
# Independent of the ripwire binary and of main.cpp (pinned in test/binoverridecheck.sh's EXEMPT dict).
# Usage:  bash test/strkerncheck.sh            (compiles with c++/clang++)
#         CXX=clang++ bash test/strkerncheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"

# ask THIS front end how it spells C++23 (see scripts/cxxstd.sh — AppleClang 15 rejects -std=c++23)
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
SRC="$ROOT/test/verify_strkern.cpp"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
ARCH="$( uname -m )"
fail=0

# The arm counts the two standalone harnesses carried before 2026-09-10, kept here so this gate can state
# the before/after rather than assert the after alone. 14 + 4; the doctest target adds the compiled-path
# assertion, so 19 is the floor below.
LEGACY_STRKERN_ARMS=14
LEGACY_ESCAPE_ARMS=4
MIN_ASSERTIONS=19

echo "strkerncheck: CXX=$CXX arch=$ARCH  target=ripwire_test_strkern"

# ── 1: the CMake target, under the complete G1 sanitizer stack ────────────────────────────────────────
# FETCHCONTENT_FULLY_DISCONNECTED=ON because every dependency is vendored: a gate must not reach the
# network, and if one ever tries, this is where it fails loudly instead of hanging.
if ! cmake -S "$ROOT" -B "$WORK/cmb" -DRIPWIRE_TESTS=ON -DRIPWIRE_ASAN=ON \
        -DFETCHCONTENT_FULLY_DISCONNECTED=ON > "$WORK/cfg.log" 2>&1; then
    echo "  FAIL  cmake configure (-DRIPWIRE_TESTS=ON -DRIPWIRE_ASAN=ON) failed"
    tail -20 "$WORK/cfg.log" | sed 's/^/    /'
    exit 2
fi
if ! cmake --build "$WORK/cmb" --target ripwire_test_strkern -j 2 > "$WORK/build.log" 2>&1; then
    echo "  FAIL  ripwire_test_strkern failed to build under the G1 sanitizers"
    tail -30 "$WORK/build.log" | sed 's/^/    /'
    exit 2
fi

# Apple's arm64 runtime rejects LeakSanitizer at startup; mirror CMakeLists.txt's platform policy rather
# than claiming a leak check that cannot run (see the note beside ripwire_asan_fixture there).
if [ "$( uname -s )" = "Darwin" ]; then
    ASAN_OPTS="detect_leaks=0:halt_on_error=1:abort_on_error=1"
else
    ASAN_OPTS="detect_leaks=1:halt_on_error=1:abort_on_error=1"
fi
ASAN_OPTIONS="$ASAN_OPTS" UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
    LSAN_OPTIONS="suppressions=$ROOT/lsan_suppressions.txt" RIPWIRE_ROOT="$ROOT" \
    "$WORK/cmb/ripwire_test_strkern" > "$WORK/out_main.log" 2>&1
rc=$?

# doctest's own tally line is the arm count: "[doctest] assertions: N | N passed | K failed |"
read_counts()   # $1 = log; sets CASES, CASES_PASS, ASSERTS, ASSERTS_FAIL
{
    CASES="$(      sed -n 's/^\[doctest\] test cases: *\([0-9][0-9]*\) .*/\1/p'                "$1" | tail -1 )"
    CASES_PASS="$( sed -n 's/^\[doctest\] test cases: *[0-9][0-9]* | *\([0-9][0-9]*\) passed.*/\1/p' "$1" | tail -1 )"
    ASSERTS="$(    sed -n 's/^\[doctest\] assertions: *\([0-9][0-9]*\) .*/\1/p'                "$1" | tail -1 )"
    ASSERTS_FAIL="$( sed -n 's/.*| *\([0-9][0-9]*\) failed |$/\1/p'                            "$1" | tail -1 )"
    : "${CASES:=0}" "${CASES_PASS:=0}" "${ASSERTS:=0}" "${ASSERTS_FAIL:=0}"
}
read_counts "$WORK/out_main.log"

if [ "$rc" -ne 0 ] || [ "${ASSERTS_FAIL:-1}" != "0" ]; then
    echo "  FAIL  parity/equivalence assertion failed (exit $rc, $ASSERTS_FAIL failed):"
    grep -B 2 -A 6 'ERROR\|FAILED' "$WORK/out_main.log" | sed 's/^/    /' | head -40
    exit 2
fi
if [ "$ASSERTS" -lt "$MIN_ASSERTIONS" ]; then
    echo "  FAIL  the doctest target ran $ASSERTS assertions; the two harnesses it replaced carried"
    echo "        $LEGACY_STRKERN_ARMS + $LEGACY_ESCAPE_ARMS = $(( LEGACY_STRKERN_ARMS + LEGACY_ESCAPE_ARMS )), and the target must be >= $MIN_ASSERTIONS."
    echo "        An arm was deleted, or a TEST_CASE stopped being registered."
    exit 2
fi
printf '  PASS  %s test cases / %s assertions green under the full G1 sanitizers (was %s + %s arms in two standalone harnesses) (%s)\n' \
       "$CASES" "$ASSERTS" "$LEGACY_STRKERN_ARMS" "$LEGACY_ESCAPE_ARMS" \
       "$( grep '^strkern: path=' "$WORK/out_main.log" | sed 's/strkern: //' )"

WANT=""
case "$ARCH" in
    arm64|aarch64) WANT="NEON" ;;
    x86_64|amd64)  WANT="AVX2" ;;
esac
if [ -n "$WANT" ]; then
    if grep -q "^strkern path: $WANT$" "$WORK/out_main.log"; then
        printf '  PASS  non-vacuity: %s on %s\n' "$( grep '^strkern path: ' "$WORK/out_main.log" )" "$ARCH"
    else
        echo "  FAIL  non-vacuity ($ARCH must compile the $WANT path; banner says '$( grep '^strkern path: ' "$WORK/out_main.log" )')"
        echo "        a scalar-only build here compares the oracle to itself — the parity arms prove nothing"
        fail=1
    fi
fi

# compile one flavour of the target directly; $1 = label, remaining args = extra compile flags. Echoes the
# binary path on success, nothing on failure (the caller decides whether a compile failure is fatal).
compile_direct()
{
    local LABEL="$1"; shift
    local BIN="$WORK/verify_$LABEL"
    if ! "$CXX" "$CXXSTD" -O2 -g -Wall -Wextra "$@" \
            -I"$ROOT/src/infra" -I"$ROOT/src" -I"$ROOT/third_party" -I"$ROOT/third_party/deps/doctest" \
            -DRIPWIRE_TEST_ROOT="\"$ROOT\"" \
            "$SRC" "$ROOT/src/infra/diagnostics.cpp" -o "$BIN" 2> "$WORK/cc_$LABEL.log"; then
        return 1
    fi
    printf '%s\n' "$BIN"
}

# ── 2: CAN GO RED ─────────────────────────────────────────────────────────────────────────────────────
# The mutation touches ONLY code inside `#if defined( STRKERN_MUTATE )` in src/infra/strkern.h, so a red
# run here is a parity assertion biting, not a broken build. Sanitizers are off for this arm: it is
# expected to fail, and we want it to fail on the assertion, not on a slow abort.
REDBIN="$( compile_direct mutate -DSTRKERN_MUTATE=1 )"
if [ -z "$REDBIN" ]; then
    echo "  FAIL  can-go-red arm failed to COMPILE (the mutation must build, then fail at runtime)"
    sed 's/^/    /' "$WORK/cc_mutate.log" | head -20
    fail=1
elif RIPWIRE_ROOT="$ROOT" "$REDBIN" > "$WORK/out_mutate.log" 2>&1; then
    echo "  FAIL  can-go-red: -DSTRKERN_MUTATE=1 build PASSED — the parity assertions are not binding"
    fail=1
else
    read_counts "$WORK/out_mutate.log"
    printf '  PASS  can-go-red: -DSTRKERN_MUTATE=1 fails %s of %s assertions as designed\n' "$ASSERTS_FAIL" "$ASSERTS"
fi

# ── 3: best-effort x86_64 / AVX2 mirror under Rosetta 2 ───────────────────────────────────────────────
# The x86-64 floor is -march=x86-64-v3 (AVX2 + BMI1/2 + FMA + LZCNT + MOVBE; CMakeLists.txt sets it
# unconditionally for x86-64 targets). Compiled without sanitizers — the ASan runtime for a cross-arch
# slice is not reliably present, and this arm's job is to run the AVX2 kernels at all, not to re-prove
# memory safety arm 1 already did.
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    if X86BIN="$( compile_direct x86 -arch x86_64 -march=x86-64-v3 )" && [ -n "$X86BIN" ]; then
        if RIPWIRE_ROOT="$ROOT" "$X86BIN" > "$WORK/out_x86.log" 2>&1; then
            read_counts "$WORK/out_x86.log"
            if grep -q '^strkern path: AVX2$' "$WORK/out_x86.log"; then
                printf '  PASS  x86_64/AVX2 mirror runs green under Rosetta 2 (%s assertions)\n' "$ASSERTS"
            else
                echo "  FAIL  x86_64 slice built but did NOT compile the AVX2 path: $( grep '^strkern path: ' "$WORK/out_x86.log" )"
                fail=1
            fi
        else
            printf '  SKIP  x86_64 slice built but did not run here (no Rosetta 2, or it aborted); CI ubuntu-24.04 is the AVX2 proof: %s\n' \
                   "$( tail -2 "$WORK/out_x86.log" | tr '\n' ' ' )"
        fi
    else
        printf '  SKIP  no x86_64 cross slice on this toolchain (no macOS x86_64 SDK); CI ubuntu-24.04 is the AVX2 proof\n'
    fi
fi

# ── 3b: the x86_64 slice under UBSan's integer checks — the arm that CI's ubuntu ASan leg is ────────────
# The 32-byte AVX2 block fills every bit of a uint32 mask, so a `<< 1` that is harmless on a 16-byte NEON
# mask (top half always zero) DROPS a set bit on AVX2, and -fsanitize=integer's unsigned-shift-base check
# aborts on exactly that (PR #127's first CI run: lexindex.h:186 on --for/--pack-task, clean on every arm64
# ASan run). Arm 3 compiled without sanitizers and could not see it. UBSan's runtime is a universal dylib
# in the Apple toolchain, so the cross slice CAN carry -fsanitize=undefined,integer; ASan stays off here
# (arm 1 owns memory safety on the host ISA). A sanitizer report is a FAIL; a slice that will not run at
# all (no Rosetta 2) is a SKIP, as in arm 3.
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    if X86UB="$( compile_direct x86ub -arch x86_64 -march=x86-64-v3 -fsanitize=undefined,integer -fno-sanitize-recover=all )" && [ -n "$X86UB" ]; then
        if RIPWIRE_ROOT="$ROOT" UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 "$X86UB" > "$WORK/out_x86ub.log" 2>&1; then
            read_counts "$WORK/out_x86ub.log"
            printf '  PASS  x86_64/AVX2 mirror is clean under -fsanitize=undefined,integer (%s assertions)\n' "$ASSERTS"
        elif grep -q 'runtime error' "$WORK/out_x86ub.log"; then
            echo "  FAIL  x86_64/AVX2 mirror trips UBSan integer checks: $( grep -m1 'runtime error' "$WORK/out_x86ub.log" | sed 's|.*/src/|src/|' )"
            fail=1
        else
            printf '  SKIP  x86_64 UBSan slice built but did not run here (no Rosetta 2): %s\n' "$( tail -1 "$WORK/out_x86ub.log" )"
        fi
    else
        printf '  SKIP  no x86_64 UBSan cross slice on this toolchain; CI ubuntu-24.04 asan is the proof\n'
    fi
fi

if [ "$fail" = 0 ]; then
    echo "strkerncheck: PASS"
else
    echo "strkerncheck: FAILURES ABOVE"
fi
exit "$fail"
