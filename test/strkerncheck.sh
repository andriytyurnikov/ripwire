#!/usr/bin/env bash
# strkerncheck.sh — SIMD-vs-scalar parity gate for src/infra/strkern.h, and the tokenizer equivalence
# gate for the mask-driven walkers in src/lexindex.h.
#
# It drives the CMake target `ripwire_test_strkern` (test/verify_strkern.cpp), the repo's doctest form —
# DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN, one TEST_CASE per kernel, one CHECK/REQUIRE per assertion, built
# beside ripwire_test_csr / ripwire_test_pagerank / ripwire_test_radix. Until 2026-09-10 the same arms
# lived in a standalone test/strkern_harness.cpp (14 `checkf` arms) and test/emitescape_harness.cpp (4);
# the doctest target carries all 18 plus a compiled-path assertion and, since the #127 review round, a
# LexHeadIndex empty-bucket case; this gate prints both counts so a lost arm is arithmetic, not a
# feeling, and MIN_ASSERTIONS is a FLOOR, never an exact expectation.
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

# ── COMPILER PORTABILITY, read off the SOURCE (CodeRabbit #127 / 3985249663) ─────────────────────────
# The scalar twins are ALWAYS compiled and the vector paths compile under MSVC's /arch:AVX2, so no path in
# this header may use a GCC/Clang-only builtin. `__builtin_ctzll` was the whole population: MSVC has no
# such intrinsic, and the pending Windows port (PR #44) would not have compiled the file at all. The
# portable spelling is <bit>'s std::countr_zero, which is the same instruction everywhere and is DEFINED
# at zero where the builtin is undefined.
#
# This is a SOURCE arm, not a build arm, and deliberately so: the only compiler on this box accepts both
# spellings, so no local build can tell them apart — the difference is visible in the text or nowhere.
# CAN GO RED: put `__builtin_ctzll` back on any one of the eight sites and this arm fires.
# CODE lines only: the prose above names the retired builtin on purpose, and a gate that cannot tell a
# comment from a call site would forbid writing down what the rule is.
HDR="$ROOT/src/infra/strkern.h"
code_hits(){ grep -n "$1" "$HDR" 2>/dev/null | grep -vE '^[0-9]+: *(//|\*|/\*)'; }
BUILTINS="$( code_hits '__builtin_' | wc -l | tr -d ' ' )"
# `grep -c … || echo 0` printed "0" TWICE on a zero count (grep prints 0 AND exits 1), a two-line value
# `-lt` cannot compare — so the arm could PASS on the very count it exists to refuse (CodeRabbit on #127).
CTZ="$( grep -o 'std::countr_zero(' "$HDR" 2>/dev/null | wc -l | tr -d ' ' )"
if [ "$BUILTINS" != "0" ]; then
    echo "  FAIL  portability: src/infra/strkern.h uses $BUILTINS GCC/Clang-only __builtin_ — MSVC cannot compile it:"
    code_hits '__builtin_' | sed 's/^/        /' | head -10
    fail=1
elif [ "$CTZ" -lt 8 ]; then
    echo "  FAIL  portability: only $CTZ std::countr_zero( call sites in strkern.h — the eight trailing-zero"
    echo "        counts (2 scalar twins + 6 vector) are the population this arm is non-vacuous over"
    fail=1
else
    printf '  PASS  portability: 0 __builtin_ in strkern.h, %s std::countr_zero( sites (MSVC-compilable; <bit> included)\n' "$CTZ"
fi
if ! grep -q '^#include <bit>' "$HDR"; then
    echo "  FAIL  portability: strkern.h calls std::countr_zero without including <bit>"
    fail=1
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

# ── 2b: THE FAILING SWEEP MUST HAVE SWEPT THE SAME CORPUS (CodeRabbit #127 / 3985249745) ──────────────
# Arm 2's red run is only evidence about the SHIPPED kernels if the broken build walked the same buffers
# the green build walked. The sweep's probes draw from one shared DeterministicRng, so a probe skipped
# because its arm had already failed used to shorten the stream: every later buffer and every later probe
# input moved, and a second, independent divergence could be shifted out of the run entirely — the failure
# report then described a sweep nobody had ever seen green. verify_strkern.cpp now runs every probe
# unconditionally and keeps only the FIRST message per arm, which makes this comparison the proof.
#
# The line is `strkern sweep-rng: <state> buffers=<n>`; the state is the generator's, after the loop, so
# it is a pure function of how many draws were made. CAN GO RED: put the `if( r.<arm>Fail.empty() )`
# guards back and the mutated build — whose arms all fail on iteration 0 — prints a different state.
GREEN_RNG="$(  grep -m1 '^strkern sweep-rng: ' "$WORK/out_main.log"   2>/dev/null )"
MUTATE_RNG="$( grep -m1 '^strkern sweep-rng: ' "$WORK/out_mutate.log" 2>/dev/null )"
if [ -z "$GREEN_RNG" ] || [ -z "$MUTATE_RNG" ]; then
    echo "  FAIL  sweep corpus: no 'strkern sweep-rng:' line (green='$GREEN_RNG' mutated='$MUTATE_RNG')"
    fail=1
elif [ "$GREEN_RNG" = "$MUTATE_RNG" ]; then
    printf '  PASS  sweep corpus: the MUTATED build swept the same buffers as the green one (%s)\n' "$GREEN_RNG"
else
    echo "  FAIL  sweep corpus: a failing arm moved the RNG stream — the red run is not the green run's sweep"
    echo "        green   $GREEN_RNG"
    echo "        mutated $MUTATE_RNG"
    fail=1
fi

# A cross-arch slice that Rosetta 2 cannot run fails at EXEC (rc 126, "Bad CPU type in executable",
# "cannot execute binary file", "Exec format error"); that — and only that — is the environment saying
# no. A slice that RAN and exited nonzero (a doctest assertion, an abort) is a red, never a SKIP
# (CodeRabbit on #127: the old branch read every nonzero exit as "no Rosetta").
# A second environmental shape, seen on CI's macos-14 runners (PR #127 run 4): the slice DID execute under
# Rosetta 2 and died with SIGILL (rc 132) before printing its first line — Rosetta 2 gained AVX2 only in
# macOS 15, so a -march=x86-64-v3 slice on macOS 14 is illegal at its first vector instruction. That is
# the emulator lacking the ISA, not a kernel defect: SKIP, with the reason. A SIGILL AFTER the slice has
# printed (its path line, an assertion) is a real red and stays one.
exec_unavailable(){   # $1 = rc, $2 = output log
    [ "$1" = 126 ] && return 0
    grep -qE 'Bad CPU type|cannot execute binary file|Exec format error' "$2" && return 0
    if [ "$1" = 132 ] && ! grep -q 'strkern path' "$2"; then
        echo "        (SIGILL before the first line: this Rosetta 2 has no AVX2 — macOS 15+ runs the v3 slice; macOS 14 cannot)"
        return 0
    fi
    return 1
}

# ── 3: best-effort x86_64 / AVX2 mirror under Rosetta 2 ───────────────────────────────────────────────
# The x86-64 floor is -march=x86-64-v3 (AVX2 + BMI1/2 + FMA + LZCNT + MOVBE; CMakeLists.txt sets it
# unconditionally for x86-64 targets). Compiled without sanitizers — the ASan runtime for a cross-arch
# slice is not reliably present, and this arm's job is to run the AVX2 kernels at all, not to re-prove
# memory safety arm 1 already did.
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    if X86BIN="$( compile_direct x86 -arch x86_64 -march=x86-64-v3 )" && [ -n "$X86BIN" ]; then
        RIPWIRE_ROOT="$ROOT" "$X86BIN" > "$WORK/out_x86.log" 2>&1; rc_x86=$?
        if [ "$rc_x86" = 0 ]; then
            read_counts "$WORK/out_x86.log"
            if grep -q '^strkern path: AVX2$' "$WORK/out_x86.log"; then
                printf '  PASS  x86_64/AVX2 mirror runs green under Rosetta 2 (%s assertions)\n' "$ASSERTS"
            else
                echo "  FAIL  x86_64 slice built but did NOT compile the AVX2 path: $( grep '^strkern path: ' "$WORK/out_x86.log" )"
                fail=1
            fi
        elif exec_unavailable "$rc_x86" "$WORK/out_x86.log"; then
            printf '  SKIP  x86_64 slice built but cannot execute here (no Rosetta 2); CI ubuntu-24.04 is the AVX2 proof: %s\n' \
                   "$( tail -1 "$WORK/out_x86.log" )"
        else
            echo "  FAIL  x86_64/AVX2 mirror RAN and exited $rc_x86: $( tail -2 "$WORK/out_x86.log" | tr '\n' ' ' )"
            fail=1
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
        RIPWIRE_ROOT="$ROOT" UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 "$X86UB" > "$WORK/out_x86ub.log" 2>&1; rc_ub=$?
        if [ "$rc_ub" = 0 ]; then
            read_counts "$WORK/out_x86ub.log"
            printf '  PASS  x86_64/AVX2 mirror is clean under -fsanitize=undefined,integer (%s assertions)\n' "$ASSERTS"
        elif grep -q 'runtime error' "$WORK/out_x86ub.log"; then
            echo "  FAIL  x86_64/AVX2 mirror trips UBSan integer checks: $( grep -m1 'runtime error' "$WORK/out_x86ub.log" | sed 's|.*/src/|src/|' )"
            fail=1
        elif exec_unavailable "$rc_ub" "$WORK/out_x86ub.log"; then
            printf '  SKIP  x86_64 UBSan slice built but cannot execute here (no Rosetta 2): %s\n' "$( tail -1 "$WORK/out_x86ub.log" )"
        else
            echo "  FAIL  x86_64 UBSan slice RAN and exited $rc_ub without a sanitizer report: $( tail -2 "$WORK/out_x86ub.log" | tr '\n' ' ' )"
            fail=1
        fi
        # 3c CONTROL — a slice that runs and FAILS must read as FAIL, never as "no Rosetta": the x86_64 build
        # of the mutation (arm 2's -DSTRKERN_MUTATE=1) is exactly that binary.
        if X86MUT="$( compile_direct x86mut -arch x86_64 -march=x86-64-v3 -DSTRKERN_MUTATE=1 )" && [ -n "$X86MUT" ]; then
            RIPWIRE_ROOT="$ROOT" "$X86MUT" > "$WORK/out_x86mut.log" 2>&1; rc_mut=$?
            if [ "$rc_mut" != 0 ] && ! exec_unavailable "$rc_mut" "$WORK/out_x86mut.log"; then
                echo "  PASS  3c control: the mutated x86_64 slice RAN and failed (rc=$rc_mut) — a red, classified as a red, not a SKIP"
            elif exec_unavailable "$rc_mut" "$WORK/out_x86mut.log"; then
                echo "  SKIP  3c control: the mutated x86_64 slice cannot execute here either (no Rosetta 2)"
            else
                echo "  FAIL  3c control: the mutated x86_64 slice exited 0 — the mutation is not visible on the AVX2 path"
                fail=1
            fi
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
